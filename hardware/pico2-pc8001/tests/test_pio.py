#!/usr/bin/env python3
"""Instruction-subset simulation of the actual .pio source, NOT hardware proof."""
import collections
import pathlib
import re
import unittest

SOURCE = pathlib.Path(__file__).parents[1] / "pio" / "uart.pio"


def program(name):
    section = SOURCE.read_text().split(".program " + name + "\n", 1)[1].split(".program ", 1)[0]
    instructions, labels = [], {}
    for raw in section.splitlines():
        line = raw.split(";", 1)[0].strip()
        if not line or line.startswith("."):
            continue
        if line.endswith(":"):
            labels[line[:-1]] = len(instructions)
        else:
            delay = re.search(r"\[(\d+)\]", line)
            side = re.search(r"\bside ([01])", line)
            text = re.sub(r"\[\d+\]|\bside [01]", "", line).strip()
            instructions.append((text, int(delay[1]) if delay else 0, int(side[1]) if side else None))
    return instructions, labels


def simulate(name, levels, tx=(), cycles=None):
    code, labels = program(name)
    fifo = collections.deque(tx)
    pc = x = isr = osr = delay_left = pin = 0
    received, output = [], []
    for t in range(cycles or len(levels)):
        level = levels[min(t, len(levels) - 1)]
        if delay_left:
            delay_left -= 1
            output.append(pin)
            continue
        text, delay, side = code[pc]
        if side is not None:
            pin = side
        advance = True
        completed = True
        if text.startswith("wait "):
            advance = level == int(text.split()[1])
            completed = advance
        elif text.startswith("set x,"):
            x = int(text.split(",")[1])
        elif text == "in pins, 1":
            isr = (isr >> 1) | (level << 31)
        elif text == "out pins, 1":
            pin, osr = osr & 1, osr >> 1
        elif text.startswith("jmp "):
            words = text.replace(",", " ").split()
            target = words[-1]
            take = True
            if words[1] == "pin":
                take = bool(level)
            elif words[1] == "x--":
                take = x != 0
                x = (x - 1) & 0xffffffff
            if take:
                pc = labels[target]
                advance = False
        elif text == "mov isr, ~isr":
            isr ^= 0xffffffff
        elif text == "mov osr, ~osr":
            osr ^= 0xffffffff
        elif text == "mov isr, null":
            isr = 0
        elif text.startswith("push "):
            received.append(isr)
            isr = 0
        elif text == "pull block":
            if fifo:
                osr = fifo.popleft()
            else:
                advance = False
                completed = False
        elif text != "nop":
            raise AssertionError(text)
        if advance:
            pc = (pc + 1) % len(code)
        if completed:
            delay_left = delay
        output.append(pin)
    return received, output


def waveform(data, inverted, bad_stop=False):
    idle = 0 if inverted else 1
    levels = [idle] * 16
    for byte in data:
        bits = [0] + [(byte >> bit) & 1 for bit in range(8)] + [0 if bad_stop else 1]
        for bit in bits:
            levels += [bit ^ inverted] * 8
    return levels + [idle] * 80


class PioTests(unittest.TestCase):
    def test_rx_all_bytes_and_continuous_frames_both_polarities(self):
        data = bytes(range(256))
        for inverted in (False, True):
            name = "s10_rx_" + ("inverted" if inverted else "normal")
            words, _ = simulate(name, waveform(data, inverted))
            self.assertEqual(bytes((word >> 23) & 255 for word in words), data)
            self.assertTrue(all(word >> 31 for word in words))

    def test_tx_rx_actual_program_loopback(self):
        data = bytes([0, 255, 0x55, 0xaa, 0x5a, 0x38])
        for inverted in (False, True):
            suffix = "inverted" if inverted else "normal"
            _, levels = simulate("s10_tx_" + suffix, [0], data, 1000)
            words, _ = simulate("s10_rx_" + suffix, levels)
            self.assertEqual(bytes((word >> 23) & 255 for word in words), data)
            self.assertTrue(all(word >> 31 for word in words))

    def test_false_start_stop_error_and_stuck_line_are_bounded(self):
        for inverted in (False, True):
            idle = 0 if inverted else 1
            name = "s10_rx_" + ("inverted" if inverted else "normal")
            short = [idle] * 16 + [1 - idle] * 3 + [idle] * 16
            words, _ = simulate(name, short)
            self.assertEqual(words, [])
            words, _ = simulate(name, waveform([0x55], inverted, bad_stop=True))
            self.assertEqual(len(words), 1)
            self.assertEqual(words[0] >> 31, 0)
            stuck = [idle] * 16 + [1 - idle] * 400
            words, _ = simulate(name, stuck)
            self.assertEqual(len(words), 1)  # Stop fault then wait for idle.
            self.assertEqual(words[0] >> 31, 0)

    def test_divider_error(self):
        for hz in (125_000_000, 150_000_000):
            q8 = (hz * 256 + 1200) // 2400
            self.assertLessEqual(q8, 0xffffff)
            baud = hz * 256 / (q8 * 8)
            self.assertLess(abs(baud - 300) / 300 * 1e6, 1)


if __name__ == "__main__":
    unittest.main()
