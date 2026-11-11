# Pulse Pal firmware

This is the firmware of Pulse Pal, an open source pulse train generator maintained by
[Sanworks LLC](https://sanworks.io). A Pulse Pal plays precisely timed voltage pulse trains on four
analog output channels, started by software or by two trigger inputs. The firmware runs on Pulse
Pal 2 (Arduino Due) and Pulse Pal 3 (Teensy 4.1).

Pulse Pal has two other repositories:

- [PulsePal](https://github.com/sanworks/PulsePal): the Python, MATLAB and C++ interfaces, the
  GUIs, the MATLAB firmware loader and USB drivers. Start there to use a Pulse Pal.
- [PulsePal-CAD](https://github.com/sanworks/PulsePal-CAD): the circuit board and enclosure
  design files.

## Releases

Releases are made with GitFlow. `main` holds the latest release, and each release is a tag named
after the Pulse Pal firmware version: [v22](https://github.com/sanworks/PulsePal-Firmware/tree/v22)
is the current one. `develop` holds the changes made since, which are not yet released. Load a
release onto a device.

A release also carries the Wave Pal and Synth Pal firmware of its time. They have version numbers
of their own (v22 carries Wave Pal v1 and Synth Pal v1), which the device shows on its screen and
reports to its classes.

## Loading firmware

To load firmware onto a device you can either use a firmware loader, which needs no Arduino
setup, or compile it yourself with [Arduino](https://www.arduino.cc/en/software/#ide).

Loading firmware without Arduino:

1. With Python: the firmware loader for all Sanworks devices, including Pulse Pal, at
   https://github.com/sanworks/Sanworks-FirmwareLoader
2. With MATLAB: `LoadPulsePalFirmware`, in
   [/MATLAB/FirmwareLoader/](https://github.com/sanworks/PulsePal/tree/master/MATLAB/FirmwareLoader)
   of the PulsePal repository.

Compiling it yourself: the board support and libraries must be installed first. They are listed
at the top of `PulsePal/PulsePal.ino`, and in the "Building" section of `PulsePal/AGENTS.md`.

## Folders and files

**/PulsePal**  
The current firmware. It compiles for both Pulse Pal 2 (Arduino Due) and Pulse Pal 3 (Teensy 4.1),
selected with the `HARDWARE_VERSION` macro at the top of `PulsePal.ino`. `AGENTS.md` in that folder
has the code map, build instructions and the rules to follow when changing the firmware.

**/WavePal**  
Wave Pal: alternative firmware for Pulse Pal 3 (Teensy 4.1) that makes it a four channel waveform
player. It stores four waveforms of up to 1 million samples on the microSD card, and each output
channel plays one of them when it is triggered by TTL, by software or from the joystick, or
reports another channel's playback as a TTL level (sync mode). It is controlled with the Python
class `pulsepal.WavePalDevice` or the MATLAB class `WavePalDevice`, both in the PulsePal
repository. `PROTOCOL.md` and `AGENTS.md` in that folder describe its USB protocol and code.

**/SynthPal**  
Synth Pal: alternative firmware for Pulse Pal 3 (Teensy 4.1) that makes it a four channel waveform
synthesizer. Each output channel plays a sine, triangle, square or sawtooth wave or white noise, or
steps to a fixed voltage, with its own levels, play duration and ramps, when it is triggered by
TTL, by software or from the joystick. One frequency, 1 Hz to 20 kHz, applies to all four. It is
controlled with the Python class `pulsepal.SynthPalDevice` or the MATLAB class `SynthPalDevice`,
both in the PulsePal repository. `PROTOCOL.md` and `AGENTS.md` in that folder describe its USB
protocol and code.

**/Old**  
Archived firmware for earlier hardware and releases, kept for reference and no longer developed.

**/tools**  
`build_check.py` compiles the firmware for both hardware versions, or Wave Pal or Synth Pal
(`--sketch`). It can also compare the compiled code with another git revision, function by
function, to confirm that an edit did not change behavior. `UsbLatencyTest` measures USB serial
latency and throughput with a minimal Teensy sketch.

**PROTOCOL.md**  
The USB serial protocol between the device and its Python, MATLAB and C++ clients: op codes,
parameter codes, replies and the settings file layout.

**AGENTS.md**  
The guide to changing this repository, for people and for AI coding agents: its layout, branches
and releases, and how the firmware and its clients stay in step.

## License

Pulse Pal is an open source instrument, released under the GNU General Public License version 3
(see [LICENSE](LICENSE)). You can build and modify the device for your own use and even release
derivative works commercially, but all derivative versions of the software and hardware must
remain open source under the GNU General Public License v3.

Please contact us with any questions, bugs and general feedback: admin@sanworks.io
