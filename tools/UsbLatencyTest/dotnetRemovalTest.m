% dotnetRemovalTest simulates unplugging a Pulse Pal 3 while MATLAB has its port open: setting the port to 134 baud
% makes a Teensy reboot into its bootloader, and its USB serial device disappears. Run each backend in its own MATLAB
% process: a crash ends the process before "survived" is printed. Upload the Pulse Pal firmware again afterwards.
%
%   matlab -batch "dotnetRemovalTest('COM20', 'dotnet', 'idle')"
% backend: 'serialport', 'dotnet' (pulsepal.DotNetSerialPort), or 'raw' (.NET SerialPort without the wrapper's
%          finalizer workaround)
% when:    'idle' (removed while nothing is happening) or 'reading' (removed during a read)

function dotnetRemovalTest(portName, backend, when)
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', '..', '..', 'PulsePal', 'MATLAB')); % The PulsePal repository, cloned beside this one
fprintf('MATLAB %s, backend %s, removal while %s\n', version('-release'), backend, when);
switch backend
    case 'serialport'
        port = serialport(portName, 12000000);
        writeFcn = @(bytes) write(port, bytes, 'uint8');
        readFcn = @(n) read(port, n, 'uint8');
        reboot = @() setBaud(port, 134);
    case 'dotnet'
        port = pulsepal.DotNetSerialPort(portName, 12000000);
        port.Timeout = 3;
        writeFcn = @(bytes) write(port, bytes, 'uint8');
        readFcn = @(n) read(port, n, 'uint8');
        reboot = @() setBaud(port, 134);
    case 'raw'
        NET.addAssembly('System');
        port = System.IO.Ports.SerialPort(portName);
        port.ReadTimeout = 3000;
        port.Open();
        writeFcn = @(bytes) port.Write(NET.convertArray(uint8(bytes), 'System.Byte'), 0, numel(bytes));
        readFcn = @(n) rawRead(port, n);
        reboot = @() setBaud(port, 134);
end
writeFcn(uint8([213 72]));
reply = readFcn(5);
fprintf('handshake before removal: %s\n', mat2str(double(reply)));
reboot();
if strcmp(when, 'reading')
    attempt('read (5 bytes) as the device disappears', @() readFcn(5));
else
    pause(2);
end
pause(1);
attempt('write after removal', @() writeFcn(uint8([213 72])));
attempt('read after removal', @() readFcn(5));
if ~strcmp(backend, 'raw')
    attempt('NumBytesAvailable after removal', @() port.NumBytesAvailable);
end
if strcmp(backend, 'raw')
    attempt('Close()', @() port.Close());
else
    attempt('delete()', @() delete(port));
end
clear port writeFcn readFcn reboot
fprintf('forcing .NET garbage collection and finalizers...\n');
System.GC.Collect();
System.GC.WaitForPendingFinalizers();
System.GC.Collect();
pause(2);
fprintf('survived\n');
end

function setBaud(port, baudRate)
port.BaudRate = baudRate;
end

function bytes = rawRead(port, n)
buffer = NET.createArray('System.Byte', n);
received = 0;
while received < n
    received = received + port.Read(buffer, received, n - received);
end
bytes = uint8(buffer);
end

function attempt(name, fcn)
t = tic;
try
    fcn();
    fprintf('%-42s ok (%.2f s)\n', name, toc(t));
catch err
    fprintf('%-42s error after %.2f s: %s\n', name, toc(t), regexprep(strtrim(err.message), '\s+', ' '));
end
end
