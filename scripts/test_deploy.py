#!/usr/bin/env python3
"""Real deploy CLI -> PTY -> actual C bridge -> existing Z80/8251 -> ASM loaders.
Accelerated functional model, no physical serial port, GPIO or wall-clock baud proof.
"""
import contextlib
import json
import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import tempfile
import termios
import time
import unittest

BINARY = os.path.abspath(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/zig80")
MOCK = os.path.abspath(sys.argv.pop(1) if len(sys.argv) > 1 else "zig-out/bin/zig80-loader-mock")
OUT = Path("zig-out/pc8001/deploy-tests").resolve()
FLAGS = ["--target", "pc8001", "--enable-tx", "--voltage-confirmed"]


@contextlib.contextmanager
def device(mode="stage1", fault="", env=None):
    with tempfile.TemporaryDirectory(prefix="zig80-deploy-") as work:
        master, slave = pty.openpty()
        path = os.ttyname(slave)
        before = termios.tcgetattr(slave)
        state = Path(work) / "state.log"
        mock = subprocess.Popen([MOCK, mode, fault], stdin=master, stdout=master,
                                stderr=subprocess.PIPE, env={**os.environ, "MOCK_STATE_LOG": str(state), **(env or {})})
        os.close(master)
        try:
            # The fixture assembles real sources before serving USB. Wait for its
            # first safety callback; this is not part of a loader wire timeout.
            deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                if state.exists() and "tx=0" in state.read_text():
                    break
                if mock.poll() is not None:
                    raise AssertionError(mock.stderr.read().decode(errors="replace"))
                time.sleep(0.01)
            assert state.exists() and "tx=0" in state.read_text(), "fixture did not initialize"
            yield path, slave, before, state, Path(work), mock
        finally:
            mock.terminate()
            _, errors = mock.communicate(timeout=5)
            os.close(slave)
            if mock.returncode not in (0, -signal.SIGTERM):
                raise AssertionError(f"Z80/C mock failed: {errors.decode(errors='replace')}")


def command(port, program, *extra):
    return [BINARY, "deploy", str(program), *FLAGS, "--port", port, *extra]


def run(port, program, *extra, timeout=15):
    return subprocess.run(command(port, program, *extra), capture_output=True, timeout=timeout)


class DeployTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        OUT.mkdir(parents=True, exist_ok=True)
        for name in ("hello", "memory_test", "serial_echo", "return_to_loader", "orbital_rings", "invaders"):
            result = subprocess.run([BINARY, "asm", f"examples/pc8001/{name}.asm", "-o", str(OUT / f"{name}.bin")], capture_output=True)
            assert result.returncode == 0, result.stderr
        (OUT / "one-kib.bin").write_bytes(b"\xc9" + bytes(i & 255 for i in range(1023)))

    def test_bootstrap_formats_and_crc_checked_basic(self):
        result = subprocess.run([BINARY, "deploy", "bootstrap", "--target", "pc8001", "--bootstrap", "legacy", "--format", "monitor", "--out-dir", str(OUT)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        code = (OUT / "stage0.bin").read_bytes()
        basic = (OUT / "stage0.bas").read_text()
        data = bytes.fromhex("".join(line.split(" DATA ")[1].strip('"') for line in basic.splitlines() if " DATA " in line))
        self.assertEqual(data, code)
        high = low = 255
        for byte in data:
            high ^= byte
            for _ in range(8):
                x, y = low // 128, high // 128
                low, high = (low * 2) % 256, (high * 2 + x) % 256
                if y:
                    high ^= 16
                    low ^= 33
        self.assertIn(f"H*256+L<>{high*256+low}", basic)
        self.assertIn(b"SE400<RETURN>", result.stdout)
        self.assertEqual(len((OUT / "stage1.bin").read_bytes()), 1280)

    def test_confirmation_and_invalid_images_rejected_before_open(self):
        result = subprocess.run([BINARY, "deploy", str(OUT / "hello.bin"), "--target", "pc8001", "--port", "/not/a/port"], capture_output=True)
        self.assertIn(b"TransmitConfirmationRequired", result.stderr)
        for data, options in ((b"", []), (bytes(2049), []), (b"\xc9", ["--load-address", "0xe400"]), (b"\xc9", ["--entry", "0xd001"])):
            with tempfile.NamedTemporaryFile() as file:
                file.write(data)
                file.flush()
                result = run("/not/a/port", file.name, *options)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(b"FileNotFound", result.stderr)

    def test_full_stage0_stage1_application_and_return(self):
        with device("stage0") as (port, slave, before, _, work, _):
            log = work / "deploy.jsonl"
            result = run(port, OUT / "hello.bin", "--loader", "stage0", "--wait-return", "--log", str(log))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"Stage 0 accepted CRC16", result.stdout)
            self.assertIn(b"RAM CRC16 verified", result.stdout)
            self.assertIn(b"Application returned to loader", result.stdout)
            self.assertIn(b"mock-z80", result.stdout)
            self.assertEqual(termios.tcgetattr(slave), before)
            records = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(records[-1]["deploy"], "complete")
            requests=[r for r in records if r.get("event")=="usb_request"]
            replies=[r for r in records if r.get("event")=="usb_reply"]
            self.assertGreater(len(requests),0)
            self.assertEqual([(r["command"],r["sequence"]) for r in requests],[(r["command"],r["sequence"]) for r in replies])
            self.assertTrue(all(r["status"]==0 for r in replies))

    def test_mini_relay_resident_application_chain_and_nonexecuting_preflight(self):
        with device("mini") as (port, _, _, _, _, _):
            result=run(port,OUT / "hello.bin","--loader","mini","--wait-return")
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn(b"Relay Stage 1 READY after 333 bytes + SUM8",result.stdout)
            self.assertIn(b"Stage 0 accepted CRC16",result.stdout)
            self.assertIn(b"RAM CRC16 verified",result.stdout)
            self.assertIn(b"Application returned",result.stdout)
        with device("mini") as (port, _, _, _, _, _):
            result=run(port,"test","--loader","mini")
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn(b"256/256",result.stdout)
            self.assertIn(b"no jump",result.stdout)

    def test_one_kib_no_exec_verify_only_and_repeat_deploy(self):
        with device() as (port, slave, before, _, _, _):
            for name, extra in (("one-kib", ["--no-exec"]), ("one-kib", ["--verify-only"]), ("hello", ["--wait-return"]), ("memory_test", ["--wait-return"]), ("return_to_loader", ["--wait-return"])):
                result = run(port, OUT / f"{name}.bin", *extra)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(b"RAM CRC16 verified", result.stdout)
                if "--no-exec" in extra or "--verify-only" in extra:
                    self.assertNotIn(b"EXEC acknowledged", result.stdout)
                self.assertEqual(termios.tcgetattr(slave), before)

    def test_graphics_demo_returns_and_allows_the_next_deployment(self):
        with device() as (port, slave, before, state, _, mock):
            result = run(port, OUT / "orbital_rings.bin", "--wait-return", "--timeout", "30000", timeout=40)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"RAM CRC16 verified", result.stdout)
            self.assertIn(b"Application returned to loader; A=52", result.stdout)
            self.assertEqual(termios.tcgetattr(slave), before)
            result = run(port, OUT / "hello.bin", "--wait-return")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"Application returned to loader", result.stdout)
            # Linux rejects tcgetattr after the fixture closes the PTY master.
            # Check restoration first; execution counts are written on fixture exit.
            self.assertEqual(termios.tcgetattr(slave), before)
            mock.terminate()
            mock.communicate(timeout=5)
            self.assertIn("exec_entries=2", state.read_text())

    def test_interactive_game_launch_and_escape_return(self):
        with device() as (port, _, _, state, _, mock):
            result = run(port, OUT / "invaders.bin")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"EXEC acknowledged", result.stdout)
            self.assertIn(b"TX released", result.stdout)
            self.assertNotIn(b"Application returned", result.stdout)
            mock.terminate()
            mock.communicate(timeout=5)
            self.assertIn("exec_entries=1", state.read_text())
        with device(fault="auto-escape") as (port, slave, before, _, _, _):
            result = run(port, OUT / "invaders.bin", "--wait-return", "--timeout", "10000")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"Application returned to loader; A=49", result.stdout)
            self.assertEqual(termios.tcgetattr(slave), before)
            result = run(port, OUT / "hello.bin", "--wait-return")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"Application returned to loader", result.stdout)

    def test_binary_00_ff_and_application_owned_uart(self):
        with device("stage0") as (port, _, _, _, _, _):
            result = run(port, "test", "--loader", "stage0")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"256/256", result.stdout)
            self.assertIn(b"no jump", result.stdout)
        with device("preflight") as (port, _, _, _, _, _):
            result = run(port, "test", "--loader", "preflight")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"256/256", result.stdout)
        with device() as (port, _, _, _, _, _):
            result = run(port, "test")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"256/256", result.stdout)
            result = run(port, OUT / "serial_echo.bin", "--app-echo")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn(b"Application echo: 17 bytes matched", result.stdout)

    def test_corruption_and_lost_data_ack_retry_without_duplicate_writes(self):
        for fault in ("corrupt-data", "drop-data-ack"):
            with device(fault=fault) as (port, _, _, _, _, _):
                result = run(port, OUT / "hello.bin", "--wait-return", "--timeout", "100")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(b"loader_retries=1", result.stdout)

    def test_lost_exec_ack_does_not_execute_twice(self):
        with device(fault="drop-exec-ack") as (port, _, _, state, _, mock):
            result = run(port, OUT / "hello.bin", "--wait-return", "--timeout", "100")
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            mock.terminate()
            mock.communicate(timeout=5)
            self.assertIn("exec_entries=1", state.read_text())

    def test_old_return_notification_cannot_prove_new_halted_application_returned(self):
        with device(fault="stale-return") as (port, _, _, _, work, _):
            program=work / "halt.bin"
            program.write_bytes(b"\x76")
            result=run(port,program,"--wait-return","--timeout","100")
            self.assertIn(b"EXEC acknowledged",result.stdout,result.stderr)
            self.assertNotEqual(result.returncode,0,result.stdout)
            self.assertNotIn(b"Application returned",result.stdout)
            self.assertNotIn(b"Completed;",result.stdout)

    def test_wrong_version_lease_expiry_reconnect_and_disconnect_never_succeed(self):
        for fault in ("wrong-version", "expire", "reconnect", "disconnect", "uart-framing"):
            with device(fault=fault) as (port, _, _, _, work, _):
                log=work / "failure.jsonl"
                result = run(port, OUT / "one-kib.bin", "--no-exec", "--timeout", "100", "--retries", "0", "--log", str(log))
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertNotIn(b"Completed;", result.stdout)
                self.assertNotIn(b"EXEC acknowledged", result.stdout)
                if fault=="uart-framing":
                    self.assertIn(b"UartFault",result.stderr)
                    self.assertTrue(any(r.get("flags",0) & 1 for r in map(json.loads,log.read_text().splitlines())))

    def test_absent_stage0_or_stage1_reports_timeout_without_upload(self):
        for mode in ("stage0", "stage1", "mini"):
            with device("silent") as (port, _, _, _, _, _):
                result = run(port, OUT / "hello.bin", "--loader", mode, "--ready-timeout", "100", "--timeout", "100", "--retries", "0")
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn(b"Uploading", result.stdout)
                self.assertNotIn(b"EXEC acknowledged", result.stdout)

    def test_ctrl_c_releases_output_and_restores_terminal(self):
        with device("silent") as (port, slave, before, state, _, _):
            process = subprocess.Popen(command(port, "stage1", "--loader", "stage0"), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if state.exists() and "tx=1" in state.read_text():
                        break
                    time.sleep(0.01)
                self.assertIn("tx=1", state.read_text())
                process.send_signal(signal.SIGINT)
                _, errors = process.communicate(timeout=5)
                self.assertIn(b"Interrupted", errors)
                time.sleep(0.05)
                self.assertEqual([x for x in state.read_text().splitlines() if x.startswith("tx=")][-1], "tx=0")
                self.assertEqual(termios.tcgetattr(slave), before)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()


if __name__ == "__main__":
    unittest.main()
