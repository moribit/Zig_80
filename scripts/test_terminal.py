#!/usr/bin/env python3
"""Optional POSIX PTY integration check; Python is a test tool, not a runtime dependency."""
import fcntl
import os
import pty
import select
import struct
import subprocess
import sys
import termios
import time


def check(binary, profile, quit_key, rows=30, columns=100):
    master, slave = pty.openpty()
    process = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, columns, 0, 0))
        before = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [binary, "tui", "--profile", profile],
            stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "TERM": "xterm-256color", "LANG": "en_US.UTF-8"},
            start_new_session=True,
        )
        output = bytearray()
        sent = False
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            ready, _, _ = select.select([master], [], [], 0.1)
            if ready:
                try:
                    data = os.read(master, 65536)
                except OSError:
                    break
                output.extend(data)
                if rows and not sent and b"\x1b[?1049h" in output:
                    os.write(master, quit_key)
                    sent = True
            if process.poll() is not None:
                # Drain remaining restoration escapes after process termination.
                while select.select([master], [], [], 0)[0]:
                    try:
                        output.extend(os.read(master, 65536))
                    except OSError:
                        break
                break
        assert process.poll() == (0 if rows else 1), ("TUI exit", process.poll(), bytes(output[-1000:]))
        assert b"\x1b[?1049h" in output, "TUI did not enter alternate screen"
        if rows:
            assert sent, "quit key was not sent"
        else:
            assert b"TerminalSizeUnavailable" in output, "expected startup failure did not occur"
        assert b"\x1b[?1049l" in output, "alternate screen was not restored"
        assert b"\x1b[?25h" in output, "cursor was not restored"
        assert termios.tcgetattr(slave) == before, "terminal attributes were not restored"
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)


if __name__ == "__main__":
    binary = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/zig80")
    for profile in ("classic", "handheld"):
        for key in (b"\x11", b"\x03"):
            check(binary, profile, key)
        check(binary, profile, b"", rows=0, columns=0)
    print("TUI restored termios, alternate screen and cursor (both profiles, Ctrl+Q/Ctrl+C/startup failure).")
