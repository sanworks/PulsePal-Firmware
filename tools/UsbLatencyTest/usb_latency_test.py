"""Measures USB serial round trip latency and throughput to UsbLatencyTest.ino, with pyserial.

Usage (from /Python/PulsePal in the PulsePal repository, cloned beside this one, whose uv environment
has pyserial):

    uv run python ../../../PulsePal-Firmware/tools/UsbLatencyTest/usb_latency_test.py COM20

Each round trip writes one command and reads its whole reply; times are from
time.perf_counter(), in ms. See UsbLatencyTest.ino for the commands.
"""

import argparse
import statistics
import struct
import sys
import time

import serial


def summarize(name, seconds):
    ms = sorted(s * 1000 for s in seconds)
    print(f"{name:52s} median {statistics.median(ms):7.3f}  95% {ms[int(0.95 * (len(ms) - 1))]:7.3f}  "
          f"min {ms[0]:7.3f}  max {ms[-1]:7.3f} ms")


def round_trips(port, command, size, n, poll=False):
    payload = bytes(range(size))
    message = bytes([ord(command), size]) + payload
    times = []
    for _ in range(n):
        start = time.perf_counter()
        port.write(message)
        if poll:
            while port.in_waiting < size:
                pass
        reply = port.read(size)
        times.append(time.perf_counter() - start)
        if reply != payload:
            sys.exit(f"Bad echo for {command} {size}: {reply!r}")
    return times


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("port")
    parser.add_argument("--n", type=int, default=200, help="round trips per test")
    args = parser.parse_args()

    # USB serial ignores the baud rate. Off Windows it is 4000000, as in the pulsepal package (_common.BAUD_RATE):
    # on Ubuntu 26.04, pyserial could not open a port at 12000000 (termios.error 22, Invalid argument)
    baud_rate = 12000000 if sys.platform == "win32" else 4000000
    port = serial.Serial(args.port, baud_rate, timeout=2)
    port.write(b"I")
    if port.readline() != b"UsbLatencyTest\n":
        sys.exit(f"{args.port} is not running UsbLatencyTest.ino")
    print(f"pyserial {serial.VERSION}, {args.port}, {args.n} round trips per test\n")

    summarize("E 1 byte, read()", round_trips(port, "E", 1, args.n))
    summarize("E 1 byte, poll in_waiting, then read()", round_trips(port, "E", 1, args.n, poll=True))
    summarize("L 1 byte (Teensy 75 us transmit timer), read()", round_trips(port, "L", 1, args.n))
    summarize("B 16 bytes (one write per byte), read()", round_trips(port, "B", 16, args.n))
    for size in (16, 64, 255):
        summarize(f"E {size} bytes, read()", round_trips(port, "E", size, args.n))

    port.timeout = None
    summarize("E 1 byte, read() with timeout=None", round_trips(port, "E", 1, args.n))
    port.timeout = 2

    times = []
    for _ in range(args.n):
        start = time.perf_counter()
        port.write(b"x")  # Ignored by the sketch: a write with no reply
        times.append(time.perf_counter() - start)
    summarize("write only (1 byte, no reply)", times)

    for k in (512, 4096):
        times = []
        for _ in range(args.n // 4):
            start = time.perf_counter()
            port.write(b"R" + struct.pack("<I", k))
            reply = port.read(k)
            times.append(time.perf_counter() - start)
            assert len(reply) == k
        summarize(f"R {k} byte reply", times)

    total = 4 * 1024 * 1024
    start = time.perf_counter()
    port.write(b"R" + struct.pack("<I", total))
    # Read in chunks: the Teensy core drops data if the PC stops reading for 120 ms (TX_TIMEOUT_MSEC in
    # usb_serial.c), and one 4 MB read() on Windows does stall that long
    reply = bytearray()
    while len(reply) < total:
        chunk = port.read(min(65536, total - len(reply)))
        if not chunk:
            break
        reply += chunk
    elapsed = time.perf_counter() - start
    assert len(reply) == total and reply[:4] == bytes([0, 1, 2, 3])
    print(f"\ndevice to PC: {total / elapsed / 1e6:.1f} MB/s ({total} bytes in {elapsed * 1000:.0f} ms)")
    data = bytes(i % 251 for i in range(total))
    start = time.perf_counter()
    port.write(b"W" + struct.pack("<I", total) + data)
    checksum = port.read(1)
    elapsed = time.perf_counter() - start
    assert checksum == bytes([sum(data) % 256])
    print(f"PC to device: {total / elapsed / 1e6:.1f} MB/s ({total} bytes in {elapsed * 1000:.0f} ms)")
    port.close()


if __name__ == "__main__":
    main()
