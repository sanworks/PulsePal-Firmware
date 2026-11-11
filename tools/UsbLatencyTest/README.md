# USB serial latency test

A minimal Teensy 4.1 sketch and two clients, for measuring USB serial round trip latency and throughput from Python and
MATLAB without the Pulse Pal firmware.

| File | Contents |
|---|---|
| `UsbLatencyTest.ino` | Echo and streaming commands (list at the top of the file). Touches no pins |
| `usb_latency_test.py` | pyserial: echo modes, reply sizes, write-only calls, throughput |
| `usbLatencyTest.m` | MATLAB: `serialport` (default and `HighReadFrequency`), the Windows timer resolution, legacy `serial`, .NET `System.IO.Ports.SerialPort`, and idle CPU use |

## Running it

Uploading the sketch replaces the Pulse Pal firmware; upload `/Firmware/PulsePal` again afterwards.

```bash
arduino-cli compile --fqbn teensy:avr:teensy41:usb=serial --build-path <build> Firmware/tools/UsbLatencyTest
arduino-cli upload --fqbn teensy:avr:teensy41:usb=serial -p <teensy port, e.g. usb:0/140000/0/6> --protocol teensy --input-dir <build> Firmware/tools/UsbLatencyTest
cd Python/PulsePal && uv run python ../../Firmware/tools/UsbLatencyTest/usb_latency_test.py COM20
```

In MATLAB, from this folder: `usbLatencyTest('COM20')`. The 1 ms timer tests need `pyenv` with `ExecutionMode`
`"InProcess"` and `pyrun` (R2021b or newer); they are skipped otherwise.

## Results, 2026-09-29

Windows 11, Teensy 4.1 (Teensyduino 1.62), a 1 byte echo, median of 200 round trips.

| Client | Round trip | CPU while a port is open and idle |
|---|---|---|
| pyserial 3.5 | 0.20 ms | |
| MATLAB `serialport` (R2020b, R2025b) | 15.6 ms | about 1% of one core |
| MATLAB `serialport`, `'HighReadFrequency', true` (R2025b only, undocumented) | 0.5 ms | about 200% |
| MATLAB `serialport`, after `timeBeginPeriod(1)` in the MATLAB process | 2.0 ms | about 3% |
| MATLAB `serial` (legacy, deprecated) | 3-4 ms, max 45-75 ms | |
| MATLAB .NET `System.IO.Ports.SerialPort` (R2020b, R2025b) | 0.28 ms | about 1% |

- The Teensy adds almost nothing: from pyserial, a reply sent with `Serial.send_now()`, one left to the core's 75 us
  transmit timer, and one written a byte at a time all take about 0.2 ms.
- `serialport`'s delay is on the MATLAB side. Polling `NumBytesAvailable` shows the reply reaching MATLAB's input
  buffer 15.6 ms after the write: MATLAB's asyncio data pump sleeps between polls of the port, and the sleep lasts one
  tick of the MATLAB process's Windows timer (15.6 ms by default; Windows 11 applies timer resolution per process, so a
  1 ms resolution set by another program does not help). `HighReadFrequency` makes the pump yield instead of sleep
  (`OptimizedSleep` in `toolbox/shared/asynciolib/.../Channel.m`), at the cost of about two busy cores for as long as
  the port is open. Waiting with `pause(0.001)` or `java.lang.Thread.sleep(1)` does not help, and `read()` itself
  keeps a core busy while it waits.
- .NET's `SerialPort` matches pyserial, costs nothing while idle, and is faster for Pulse Pal's larger transfers too:
  a 60 KB custom train plus its acknowledgement takes 5.2 ms (`serialport`: 15.7 ms), and a 178 byte parameter
  read-back 0.39 ms (15.5 ms).
- Throughput, device to PC: pyserial and .NET 16 MB/s. `serialport` 16 MB/s on R2020b, but only 0.2 MB/s on R2025b
  (about 4 KB per 15.6 ms poll), and data was lost: the Teensy core drops output when the PC stops reading for 120 ms
  (`TX_TIMEOUT_MSEC` in `cores/teensy4/usb_serial.c`). pyserial loses a packet the same way if a single `read()` asks
  for megabytes, so the clients here read in 64 KB chunks. PC to device: 13 MB/s for every client.

## .NET robustness, 2026-09-29

Before `PulsePalDevice` moved to .NET on Windows, `pulsepal.DotNetSerialPort` (`/MATLAB/+pulsepal`) was compared with
`serialport` on a Pulse Pal 3 running Pulse Pal firmware, on R2020b and R2025b (16 logical cores):

- `dotnetRobustnessTest.m`: the op 72 handshake round trip, a 60 KB custom train (op 95) and a 178 byte read (op 93),
  at idle and with 16 and 32 busy processes (`cpu_load.py`); 20000 round trips; a read with no reply; the port held by
  Python, or already open in MATLAB; a port that does not exist; 50 open/close cycles; clearing a port without closing it.
- `dotnetRemovalTest.m`: the device disappearing (134 baud reboots the Teensy into its bootloader) while idle and during
  a read, for serialport, the wrapper, and raw .NET without the wrapper's finalizer workaround, each in its own MATLAB
  process.
- `dotnetSessionTest.m`: first open, memory over 100000 round trips, and reconnecting after the device comes back.

| Handshake round trip (median / 99th percentile / max) | serialport | DotNetSerialPort |
|---|---|---|
| Idle, R2025b | 15.8 / 16.7 / 38.9 ms | 0.40 / 0.76 / 21.0 ms |
| 16 busy processes, R2025b | 8.4 / 29.8 / 36.0 ms | 0.55 / 8.4 / 32.1 ms |
| 32 busy processes, R2025b | 11.2 / 35.5 / 38.1 ms | 0.93 / 6.7 / 35.5 ms |
| Idle, R2020b | 15.8 / 16.6 / 20.4 ms | 0.48 / 0.92 / 18.9 ms |
| 32 busy processes, R2020b | 8.0 / 32.7 / 33.1 ms | 0.94 / 12.3 / 25.8 ms |

- No failed transfer in any test, for either backend. Under load, both have worst cases of 20-40 ms (the Windows
  scheduler); .NET's median and 99th percentile stay far lower.
- 60 KB custom train and confirm byte, 32 busy processes: 5.5 ms median (serialport 18-32 ms).
- 100000 round trips: no leak (MATLAB memory flat after warm-up, .NET heap +0.17 MB after a collection).
- A read with no reply: both warn and return nothing after the timeout, and the next round trip works.
- A port in use, or missing: both refuse with a clear error. 50 open/close cycles: 0.4-0.6 s (serialport 2.3-3.8 s),
  and the port is free afterwards. Clearing the variable closes the port at once, for both.
- Device removed: no crash with any backend, including raw .NET (.NET Framework 4.8.1 has no finalizer crash). Every
  later call fails at once with "The port is closed"; a read in progress fails within 60 ms. After the device comes
  back, a new port opens within 1 s in the same session.
- First open in a session (loads .NET): 190 ms; later opens 13 ms.
- MATLAB set to .NET (Core) with `dotnetenv`: `System.IO.Ports` is not available, `isAvailable()` returns false, and
  PulsePalDevice uses serialport. (`dotnetenv` does not persist between sessions.)
- Pulse Pal 2 (Arduino Due, native USB port, which only sends while DTR is set; the wrapper sets it when it opens the
  port): the scope test panel's full case list ran through the wrapper without a transfer error on 2026-09-29
  (MATLAB R2025b).
- Not tested here: Ctrl+C during a read (reads wait in 100 ms slices so that it can interrupt them), Windows on
  ARM, sleep and hibernation.
