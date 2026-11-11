% usbLatencyTest measures USB serial round trip latency from MATLAB to UsbLatencyTest.ino (in this folder), with
% MATLAB's serialport and the alternatives MATLAB has on Windows, to find where MATLAB's latency comes from.
%
% Usage:
%   usbLatencyTest('COM20')
%   results = usbLatencyTest('COM20', 'N', 500)    % round trips per test (default 200)
%
% Tests (a 1 byte echo, the 'E' command, unless noted):
%   serialport, read()                        MATLAB's current serial interface, as PulsePalDevice uses it
%   serialport, polling NumBytesAvailable     when the reply reaches MATLAB's input buffer
%   serialport, 'HighReadFrequency', true     hidden constructor option (R2025b). The asyncio data pump then yields
%                                             instead of sleeping between polls (see OptimizedSleep in
%                                             toolbox/shared/asynciolib/+matlabshared/+asyncio/+internal/Channel.m)
%   ... at 1 ms Windows timer resolution      timeBeginPeriod(1), called through in-process Python (ctypes), when
%                                             pyenv is set up with ExecutionMode "InProcess"
%   serial (legacy, deprecated), fread()
%   .NET System.IO.Ports.SerialPort           Windows only
% Also: reply sizes, the Teensy's transmit timer ('L'), throughput, and the MATLAB process's CPU use while a port is
% open and idle.

%{
----------------------------------------------------------------------------

This file is part of the Sanworks Pulse Pal repository
Copyright (C) 2026 Sanworks LLC, Rochester, New York, USA

----------------------------------------------------------------------------

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, version 3.

This program is distributed  WITHOUT ANY WARRANTY and without even the
implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
%}

function results = usbLatencyTest(portName, varargin)
p = inputParser;
addParameter(p, 'N', 200);
parse(p, varargin{:});
n = p.Results.N;
results = struct('name', {}, 'ms', {});
baudRate = 12000000; % Ignored by USB serial
fprintf('MATLAB %s, %s, %d round trips per test\n', version('-release'), portName, n);
timerAvailable = ~isnan(timerResolution());
if timerAvailable
    fprintf('Windows timer resolution now: %.3f ms\n', timerResolution());
end
fprintf('\n');

% ---- serialport, as PulsePalDevice uses it -----------------------------------------------------------------------
s = serialport(portName, baudRate);
checkSketch(@(bytes) write(s, bytes, 'uint8'), @(k) read(s, k, 'uint8'));
record('serialport, E 1 byte, read()', serialportTrips(s, 'E', 1, n, false));
record('serialport, E 1 byte, poll NumBytesAvailable', serialportTrips(s, 'E', 1, n, true));
% Waiting with a 1 ms sleep: Java's Thread.sleep() raises this process's Windows timer resolution to 1 ms while it
% sleeps (HotSpot's HighResolutionInterval, for sleeps that are not a multiple of 10 ms), and MATLAB's pause may too
record('serialport, E 1 byte, wait with java Thread.sleep(1)', serialportTrips(s, 'E', 1, n, 'java'));
record('serialport, E 1 byte, wait with pause(0.001)', serialportTrips(s, 'E', 1, n, 'pause'));
record('serialport, L 1 byte (Teensy 75 us timer)', serialportTrips(s, 'L', 1, n, false));
record('serialport, E 64 bytes', serialportTrips(s, 'E', 64, n, false));
record('serialport, write only', writeOnly(@() write(s, uint8('x'), 'uint8'), n));
throughput('serialport', s);
cpuIdle('serialport open, idle', 5);
delete(s);
cpuIdle('no port open, idle', 5);

% ---- serialport with HighReadFrequency ------------------------------------------------------------------------------
try
    s = serialport(portName, baudRate, 'HighReadFrequency', true);
    record('serialport HighReadFrequency, E 1 byte, read()', serialportTrips(s, 'E', 1, n, false));
    record('serialport HighReadFrequency, E 1 byte, poll', serialportTrips(s, 'E', 1, n, true));
    record('serialport HighReadFrequency, E 64 bytes', serialportTrips(s, 'E', 64, n, false));
    throughput('serialport HighReadFrequency', s);
    cpuIdle('serialport HighReadFrequency open, idle', 5);
    delete(s);
catch err
    fprintf('serialport HighReadFrequency: not available (%s)\n', err.message);
end

% ---- Legacy serial and .NET, at the default timer resolution ---------------------------------------------------------
legacySerial('legacy serial', portName, baudRate, n);
dotNetSerial('.NET SerialPort', portName, n);

% ---- The same, with the Windows timer at 1 ms -------------------------------------------------------------------------
if timerAvailable
    setTimerPeriod(1);
    fprintf('\nWindows timer resolution now: %.3f ms (timeBeginPeriod(1) in this process)\n', timerResolution());
    s = serialport(portName, baudRate);
    record('1 ms timer: serialport, E 1 byte, read()', serialportTrips(s, 'E', 1, n, false));
    record('1 ms timer: serialport, E 1 byte, poll', serialportTrips(s, 'E', 1, n, true));
    cpuIdle('1 ms timer: serialport open, idle', 5);
    delete(s);
    legacySerial('1 ms timer: legacy serial', portName, baudRate, n);
    dotNetSerial('1 ms timer: .NET SerialPort', portName, n);
    setTimerPeriod(0);
    fprintf('Windows timer resolution restored: %.3f ms\n', timerResolution());
else
    fprintf('\nSkipped the 1 ms timer tests: pyenv needs ExecutionMode "InProcess" for ctypes\n');
end

    function record(name, seconds)
        ms = sort(seconds(:)' * 1e3);
        fprintf('%-52s median %7.3f  95%% %7.3f  min %7.3f  max %7.3f ms\n', name, median(ms), ...
            ms(max(1, ceil(0.95 * numel(ms)))), ms(1), ms(end));
        results(end + 1) = struct('name', name, 'ms', ms);
    end

    function legacySerial(name, portName, baudRate, n)
        try
            warning('off', 'MATLAB:serial:fread:unsuccessfulRead');
            warning('off', 'all');
            sl = serial(portName, 'BaudRate', baudRate, 'InputBufferSize', 65536, 'Timeout', 2); %#ok<SERIAL>
            fopen(sl);
            warning('on', 'all');
            d = zeros(1, n);
            for k = 1:n
                t = tic;
                fwrite(sl, uint8([69 1 7]), 'uint8');
                fread(sl, 1, 'uint8');
                d(k) = toc(t);
            end
            record([name ', fread()'], d);
            fclose(sl);
            delete(sl);
        catch err
            warning('on', 'all');
            fprintf('%s: not available (%s)\n', name, err.message);
        end
    end

    function dotNetSerial(name, portName, n)
        try
            NET.addAssembly('System');
            sp = System.IO.Ports.SerialPort(portName);
            sp.ReadTimeout = 2000;
            sp.Open();
            for size = [1 64]
                message = NET.convertArray(uint8([69 size mod(0:size - 1, 256)]), 'System.Byte');
                reply = NET.createArray('System.Byte', size);
                d = zeros(1, n);
                for k = 1:n
                    t = tic;
                    sp.Write(message, 0, size + 2);
                    received = 0;
                    while received < size % Read() returns what has arrived, at least 1 byte
                        received = received + sp.Read(reply, received, size - received);
                    end
                    d(k) = toc(t);
                end
                record(sprintf('%s, E %d byte(s), Write() and Read()', name, size), d);
            end
            cpuIdle([name ' open, idle'], 5);
            sp.Close();
            sp.Dispose();
        catch err
            fprintf('%s: not available (%s)\n', name, err.message);
        end
    end
end

% ================================================================================================================

function d = serialportTrips(s, command, size, n, poll)
message = uint8([double(command) size mod(0:size - 1, 256)]);
d = zeros(1, n);
for k = 1:n
    t = tic;
    write(s, message, 'uint8');
    if isequal(poll, true)
        while s.NumBytesAvailable < size
        end
    elseif strcmp(poll, 'java')
        while s.NumBytesAvailable < size
            java.lang.Thread.sleep(1);
        end
    elseif strcmp(poll, 'pause')
        while s.NumBytesAvailable < size
            pause(0.001);
        end
    end
    reply = read(s, size, 'uint8');
    d(k) = toc(t);
    if ~isequal(double(reply(:)'), double(message(3:end)))
        error('Bad echo for %s %d', command, size);
    end
end
end

function d = writeOnly(writeFcn, n)
d = zeros(1, n);
for k = 1:n
    t = tic;
    writeFcn();
    d(k) = toc(t);
end
end

function throughput(name, s)
total = 4 * 1024 * 1024;
t = tic;
write(s, [uint8('R') typecast(uint32(total), 'uint8')], 'uint8');
received = 0;
while received < total % Chunks, so the Teensy never waits 120 ms for MATLAB to read (TX_TIMEOUT_MSEC)
    chunk = read(s, min(65536, total - received), 'uint8');
    if isempty(chunk)
        break
    end
    received = received + numel(chunk);
end
elapsed = toc(t);
fprintf('%-52s %.1f MB/s (%d bytes in %.0f ms)\n', [name ', device to PC'], total / elapsed / 1e6, received, ...
    elapsed * 1e3);
data = uint8(mod(0:total - 1, 251));
t = tic;
write(s, [uint8('W') typecast(uint32(total), 'uint8') data], 'uint8');
checksum = read(s, 1, 'uint8');
elapsed = toc(t);
if checksum ~= mod(sum(double(data)), 256)
    error('PC to device checksum mismatch');
end
fprintf('%-52s %.1f MB/s\n', [name ', PC to device'], total / elapsed / 1e6);
end

function cpuIdle(name, seconds)
% CPU time used by the MATLAB process while it waits, as a percentage of one core
process = System.Diagnostics.Process.GetCurrentProcess();
before = process.TotalProcessorTime.TotalMilliseconds;
pause(seconds);
process.Refresh();
used = process.TotalProcessorTime.TotalMilliseconds - before;
fprintf('%-52s CPU %.1f%% of one core\n', name, used / (seconds * 1e3) * 100);
end

function checkSketch(writeFcn, readFcn)
writeFcn(uint8('I'));
reply = char(readFcn(15));
if ~strcmp(reply(:)', sprintf('UsbLatencyTest\n'))
    error('The port is not running UsbLatencyTest.ino');
end
end

function ms = timerResolution()
% The Windows timer resolution in ms (NtQueryTimerResolution), or NaN without in-process Python
ms = NaN;
try
    if string(pyenv().ExecutionMode) ~= "InProcess"
        return
    end
    % pyrun, because MATLAB cannot see ctypes' dynamic attributes such as windll.ntdll
    ms = double(pyrun(["import ctypes", ...
        "lowest, highest, current = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.c_ulong()", ...
        "ctypes.windll.ntdll.NtQueryTimerResolution(ctypes.byref(lowest), ctypes.byref(highest), ctypes.byref(current))", ...
        "ms = current.value / 1e4"], "ms")); % 100 ns units
catch
end
end

function setTimerPeriod(ms)
% timeBeginPeriod(ms) for this process, or timeEndPeriod(1) when ms is 0
persistent period
if ms > 0
    pyrun(sprintf("import ctypes; ctypes.windll.winmm.timeBeginPeriod(%d)", ms));
    period = ms;
elseif ~isempty(period)
    pyrun(sprintf("import ctypes; ctypes.windll.winmm.timeEndPeriod(%d)", period));
    period = [];
end
end
