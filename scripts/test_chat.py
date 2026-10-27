#!/usr/bin/env python3
"""Real chat CLI -> portable C Pico bridge -> existing Z80/8251 -> chat.asm.
HTTP cases use an independent chunked Ollama server. No physical GPIO access.
"""
import contextlib
import http.server
import json
import os
from pathlib import Path
import signal
import subprocess
import termios
import threading
import time
import unittest
import sys

LIVE = '--live-ollama' in sys.argv
if LIVE:
    sys.argv.remove('--live-ollama')

from test_deploy import BINARY, FLAGS, OUT, device, run


@contextlib.contextmanager
def provider(stall=False):
    requests = []
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_POST(self):
            body = self.rfile.read(int(self.headers['Content-Length']))
            requests.append(json.loads(body))
            self.send_response(200)
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            if stall:
                time.sleep(2)
                return
            try:
                for text, done in [('HELLO!\n', False), ('I AM GEMMA.\n', False), ('NICE TO MEET YOU.', True)]:
                    data = (json.dumps({'message': {'content': text}, 'done': done}) + '\n').encode()
                    # Deliberately split JSON across HTTP chunks, including in
                    # the middle of escaped strings, not just at JSON boundaries.
                    for chunk in (data[:13], data[13:]):
                        self.wfile.write(f'{len(chunk):x}\r\n'.encode()+chunk+b'\r\n')
                        self.wfile.flush()
                    time.sleep(.4)
                self.wfile.write(b'0\r\n\r\n')
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f'http://127.0.0.1:{server.server_port}', requests
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def command(port, *extra):
    return [BINARY, 'chat', *FLAGS, '--port', port, *extra]


class ChatTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([BINARY, 'asm', 'examples/pc8001/hello.asm', '-o', str(OUT/'hello.bin')], capture_output=True)
        assert result.returncode == 0, result.stderr

    def check_chat(self, fault='chat', *extra, strict=True, record=None):
        with device(fault=fault) as (port, slave, before, state, work, _):
            log = work/'chat.jsonl'
            result = subprocess.run(command(port, '--log', str(log), *extra), capture_output=True, timeout=40)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertIn(b'Chat ended; TX released.', result.stdout)
            self.assertEqual(result.stdout.count(b'Answer complete:'), 2)
            self.assertEqual(termios.tcgetattr(slave), before)
            events = [json.loads(line) for line in log.read_text().splitlines()]
            first_text = next(e['host_us'] for e in events if e.get('event') == 'text_ack')
            first_done = next(e['host_us'] for e in events if e.get('event') in ('model_done', 'model_limit'))
            if strict:
                self.assertLess(first_text, first_done)
            visible = int(next(line.split('=')[1] for line in state.read_text().splitlines() if line.startswith('chat_text_visible_us=')))
            if strict:
                self.assertLess(visible, first_done)
            keepalives = [e['host_us'] for e in events if e.get('event') == 'usb_request' and e.get('command') == 9]
            self.assertGreater(len(keepalives), 10)
            self.assertLess(max(b-a for a,b in zip(keepalives, keepalives[1:])), 900000)
            self.assertEqual(state.read_text().splitlines()[-1], 'tx=0')
            result = run(port, OUT/'hello.bin', '--wait-return')
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            if record:
                Path(record).write_text(json.dumps({'hardware': False, 'model': 'gemma3:1b',
                    'first_z80_display_us': visible, 'first_text_ack_us': first_text,
                    'first_model_done_or_limit_received_us': first_done,
                    'display_before_done_received': visible < first_done,
                    'events': events, 'host_output': result.stdout.decode()}, indent=2)+'\n')
            return events

    @unittest.skipUnless(LIVE, 'optional real local Ollama model')
    def test_live_ollama(self):
        self.check_chat('chat', '--model', 'gemma3:1b', strict=False, record=OUT/'chat-live-ollama.json')

    def test_mock_stream_is_displayed_before_done_and_next_deploy_works(self):
        self.check_chat('chat', '--mock')

    def test_http_stream_and_multiturn_history(self):
        with provider() as (url, requests):
            self.check_chat('chat', '--ollama-url', url)
        self.assertEqual(len(requests), 2)
        self.assertTrue(all(r['stream'] for r in requests))
        self.assertEqual([len(r['messages']) for r in requests], [2, 4])
        self.assertEqual(requests[0]['messages'][-1]['content'], 'HELLO')

    def test_corrupt_frame_is_retried(self):
        events = self.check_chat('chat-corrupt', '--mock')
        self.assertTrue(any(e.get('event') == 'chat_retry' for e in events))

    def test_lost_ack_is_retried_without_duplicate_display(self):
        events = self.check_chat('chat-drop-ack', '--mock')
        self.assertTrue(any(e.get('event') == 'chat_retry' for e in events))

    def test_http_stall_keeps_lease_and_ctrl_c_returns_to_loader(self):
        with provider(stall=True) as (url, _), device(fault='chat') as (port, slave, before, _, work, _):
            log = work/'stall.jsonl'
            process = subprocess.Popen(command(port, '--ollama-url', url, '--log', str(log)), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic()+15
                while time.monotonic() < deadline:
                    if log.exists() and '"event":"prompt"' in log.read_text():
                        break
                    if process.poll() is not None:
                        break
                    time.sleep(.05)
                time.sleep(1.5)
                process.send_signal(signal.SIGINT)
                stdout, stderr = process.communicate(timeout=10)
                self.assertIn(b'Interrupted', stderr, stdout+stderr)
                self.assertEqual(termios.tcgetattr(slave), before)
                events = [json.loads(line) for line in log.read_text().splitlines()]
                keepalives = [e['host_us'] for e in events if e.get('event') == 'usb_request' and e.get('command') == 9]
                self.assertGreater(len(keepalives), 10)
                self.assertLess(max(b-a for a,b in zip(keepalives, keepalives[1:])), 900000)
                result = run(port, OUT/'hello.bin', '--wait-return')
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


if __name__ == '__main__':
    unittest.main()
