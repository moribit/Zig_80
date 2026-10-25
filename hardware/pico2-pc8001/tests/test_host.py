#!/usr/bin/env python3
"""Real Zig CLI <-> PTY <-> exact C firmware protocol core. No hardware I/O."""
import contextlib
import os
import pathlib
import pty
import signal
import subprocess
import sys
import tempfile
import termios
import time
import unittest

BINARY = os.path.abspath(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/zig80")
MOCK = os.path.abspath(sys.argv.pop(1) if len(sys.argv) > 1 else ".zig-cache/pc8001/protocol_mock")


@contextlib.contextmanager
def device(stall=False):
    with tempfile.TemporaryDirectory(prefix="zig80-serial-") as work:
        master, slave = pty.openpty()
        path = os.ttyname(slave)
        before = termios.tcgetattr(slave)
        state = pathlib.Path(work) / "state.log"
        env = {**os.environ, "MOCK_STATE_LOG": str(state)}
        if stall:
            env["MOCK_STALL_TX"] = "1"
        mock = subprocess.Popen([MOCK], stdin=master, stdout=master, stderr=subprocess.PIPE, env=env)
        os.close(master)
        try:
            yield path, slave, before, state, work, mock
        finally:
            mock.terminate()
            mock.communicate(timeout=3)
            os.close(slave)


def command(path, *args):
    return [BINARY, "serial", *args, "--port", path]


class HostTests(unittest.TestCase):
    def test_refuses_tx_before_open_without_both_confirmations(self):
        for flags in ([], ["--enable-tx"], ["--voltage-confirmed"]):
            result = subprocess.run(command("/not/a/serial/port", "send", "HELLO", *flags), capture_output=True, timeout=3)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"TransmitConfirmationRequired", result.stderr)

    def test_info_monitor_and_terminal_restore_never_enable_tx(self):
        with device() as (path, slave, before, state, _, _):
            result = subprocess.run(command(path, "info"), capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"UART=300 8N1 inverted=1 RX=GP1 TX=GP0 tx_enabled=0", result.stdout)
            self.assertEqual(termios.tcgetattr(slave), before)
            result = subprocess.run(command(path, "monitor", "--duration-ms", "100", "--normal"), capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("tx=1", state.read_text())
            self.assertEqual(termios.tcgetattr(slave), before)

    def test_all_bytes_raw_and_diagnostic_log(self):
        with device() as (path, slave, before, state, work, _):
            data = bytes(range(256))
            payload = pathlib.Path(work) / "payload.bin"
            log = pathlib.Path(work) / "events.jsonl"
            payload.write_bytes(data)
            result = subprocess.run(command(path, "send", "--file", str(payload), "--raw", "--log", str(log), "--enable-tx", "--voltage-confirmed"), capture_output=True, timeout=6)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, data)
            self.assertIn(b"tx_completed=256", result.stderr)
            self.assertEqual(len(log.read_text().splitlines()), 256)
            self.assertIn("tx=1", state.read_text())
            time.sleep(0.05)
            self.assertTrue(state.read_text().splitlines()[-1].startswith("tx=0"))
            self.assertEqual(termios.tcgetattr(slave), before)

    def test_pattern_quality_and_identity_are_explicitly_mock(self):
        with device() as (path, _, _, _, _, _):
            result = subprocess.run(command(path, "test", "--enable-tx", "--voltage-confirmed"), capture_output=True, timeout=6)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(b"transport=pico2-pc8001/mock", result.stdout)
            self.assertIn(b"mismatches=0", result.stdout)
            self.assertIn(b"topology NOT verified", result.stdout)

    def test_signal_cleanup_disarms_and_restores_termios(self):
        with device(stall=True) as (path, slave, before, state, _, _):
            process = subprocess.Popen(command(path, "send", "HELLO", "--enable-tx", "--voltage-confirmed"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if state.exists() and "tx=1" in state.read_text():
                        break
                    time.sleep(0.01)
                self.assertIn("tx=1", state.read_text())
                process.send_signal(signal.SIGINT)
                _, errors = process.communicate(timeout=3)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn(b"Interrupted", errors)
                time.sleep(0.05)
                self.assertTrue(state.read_text().splitlines()[-1].startswith("tx=0"))
                self.assertEqual(termios.tcgetattr(slave), before)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()

    def test_disconnection_is_reported(self):
        with device() as (path, _, _, _, _, mock):
            process = subprocess.Popen(command(path, "monitor", "--duration-ms", "10000"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                time.sleep(0.15)
                mock.terminate()
                mock.communicate(timeout=3)
                _, errors = process.communicate(timeout=3)
                self.assertNotEqual(process.returncode, 0)
                self.assertIn(b"DeviceDisconnected", errors)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


if __name__ == "__main__":
    unittest.main()
