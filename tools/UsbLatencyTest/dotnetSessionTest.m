% dotnetSessionTest checks pulsepal.DotNetSerialPort over a MATLAB session, on a Pulse Pal 3 running Pulse Pal
% firmware: the first open (including loading .NET), memory over 100000 round trips, and reconnecting after the device
% is unplugged and plugged back in (simulated: 134 baud reboots the Teensy into its bootloader, and the Pulse Pal
% firmware is uploaded again with arduino-cli).
%
%   matlab -batch "dotnetSessionTest('COM20', '<Pulse Pal 3 build folder>')"

function dotnetSessionTest(portName, buildPath)
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', '..', '..', 'MATLAB'));
fprintf('MATLAB %s\n', version('-release'));

t = tic;
port = pulsepal.DotNetSerialPort(portName, 12000000);
fprintf('first open in this session (loads .NET): %.0f ms\n', toc(t) * 1e3);
t = tic;
delete(port);
port = pulsepal.DotNetSerialPort(portName, 12000000);
fprintf('close and open again: %.0f ms\n', toc(t) * 1e3);

% Memory over a long run: MATLAB's own, and the .NET heap before and after a full collection
before = memory().MemUsedMATLAB;
netBefore = double(System.GC.GetTotalMemory(true));
for block = 1:5
    for k = 1:20000
        write(port, uint8([213 72]), 'uint8');
        reply = read(port, 5, 'uint8');
        if reply(1) ~= 75
            error('Bad reply at round trip %d', k);
        end
    end
    fprintf('after %6d round trips: MATLAB memory %+6.1f MB, .NET heap %+6.2f MB (after a collection)\n', ...
        block * 20000, (memory().MemUsedMATLAB - before) / 1e6, ...
        (double(System.GC.GetTotalMemory(true)) - netBefore) / 1e6);
end

% Unplug and plug back in
port.BaudRate = 134;
pause(2);
try
    write(port, uint8([213 72]), 'uint8');
    fprintf('write after removal: no error!\n');
catch err
    fprintf('write after removal: %s\n', err.message);
end
delete(port);
cli = 'C:\Users\Josh\AppData\Local\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe';
firmware = fullfile(here, '..', '..', 'PulsePal');
[status, ~] = system(sprintf('"%s" upload --fqbn teensy:avr:teensy41 -p usb:0/140000/0/6 --protocol teensy --input-dir "%s" "%s"', ...
    cli, buildPath, firmware));
fprintf('firmware upload (the device plugged back in): status %d\n', status);
for attempt = 1:20
    pause(1);
    try
        port = pulsepal.DotNetSerialPort(portName, 12000000);
        write(port, uint8([213 72]), 'uint8');
        reply = read(port, 5, 'uint8');
        fprintf('reconnected after %d s: handshake %s\n', attempt, mat2str(reply));
        delete(port);
        return
    catch err
        lastError = err.message;
    end
end
fprintf('could not reconnect: %s\n', lastError);
end
