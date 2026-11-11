% dotnetRobustnessTest compares pulsepal.DotNetSerialPort (/MATLAB/+pulsepal in the PulsePal repository) with
% MATLAB's serialport, on a Pulse Pal running Pulse Pal firmware: latency at idle and under CPU load, large transfers,
% a long run, timeouts, a port in use by another program, a missing port, repeated opening and closing, and clearing a
% port without closing it.
%
% Usage: dotnetRobustnessTest('COM20')
% Uses the Python in the PulsePal repository's /Python/PulsePal/.venv (run "uv sync" there) for cpu_load.py and to
% hold the port from another process.
% Unplugging (surprise removal) is tested separately, by dotnetRemovalTest.m.

function dotnetRobustnessTest(portName, varargin)
p = inputParser;
addParameter(p, 'Quick', false); % Skips the CPU load and long runs
parse(p, varargin{:});
quick = p.Results.Quick;
here = fileparts(mfilename('fullpath'));
addpath(fullfile(here, '..', '..', '..', 'PulsePal', 'MATLAB')); % The PulsePal repository, cloned beside this one
nCores = feature('numcores');
nLogical = str2double(getenv('NUMBER_OF_PROCESSORS'));
fprintf('MATLAB %s, %s, %d cores (%d logical), DotNetSerialPort available: %d\n\n', version('-release'), portName, ...
    nCores, nLogical, pulsepal.DotNetSerialPort.isAvailable());
backends = {'serialport', 'dotnet'};

% ---- Latency, idle -------------------------------------------------------------------------------------------------
for b = backends
    port = openPort(b{1}, portName);
    report(sprintf('%s, handshake round trip, idle', b{1}), handshakes(port, 500));
    delete(port);
end

% ---- Under CPU load -------------------------------------------------------------------------------------------------
if ~quick
    for nBusy = [nLogical 2 * nLogical]
        load = startLoad(here, nBusy, 45);
        pause(2);
        fprintf('\n-- %d busy processes (normal priority) --\n', nBusy);
        for b = backends
            port = openPort(b{1}, portName);
            report(sprintf('%s, handshake round trip', b{1}), handshakes(port, 500));
            report(sprintf('%s, 60 KB custom train + confirm', b{1}), customTrains(port, 10));
            report(sprintf('%s, 178 byte parameter read (op 93)', b{1}), paramReads(port, 100));
            delete(port);
        end
        waitForLoad(load);
    end
end

% ---- Long run ---------------------------------------------------------------------------------------------------------
fprintf('\n');
if ~quick
    for b = backends
        n = 20000;
        if strcmp(b{1}, 'serialport')
            n = 2000; % 16 ms each
        end
        port = openPort(b{1}, portName);
        before = memoryUsed();
        d = handshakes(port, n);
        after = memoryUsed();
        report(sprintf('%s, %d round trips', b{1}, n), d);
        fprintf('   MATLAB memory change: %+.1f MB\n', (after - before) / 1e6);
        delete(port);
    end
end

% ---- A reply that never comes ----------------------------------------------------------------------------------------
fprintf('\n');
for b = backends
    port = openPort(b{1}, portName);
    port.Timeout = 1;
    write(port, uint8([213 77 0]), 'uint8'); % Op 77 has no reply
    lastwarn('');
    t = tic;
    reply = read(port, 1, 'uint8');
    [~, warningID] = lastwarn();
    fprintf('%-44s returned %d values after %.2f s, warning "%s"; ', [b{1} ', read with no reply'], ...
        numel(reply), toc(t), warningID);
    port.Timeout = 10;
    ok = isequal(handshakes(port, 1) > 0, true);
    fprintf('next round trip ok: %d\n', ok);
    delete(port);
end

% ---- A port another program has open ------------------------------------------------------------------------------------
holder = startHolder(portName, 6);
pause(2);
for b = backends
    try
        port = openPort(b{1}, portName);
        fprintf('%-44s opened!\n', [b{1} ', port held by Python']);
        delete(port);
    catch err
        fprintf('%-44s %s\n', [b{1} ', port held by Python'], oneLine(err.message));
    end
end
waitForLoad(holder);

% ---- The same port opened twice in MATLAB --------------------------------------------------------------------------------
for first = backends
    for second = backends
        a = openPort(first{1}, portName);
        try
            c = openPort(second{1}, portName);
            fprintf('%-44s opened!\n', sprintf('%s open, then %s', first{1}, second{1}));
            delete(c);
        catch err
            fprintf('%-44s %s\n', sprintf('%s open, then %s', first{1}, second{1}), oneLine(err.message));
        end
        delete(a);
    end
end

% ---- A port that does not exist -------------------------------------------------------------------------------------------
for b = backends
    try
        port = openPort(b{1}, 'COM99');
        delete(port);
    catch err
        fprintf('%-44s %s\n', [b{1} ', COM99'], oneLine(err.message));
    end
end

% ---- Opening and closing ---------------------------------------------------------------------------------------------------
fprintf('\n');
for b = backends
    t = tic;
    failures = 0;
    for k = 1:50
        port = openPort(b{1}, portName);
        failures = failures + (handshakes(port, 1) <= 0);
        delete(port);
    end
    fprintf('%-44s 50 cycles in %.1f s, %d failed; ', [b{1} ', open, round trip, close'], toc(t), failures);
    fprintf('Python can open the port afterwards: %d\n', pythonCanOpen(portName));
end

% ---- Clearing a port without closing it ------------------------------------------------------------------------------------
for b = backends
    port = openPort(b{1}, portName);
    handshakes(port, 1);
    clear port
    fprintf('%-44s Python can open the port at once: %d\n', [b{1} ', cleared without delete()'], ...
        pythonCanOpen(portName));
end
end

% ================================================================================================================

function port = openPort(backend, portName)
if strcmp(backend, 'serialport')
    port = serialport(portName, 12000000);
    setDTR(port, true);
else
    port = pulsepal.DotNetSerialPort(portName, 12000000);
end
end

function d = handshakes(port, n)
% Op 72: reply 75, then the firmware version (uint32). Returns the round trip times, or -1 for a bad reply.
d = zeros(1, n);
for k = 1:n
    t = tic;
    write(port, uint8([213 72]), 'uint8');
    reply = read(port, 5, 'uint8');
    d(k) = toc(t);
    if numel(reply) ~= 5 || reply(1) ~= 75
        d(k) = -1;
    end
end
end

function d = customTrains(port, n)
% Op 95: 10000 pulses (60006 bytes of data), then a confirm byte
nPulses = 10000;
message = [uint8([213 95 0]) typecast(uint32(nPulses), 'uint8') typecast(uint32(0:nPulses - 1), 'uint8') ...
    typecast(uint16(32768 * ones(1, nPulses)), 'uint8')];
d = zeros(1, n);
for k = 1:n
    t = tic;
    write(port, message, 'uint8');
    confirm = read(port, 1, 'uint8');
    d(k) = toc(t);
    if ~isequal(confirm, 1)
        d(k) = -1;
    end
end
end

function d = paramReads(port, n)
d = zeros(1, n);
for k = 1:n
    t = tic;
    write(port, uint8([213 93]), 'uint8');
    reply = read(port, 178, 'uint8');
    d(k) = toc(t);
    if numel(reply) ~= 178
        d(k) = -1;
    end
end
end

function report(name, d)
failures = sum(d < 0);
ms = sort(d(d >= 0) * 1e3);
fprintf('%-44s median %6.2f  95%% %6.2f  99%% %6.2f  max %7.2f ms  (%d failed)\n', name, median(ms), ...
    ms(ceil(0.95 * end)), ms(ceil(0.99 * end)), ms(end), failures);
end

function process = startLoad(here, n, seconds)
builder = java.lang.ProcessBuilder({pythonExe(), fullfile(here, 'cpu_load.py'), num2str(n), num2str(seconds)});
builder.redirectErrorStream(true);
process = builder.start();
end

function process = startHolder(portName, seconds)
code = sprintf('import serial, time; p = serial.Serial(''%s''); time.sleep(%d); p.close()', portName, seconds);
builder = java.lang.ProcessBuilder({pythonExe(), '-c', code});
builder.redirectErrorStream(true);
process = builder.start();
end

function waitForLoad(process)
process.waitFor();
end

function tf = pythonCanOpen(portName)
[status, ~] = system(sprintf('"%s" -c "import serial; serial.Serial(''%s'').close()"', pythonExe(), portName));
tf = status == 0;
end

function exe = pythonExe()
exe = fullfile(fileparts(mfilename('fullpath')), '..', '..', '..', 'PulsePal', 'Python', 'PulsePal', '.venv', 'Scripts', 'python.exe');
end

function bytes = memoryUsed()
m = memory();
bytes = m.MemUsedMATLAB;
end

function text = oneLine(text)
text = regexprep(strtrim(text), '\s+', ' ');
if numel(text) > 150
    text = [text(1:150) '...'];
end
end
