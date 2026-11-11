/*
----------------------------------------------------------------------------

This file is part of the Pulse Pal Project
Copyright (C) 2026 Sanworks LLC, Rochester, NY, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/

// UsbLatencyTest: a minimal USB serial responder for a Teensy 4.1, for measuring the round trip latency and throughput
// of USB serial clients (pyserial, MATLAB's serialport and others) without the Pulse Pal firmware. It touches no pins,
// so it can run on a Pulse Pal 3, until the Pulse Pal firmware is uploaded again. Build with Tools > USB Type: Serial.
//
// Test clients: usb_latency_test.py and usbLatencyTest.m in this folder.
//
// Commands. Each is one ASCII letter, then its data:
//   'E' n <n bytes>  Echo the n bytes (n 1-255), sent at once with Serial.send_now(), as Pulse Pal's ArCOM sends replies
//   'L' n <n bytes>  Echo, sent by the Teensy core's transmit timer, 75 us after the last write (TRANSMIT_FLUSH_TIMEOUT in
//                    cores/teensy4/usb_serial.c)
//   'B' n <n bytes>  Echo with one Serial.write() per byte, and no send_now()
//   'R' k (uint32)   Send k bytes: 0, 1, ... 255, 0, 1, ... (device to PC throughput, and long replies)
//   'W' k (uint32)   Read k bytes, then reply with one byte: their sum, mod 256 (PC to device throughput)
//   'I'              Reply "UsbLatencyTest\n"
// Other bytes are ignored, so writing one is a write with no reply. Multi-byte values are little-endian.

const uint32_t READ_TIMEOUT_MS = 1000; // Give up on a command whose data stops arriving
uint8_t buffer[4096];

void setup() {
  Serial.begin(115200); // The baud rate is ignored for USB
  Serial.setTimeout(READ_TIMEOUT_MS);
}

void loop() {
  if (!Serial.available()) {
    return;
  }
  uint8_t command = Serial.read();
  switch (command) {
    case 'E':
    case 'L':
    case 'B': {
      uint8_t n;
      if ((Serial.readBytes((char *)&n, 1) != 1) || (Serial.readBytes((char *)buffer, n) != n)) {
        return;
      }
      if (command == 'B') {
        for (int i = 0; i < n; i++) {
          Serial.write(buffer[i]);
        }
      } else {
        Serial.write(buffer, n);
        if (command == 'E') {
          Serial.send_now();
        }
      }
    } break;
    case 'R': {
      uint32_t k;
      if (Serial.readBytes((char *)&k, 4) != 4) {
        return;
      }
      for (uint32_t i = 0; i < sizeof(buffer); i++) {
        buffer[i] = (uint8_t)i;
      }
      while (k > 0) { // sizeof(buffer) is a multiple of 256, so the pattern continues across writes
        uint32_t chunk = (k < sizeof(buffer)) ? k : sizeof(buffer);
        Serial.write(buffer, chunk);
        k -= chunk;
      }
      Serial.send_now();
    } break;
    case 'W': {
      uint32_t k;
      if (Serial.readBytes((char *)&k, 4) != 4) {
        return;
      }
      uint8_t sum = 0;
      while (k > 0) {
        uint32_t chunk = (k < sizeof(buffer)) ? k : sizeof(buffer);
        if (Serial.readBytes((char *)buffer, chunk) != chunk) {
          return;
        }
        for (uint32_t i = 0; i < chunk; i++) {
          sum += buffer[i];
        }
        k -= chunk;
      }
      Serial.write(sum);
      Serial.send_now();
    } break;
    case 'I': {
      Serial.print("UsbLatencyTest\n");
      Serial.send_now();
    } break;
  }
}
