#!/usr/bin/env python3
"""Optional real-time 30 minute host/C-bridge/Z80 soak, no physical device.
Makes ten mock turns, idles with the lease active, then SIGINTs and redeploys.
Run after `zig build && zig build loader-mock`.
"""
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import termios
import time

seconds = int(sys.argv[1]) if len(sys.argv) > 1 else 1800
sys.argv = [sys.argv[0]]
from test_chat import BINARY, OUT, command, device, run

OUT.mkdir(parents=True, exist_ok=True)
assembled = subprocess.run([BINARY, 'asm', 'examples/pc8001/hello.asm', '-o', str(OUT/'hello.bin')], capture_output=True)
assert assembled.returncode == 0, assembled.stderr
os.environ['CHAT_TURNS'] = '10'
os.environ['CHAT_IDLE_AFTER_TURNS'] = '1'
with device(fault='chat') as (port, slave, before, state, work, _):
    log = OUT/'chat-soak.jsonl'
    if log.exists():
        log = OUT/f'chat-soak-{time.time_ns()}.jsonl'
    process = subprocess.Popen(command(port, '--mock', '--session-minutes', '60', '--log', str(log)), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    started = time.monotonic()
    try:
        while time.monotonic()-started < seconds:
            if process.poll() is not None:
                out, err = process.communicate()
                raise AssertionError((out+err).decode(errors='replace'))
            elapsed = time.monotonic()-started
            print(f'chat soak active: {elapsed:.0f}/{seconds}s', flush=True)
            time.sleep(max(0, min(30, seconds-elapsed)))
        process.send_signal(signal.SIGINT)
        out, err = process.communicate(timeout=10)
        assert b'Interrupted' in err, (out, err)
        assert out.count(b'Answer complete:') == 10, out
        assert termios.tcgetattr(slave) == before
        result = run(port, OUT/'hello.bin', '--wait-return')
        assert result.returncode == 0, result.stdout+result.stderr
        keepalive = []
        with log.open() as stream:
            for line in stream:
                event = json.loads(line)
                if event.get('event') == 'usb_request' and event.get('command') == 9:
                    keepalive.append(event['host_us'])
        max_gap = max(b-a for a,b in zip(keepalive, keepalive[1:]))
        assert max_gap < 900000, max_gap
        report = {'physical_hardware': False, 'requested_seconds': seconds,
                  'elapsed_seconds': time.monotonic()-started, 'turns': 10,
                  'keepalives': len(keepalive), 'max_keepalive_gap_us': max_gap,
                  'sigint_cleanup': True, 'termios_restored': True,
                  'next_deploy_and_return': True, 'log': str(log)}
        (OUT/'chat-soak-result.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps(report), flush=True)
    finally:
        if process.poll() is None:
            process.kill()
            process.communicate()
