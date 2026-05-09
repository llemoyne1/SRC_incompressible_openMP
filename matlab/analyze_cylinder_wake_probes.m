function summary = analyze_cylinder_wake_probes(opts)
%ANALYZE_CYLINDER_WAKE_PROBES Quantitative post-processing for out_wake_probes.csv.
%
% Minimal usage:
%   opts = struct();
%   opts.workdir = '/home/llemoyne/gasdyn/mpcd/incompressible/rbps_work';
%   summary = analyze_cylinder_wake_probes(opts);
%
% Typical options:
%   opts.fileName       = 'out_wake_probes.csv';
%   opts.paramsFileName = 'params.kv';
%   opts.tMinAnalysis   = [];      % [] => automatic transient cut
%   opts.smoothWindow   = 3;       % moving average window in samples
%   opts.makeFigures    = true;
%   opts.saveFigures    = true;
%   opts.outputDir      = '';      % '' => workdir
%
% The script reads obstacleRadius from params.kv and estimates:
%   - Uref mean/std after transient;
%   - wake probe Ux/Uy statistics;
%   - dominant frequency and Strouhal number from p2_Uy, p3_Uy, p4_Uy,
%     and wake_Uy_asym.

if nargin < 1 || isempty(opts)
    opts = struct();
end

opts = set_default(opts, 'workdir', pwd);
opts = set_default(opts, 'fileName', 'out_wake_probes.csv');
opts = set_default(opts, 'paramsFileName', 'params.kv');
opts = set_default(opts, 'tMinAnalysis', []);
opts = set_default(opts, 'smoothWindow', 3);
opts = set_default(opts, 'makeFigures', true);
opts = set_default(opts, 'saveFigures', true);
opts = set_default(opts, 'outputDir', '');
opts = set_default(opts, 'signalNames', {'p2_Uy','p3_Uy','p4_Uy','wake_Uy_asym'});

if isempty(opts.outputDir)
    opts.outputDir = opts.workdir;
end

if ~exist(opts.outputDir, 'dir')
    mkdir(opts.outputDir);
end

dataFile = fullfile(opts.workdir, opts.fileName);
paramsFile = fullfile(opts.workdir, opts.paramsFileName);

if ~exist(dataFile, 'file')
    error('Cannot find wake probes file: %s', dataFile);
end

T = readtable(dataFile);

params = struct();
if exist(paramsFile, 'file')
    params = read_params_kv(paramsFile);
else
    warning('Cannot find params.kv: %s. Some quantities will be inferred.', paramsFile);
end

required = {'t','Uref','Nref','p1_Ux','p2_Ux','p3_Ux','p4_Ux', ...
            'p1_Uy','p2_Uy','p3_Uy','p4_Uy','wake_Uy_asym','recircLength'};
check_required_columns(T, required);

t = T.t;
t = t(:);
n = numel(t);

if n < 2
    error('Need at least two wake-probe samples.');
end

D = 2.0 * get_param(params, 'obstacleRadius', NaN);
if ~isfinite(D) || D <= 0
    if all(ismember({'p1_x','p2_x'}, T.Properties.VariableNames))
        D = T.p2_x(1) - T.p1_x(1);
        warning('D inferred from p2_x - p1_x = %.12g.', D);
    else
        D = NaN;
        warning('Could not determine cylinder diameter D.');
    end
end

cx = get_param(params, 'obstacleCx', NaN);
cy = get_param(params, 'obstacleCy', NaN);
Re_sample = NaN; %#ok<NASGU> % Placeholder for future dimensional analysis.

% Automatic transient removal.
if isempty(opts.tMinAnalysis)
    uTail = T.Uref(max(1, floor(0.75*n)):end);
    uPlateau = median(uTail, 'omitnan');
    iAuto = find(T.Uref >= 0.95 * uPlateau, 1, 'first');
    if isempty(iAuto)
        opts.tMinAnalysis = t(1) + 0.30 * (t(end) - t(1));
    else
        opts.tMinAnalysis = t(iAuto);
    end
end

idxA = t >= opts.tMinAnalysis;
if nnz(idxA) < 4
    warning('Analysis window contains only %d samples; reverting to all samples.', nnz(idxA));
    idxA = true(size(t));
    opts.tMinAnalysis = t(1);
end

TA = T(idxA, :);
tA = TA.t(:);

dt = median(diff(tA), 'omitnan');
fs = 1.0 / dt;

UrefMean = mean(TA.Uref, 'omitnan');
UrefStd = std(TA.Uref, 'omitnan');
NrefMean = mean(TA.Nref, 'omitnan');

probeNames = {'p1','p2','p3','p4'};
probeStats = struct();

for k = 1:numel(probeNames)
    p = probeNames{k};
    ux = TA.([p '_Ux']);
    uy = TA.([p '_Uy']);
    om = TA.([p '_omega']);
    nn = TA.([p '_N']);

    probeStats.(p).x = mean(TA.([p '_x']), 'omitnan');
    probeStats.(p).UxMean = mean(ux, 'omitnan');
    probeStats.(p).UxStd = std(ux, 'omitnan');
    probeStats.(p).UyMean = mean(uy, 'omitnan');
    probeStats.(p).UyStd = std(uy, 'omitnan');
    probeStats.(p).omegaMean = mean(om, 'omitnan');
    probeStats.(p).omegaStd = std(om, 'omitnan');
    probeStats.(p).NMean = mean(nn, 'omitnan');
end

signalNames = opts.signalNames;
spectra = struct();
bestSignal = '';
bestPower = -Inf;
bestFrequency = NaN;
bestStrouhal = NaN;

for k = 1:numel(signalNames)
    name = signalNames{k};
    if ~ismember(name, T.Properties.VariableNames)
        warning('Signal %s not found in table; skipped.', name);
        continue;
    end

    y = TA.(name);
    y = y(:);
    y = y - mean(y, 'omitnan');

    [freq, power, fDom, pDom] = simple_spectrum(tA, y);
    St = NaN;
    if isfinite(fDom) && isfinite(D) && isfinite(UrefMean) && UrefMean > 0
        St = fDom * D / UrefMean;
    end

    safeName = matlab.lang.makeValidName(name);
    spectra.(safeName).freq = freq;
    spectra.(safeName).power = power;
    spectra.(safeName).dominantFrequency = fDom;
    spectra.(safeName).dominantPower = pDom;
    spectra.(safeName).Strouhal = St;

    if isfinite(pDom) && pDom > bestPower
        bestPower = pDom;
        bestSignal = name;
        bestFrequency = fDom;
        bestStrouhal = St;
    end
end

recircMean = mean(TA.recircLength, 'omitnan');
recircStd = std(TA.recircLength, 'omitnan');
asymMean = mean(TA.wake_Uy_asym, 'omitnan');
asymStd = std(TA.wake_Uy_asym, 'omitnan');

summary = struct();
summary.workdir = opts.workdir;
summary.dataFile = dataFile;
summary.paramsFile = paramsFile;
summary.nSamples = height(T);
summary.nSamplesAnalysis = height(TA);
summary.tMin = min(t);
summary.tMax = max(t);
summary.tMinAnalysis = opts.tMinAnalysis;
summary.dt = dt;
summary.fs = fs;
summary.D = D;
summary.cx = cx;
summary.cy = cy;
summary.UrefMean = UrefMean;
summary.UrefStd = UrefStd;
summary.NrefMean = NrefMean;
summary.probeStats = probeStats;
summary.recircLengthMean = recircMean;
summary.recircLengthStd = recircStd;
summary.wakeUyAsymMean = asymMean;
summary.wakeUyAsymStd = asymStd;
summary.spectra = spectra;
summary.bestSignal = bestSignal;
summary.dominantFrequency = bestFrequency;
summary.Strouhal = bestStrouhal;

write_summary(summary, opts);

if opts.makeFigures
    make_all_figures(T, TA, opts, summary, signalNames);
end

fprintf('\n=== Wake probe summary ===\n');
fprintf('samples               : %d total, %d analysis\n', summary.nSamples, summary.nSamplesAnalysis);
fprintf('analysis window       : t >= %.6g\n', summary.tMinAnalysis);
fprintf('D                     : %.6g\n', summary.D);
fprintf('Uref mean +/- std     : %.6g +/- %.6g\n', summary.UrefMean, summary.UrefStd);
fprintf('Nref mean             : %.6g\n', summary.NrefMean);
fprintf('wake_Uy_asym mean/std : %.6g / %.6g\n', summary.wakeUyAsymMean, summary.wakeUyAsymStd);
fprintf('recircLength mean/std : %.6g / %.6g\n', summary.recircLengthMean, summary.recircLengthStd);
fprintf('best spectral signal  : %s\n', summary.bestSignal);
fprintf('dominant frequency    : %.6g\n', summary.dominantFrequency);
fprintf('Strouhal              : %.6g\n', summary.Strouhal);
fprintf('Summary written to    : %s\n\n', fullfile(opts.outputDir, 'wake_probe_summary.txt'));

end

% ======================================================================
% Helpers
% ======================================================================

function opts = set_default(opts, name, value)
if ~isfield(opts, name) || isempty(opts.(name))
    opts.(name) = value;
end
end

function params = read_params_kv(fileName)
params = struct();
fid = fopen(fileName, 'r');
if fid < 0
    error('Cannot open params file: %s', fileName);
end

cleaner = onCleanup(@() fclose(fid));

while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end

    line = strtrim(line);
    if isempty(line) || startsWith(line, '#')
        continue;
    end

    eq = strfind(line, '=');
    if isempty(eq)
        continue;
    end

    key = strtrim(line(1:eq(1)-1));
    valueRaw = strtrim(line(eq(1)+1:end));

    key = matlab.lang.makeValidName(key);

    valueNum = str2double(valueRaw);
    if strcmpi(valueRaw, 'true')
        params.(key) = true;
    elseif strcmpi(valueRaw, 'false')
        params.(key) = false;
    elseif isfinite(valueNum) || strcmpi(valueRaw, 'NaN') || strcmpi(valueRaw, 'Inf') || strcmpi(valueRaw, '-Inf')
        params.(key) = valueNum;
    else
        % Preserve strings and comma-separated lists as raw strings.
        params.(key) = valueRaw;
    end
end
end

function value = get_param(params, name, defaultValue)
key = matlab.lang.makeValidName(name);
if isfield(params, key)
    value = params.(key);
    if ischar(value) || isstring(value)
        tmp = str2double(value);
        if isfinite(tmp)
            value = tmp;
        else
            value = defaultValue;
        end
    end
else
    value = defaultValue;
end
end

function check_required_columns(T, names)
missing = {};
for i = 1:numel(names)
    if ~ismember(names{i}, T.Properties.VariableNames)
        missing{end+1} = names{i}; %#ok<AGROW>
    end
end

if ~isempty(missing)
    error('Missing required columns: %s', strjoin(missing, ', '));
end
end

function [freq, power, fDom, pDom] = simple_spectrum(t, y)
t = t(:);
y = y(:);

valid = isfinite(t) & isfinite(y);
t = t(valid);
y = y(valid);

freq = [];
power = [];
fDom = NaN;
pDom = NaN;

if numel(t) < 8
    warning('Too few samples for spectrum: %d. Need at least 8.', numel(t));
    return;
end

dt = median(diff(t), 'omitnan');
if ~isfinite(dt) || dt <= 0
    warning('Invalid time step for spectrum.');
    return;
end

% Interpolate on a uniform grid if needed.
tu = (t(1):dt:t(end)).';
if numel(tu) >= 8 && max(abs(diff(t) - dt)) > 1e-8 * max(1, dt)
    y = interp1(t, y, tu, 'linear', 'extrap');
    t = tu;
end

n = numel(y);
y = y - mean(y, 'omitnan');

if all(abs(y) < 1e-14)
    freq = (0:floor(n/2)).' / (n * dt);
    power = zeros(size(freq));
    return;
end

if n > 1
    win = 0.5 * (1.0 - cos(2.0*pi*(0:n-1).' / (n-1)));
else
    win = 1;
end

yw = y .* win;
Y = fft(yw);
nHalf = floor(n/2);
freq = (0:nHalf).' / (n * dt);
power = abs(Y(1:nHalf+1)).^2;

% Ignore DC.
if numel(power) >= 2
    [pDom, idx] = max(power(2:end));
    idx = idx + 1;
    fDom = freq(idx);
end
end

function write_summary(summary, opts)
fileName = fullfile(opts.outputDir, 'wake_probe_summary.txt');
fid = fopen(fileName, 'w');
if fid < 0
    warning('Could not write summary file: %s', fileName);
    return;
end

cleaner = onCleanup(@() fclose(fid));

fprintf(fid, "Wake probe summary\n");
fprintf(fid, "==================\n\n");
fprintf(fid, "workdir = %s\n", summary.workdir);
fprintf(fid, "dataFile = %s\n", summary.dataFile);
fprintf(fid, "paramsFile = %s\n", summary.paramsFile);
fprintf(fid, "nSamples = %d\n", summary.nSamples);
fprintf(fid, "nSamplesAnalysis = %d\n", summary.nSamplesAnalysis);
fprintf(fid, "tMin = %.16g\n", summary.tMin);
fprintf(fid, "tMax = %.16g\n", summary.tMax);
fprintf(fid, "tMinAnalysis = %.16g\n", summary.tMinAnalysis);
fprintf(fid, "dt = %.16g\n", summary.dt);
fprintf(fid, "fs = %.16g\n", summary.fs);
fprintf(fid, "D = %.16g\n", summary.D);
fprintf(fid, "cx = %.16g\n", summary.cx);
fprintf(fid, "cy = %.16g\n", summary.cy);
fprintf(fid, "UrefMean = %.16g\n", summary.UrefMean);
fprintf(fid, "UrefStd = %.16g\n", summary.UrefStd);
fprintf(fid, "NrefMean = %.16g\n", summary.NrefMean);
fprintf(fid, "wakeUyAsymMean = %.16g\n", summary.wakeUyAsymMean);
fprintf(fid, "wakeUyAsymStd = %.16g\n", summary.wakeUyAsymStd);
fprintf(fid, "recircLengthMean = %.16g\n", summary.recircLengthMean);
fprintf(fid, "recircLengthStd = %.16g\n", summary.recircLengthStd);
fprintf(fid, "bestSignal = %s\n", summary.bestSignal);
fprintf(fid, "dominantFrequency = %.16g\n", summary.dominantFrequency);
fprintf(fid, "Strouhal = %.16g\n", summary.Strouhal);

fprintf(fid, "\nProbe statistics after transient\n");
fprintf(fid, "probe,x,UxMean,UxStd,UyMean,UyStd,omegaMean,omegaStd,NMean\n");
names = fieldnames(summary.probeStats);
for i = 1:numel(names)
    p = summary.probeStats.(names{i});
    fprintf(fid, "%s,%.16g,%.16g,%.16g,%.16g,%.16g,%.16g,%.16g,%.16g\n", ...
        names{i}, p.x, p.UxMean, p.UxStd, p.UyMean, p.UyStd, ...
        p.omegaMean, p.omegaStd, p.NMean);
end
end

function make_all_figures(T, TA, opts, summary, signalNames)
outDir = opts.outputDir;
w = max(1, round(opts.smoothWindow));

% Figure 1: Uref and Nref.
fig = figure('Name', 'Wake Uref and Nref');
yyaxis left;
plot(T.t, T.Uref, '-o', 'DisplayName', 'Uref');
hold on;
xline(summary.tMinAnalysis, '--', 'DisplayName', 'tMinAnalysis');
ylabel('Uref');

yyaxis right;
plot(T.t, T.Nref, '-s', 'DisplayName', 'Nref');
ylabel('Nref');

xlabel('t');
title('Reference upstream velocity and occupancy');
grid on;
legend('Location', 'best');
save_fig(fig, fullfile(outDir, 'fig_wake_Uref_Nref.png'), opts);

% Figure 2: Ux probes.
fig = figure('Name', 'Wake Ux probes');
hold on;
plot(T.t, smooth_series(T.p1_Ux, w), '-o', 'DisplayName', 'p1 Ux');
plot(T.t, smooth_series(T.p2_Ux, w), '-o', 'DisplayName', 'p2 Ux');
plot(T.t, smooth_series(T.p3_Ux, w), '-o', 'DisplayName', 'p3 Ux');
plot(T.t, smooth_series(T.p4_Ux, w), '-o', 'DisplayName', 'p4 Ux');
plot(T.t, T.Uref, 'k--', 'DisplayName', 'Uref');
xline(summary.tMinAnalysis, '--', 'DisplayName', 'tMinAnalysis');
xlabel('t');
ylabel('Ux');
title('Streamwise wake velocity probes');
grid on;
legend('Location', 'best');
save_fig(fig, fullfile(outDir, 'fig_wake_Ux_probes.png'), opts);

% Figure 3: Uy probes.
fig = figure('Name', 'Wake Uy probes');
hold on;
plot(T.t, smooth_series(T.p1_Uy, w), '-o', 'DisplayName', 'p1 Uy');
plot(T.t, smooth_series(T.p2_Uy, w), '-o', 'DisplayName', 'p2 Uy');
plot(T.t, smooth_series(T.p3_Uy, w), '-o', 'DisplayName', 'p3 Uy');
plot(T.t, smooth_series(T.p4_Uy, w), '-o', 'DisplayName', 'p4 Uy');
xline(summary.tMinAnalysis, '--', 'DisplayName', 'tMinAnalysis');
xlabel('t');
ylabel('Uy');
title('Transverse wake velocity probes');
grid on;
legend('Location', 'best');
save_fig(fig, fullfile(outDir, 'fig_wake_Uy_probes.png'), opts);

% Figure 4: asymmetry and recirculation.
fig = figure('Name', 'Wake asymmetry and recirculation');
yyaxis left;
plot(T.t, smooth_series(T.wake_Uy_asym, w), '-o', 'DisplayName', 'wake Uy asym');
ylabel('wake Uy asym');

yyaxis right;
plot(T.t, smooth_series(T.recircLength, w), '-s', 'DisplayName', 'recircLength');
ylabel('recircLength');

xline(summary.tMinAnalysis, '--', 'DisplayName', 'tMinAnalysis');
xlabel('t');
title('Wake asymmetry and recirculation length');
grid on;
legend('Location', 'best');
save_fig(fig, fullfile(outDir, 'fig_wake_asym_recirc.png'), opts);

% Figure 5: spectra.
fig = figure('Name', 'Wake spectra');
hold on;
for k = 1:numel(signalNames)
    name = signalNames{k};
    safeName = matlab.lang.makeValidName(name);
    if isfield(summary.spectra, safeName)
        sp = summary.spectra.(safeName);
        if ~isempty(sp.freq)
            plot(sp.freq, sp.power, '-o', 'DisplayName', sprintf('%s, f*=%.4g, St=%.4g', ...
                name, sp.dominantFrequency, sp.Strouhal));
        end
    end
end
xlabel('frequency');
ylabel('periodogram power');
title('Wake probe spectra after transient');
grid on;
legend('Location', 'best');
save_fig(fig, fullfile(outDir, 'fig_wake_spectra.png'), opts);
end

function y = smooth_series(x, w)
x = x(:);
if w <= 1
    y = x;
    return;
end
kernel = ones(w, 1) / w;
valid = isfinite(x);
x0 = x;
x0(~valid) = 0;
den = conv(double(valid), kernel, 'same');
num = conv(x0, kernel, 'same');
y = num ./ max(den, eps);
end

function save_fig(fig, fileName, opts)
if ~opts.saveFigures
    return;
end

try
    exportgraphics(fig, fileName, 'Resolution', 160);
catch
    try
        saveas(fig, fileName);
    catch ME
        warning('Could not save figure %s: %s', fileName, ME.message);
    end
end
end
