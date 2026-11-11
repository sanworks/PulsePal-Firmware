# Working on this repository

Pulse Pal is an open source pulse train generator: a device that plays precisely timed voltage
pulse trains on four analog output channels, started by software or by two trigger inputs. This
repository holds its firmware, for Pulse Pal 2 (Arduino Due) and Pulse Pal 3 (Teensy 4.1), and
Wave Pal and Synth Pal, alternative firmware that makes a Pulse Pal 3 a four channel waveform
player or synthesizer. The current release is v22.

Pulse Pal is split into three repositories. Clone them side by side, under these names, in one
folder:

| Repository | Contents |
|---|---|
| [PulsePal-Firmware](https://github.com/sanworks/PulsePal-Firmware) (this one) | The firmware, its USB protocols and the build check |
| [PulsePal](https://github.com/sanworks/PulsePal) | The clients: the Python, MATLAB and C++ classes, the GUIs, the MATLAB firmware loader, the offline and hardware tests, and `/USING.md`, the guide to using the devices from Python and MATLAB |
| [PulsePal-CAD](https://github.com/sanworks/PulsePal-CAD) | Circuit board and enclosure design files |

In these pages a path that starts with `/` is in this repository, unless the text places it in the
PulsePal repository (`/Python/PulsePal/tests/test_protocol.py` in the PulsePal repository). The
clients' tests run from the PulsePal repository's root.

## Layout

| Path | Contents |
|---|---|
| `/PulsePal/` | Current firmware (v22), for **both** Pulse Pal 2 and Pulse Pal 3. Read its `AGENTS.md` before changing it |
| `/PROTOCOL.md` | The USB serial protocol: op codes, parameter codes, replies, settings file layout |
| `/WavePal/` | Wave Pal: a four channel waveform player for Pulse Pal 3. Its own `AGENTS.md` and `PROTOCOL.md` |
| `/SynthPal/` | Synth Pal: a four channel waveform synthesizer for Pulse Pal 3 (sine, triangle, square, sawtooth, white noise, fixed voltage), with Pulse Pal's trigger modes, param sync included. Its own `AGENTS.md` and `PROTOCOL.md` |
| `/tools/` | `build_check.py`: compiles both hardware versions (or Wave Pal and Synth Pal, with `--sketch wavepal` and `--sketch synthpal`), and compares compiled functions between git revisions. `stub_libraries/` holds the compile-only LiquidCrystal it builds Pulse Pal 2 with. `UsbLatencyTest/` measures USB serial latency from Python and MATLAB |
| `/Old/` | Archived firmware, no longer developed |

`ArCOM.h` and `LiquidCrystal_U8G2` in `/WavePal/` and `/SynthPal/` are copies of the files in
`/PulsePal/`. A fix to one usually belongs in all three.

## Branches and releases

Releases are made with GitFlow:

- `develop` holds the work since the last release. Work there, or on a branch from it.
- A release is prepared on a `release/vNN` branch from `develop`, then merged into `main`, tagged
  `vNN`, and merged back into `develop`. v22 was released this way.
- `main` holds releases only. A fix to a release goes on a `hotfix/` branch from `main`, and is
  merged into `main` and `develop`.

Each firmware has its own version number: `FIRMWARE_VERSION` at the top of its main tab
(`PulsePal.ino`, `WavePal.ino`, `SynthPal.ino`). The device reports it in the handshake and shows
it on its screen. Tags carry Pulse Pal's (v22, which carries Wave Pal v1 and Synth Pal v1).

A new version number has counterparts in the PulsePal repository, which change with it:

- Each class holds the newest firmware version it knows, and warns of a newer one:
  `_CURRENT_FIRMWARE_VERSION` in the Python classes, `CurrentFirmwareVersion` in the MATLAB
  classes and in the C++ class (`/c++/PulsePal.cpp`). Pulse Pal's classes also tell the user of older firmware that the
  current version is available.
- `/MATLAB/FirmwareLoader/` holds compiled firmware, one file per firmware, hardware version and
  firmware version (`PulsePal_HW3_v022.hex`, `PulsePal_HW2_v022.bin`, `WavePal_HW3_v001.hex`).
  Build a Pulse Pal 2 file with the real LiquidCrystal library, never from a default
  `build_check.py` run (see "Building" in `/PulsePal/AGENTS.md`).

## The protocol ties the firmware to its clients

The firmware and four clients in the PulsePal repository (Python class, MATLAB class, MATLAB
legacy functions, C++ class) all encode the same serial protocol, documented in `/PROTOCOL.md`.
Wave Pal and Synth Pal have protocols of their own, in `/WavePal/PROTOCOL.md` and
`/SynthPal/PROTOCOL.md`, with the same framing byte, and Python and MATLAB classes each. A change
on one side usually needs a matching change on the other, in the other repository: make both on
each repository's `develop` branch. A client that uses a new op needs firmware that has it, so the
firmware release that adds an op goes out no later than the clients that send it.

Op codes, parameter codes, message layouts and the settings file layout are **fixed**, because
installed copies of the clients rely on them. Add new op codes instead of changing existing ones.

The three firmwares answer the same handshake (op 72) with different bytes, 'K', 'W' and 'S', and
every client names the firmware it finds when it is not its own. Pulse Pal also answers op 103,
with which the current Pulse Pal classes connect: the session's times are then in the device's
own timer cycles (10 µs on Pulse Pal 3), where op 72 makes them 50 µs cycles, as every older
client sends them (see "Time units" and "Connecting" in `/PROTOCOL.md`). All three answer op 100
with the circuit board revision and op 102 with the USB serial number.

Past bugs came from this coupling, so check both sides: a Python parameter code was derived from
a list position, custom trains were sent with an op code calculated from the train number, and the
last byte of op 97's reply arrived after the clients had stopped reading. The client conventions
that guard against these are in the PulsePal repository's `/AGENTS.md`, under "Working on the
clients".

## Checks you can run without a device

```bash
# Compile the firmware for both hardware versions (needs arduino-cli; see build_check.py's docstring)
python tools/build_check.py

# Compile, and compare every compiled function with the last commit
python tools/build_check.py --compare HEAD

# Wave Pal and Synth Pal
python tools/build_check.py --sketch wavepal --compare HEAD
python tools/build_check.py --sketch synthpal --compare HEAD
```

`--compare` takes a revision of this repository, whose history starts at v22. Earlier revisions
of the firmware are in the PulsePal repository's history, under `/Firmware/`.

After a change to a protocol, check the bytes each class sends, in the PulsePal repository:

```bash
cd Python/PulsePal && uv run python tests/test_protocol.py
cd Python/PulsePal && uv run python tests/test_wavepal_protocol.py
cd Python/PulsePal && uv run python tests/test_synthpal_protocol.py
matlab -batch "addpath('MATLAB', 'MATLAB/tests'); testPulsePalDeviceOffline"
```

The C++ class has offline tests too (see `/c++/README.md` in the PulsePal repository).

## Checks that need a device

Everything else needs a device: pulse timing, the trigger inputs, the screen, the joystick menu
and the microSD card. Each firmware's `AGENTS.md` lists the usual checks. The hardware tests are
in the PulsePal repository: `/Python/PulsePal/tests/pulsepal_hardware_test.py` checks, without a
scope, that a Pulse Pal stays in step with the PC (with `--driver`, a second Pulse Pal on the
trigger inputs, also 5 kHz trigger edges and param sync); `wavepal_hardware_test.py` and
`synthpal_hardware_test.py`, beside it, check every sample a Wave Pal or Synth Pal plays; and
`/Python/PulsePal/tests/benchmark_serial.py` measures USB latency and throughput, before and
after a change to serial code.

When you finish a change, state plainly what was and was not tested, and give the user a short
list of things to check on the device.

## Style

- Match the surrounding code. The firmware is long-lived and written in a consistent style, and
  a large reformat makes support calls harder for the people who maintain it.
- Keep existing names for variables, functions, op codes and parameters.
- Comments explain why, and record the traps: interrupt context, fixed numbers, hardware quirks.
- Python (`/tools/`) follows PEP 8.
- Work on the `develop` branch. `main` holds the latest release.
- Commit messages list the changes per component, e.g. `-Pulse Pal: Fixed X -Synth Pal: Added Y`.
