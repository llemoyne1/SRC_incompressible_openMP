function S = analyze_open_channel_poiseuille_validation_0065(varargin)
%ANALYZE_OPEN_CHANNEL_POISEUILLE_VALIDATION_0065 Summarize 0065 validation.
%
% Usage from repository root:
%   cd matlab
%   S = analyze_open_channel_poiseuille_validation_0065('root','..');
%   cd ..
%
% Outputs:
%   runs/open_channel_poiseuille_validation_0065/summary_open_channel_validation.csv
%   runs/open_channel_poiseuille_validation_0065/profiles/profiles_y_<case>.csv
%   runs/open_channel_poiseuille_validation_0065/profiles/profiles_x_<case>.csv
%
% A non-default run root can be supplied with:
%   S = analyze_open_channel_poiseuille_validation_0065('root','..', ...
%       'runRoot','runs/test_0065_short');

opts = parse_options(varargin{:});
repoRoot = char(opts.root);
if strlength(string(opts.runRoot)) > 0
    runRoot = char(opts.runRoot);
    if ~isfolder(runRoot)
        runRoot = fullfile(repoRoot, char(opts.runRoot));
    end
else
    runRoot = fullfile(repoRoot, 'runs', 'open_channel_poiseuille_validation_0065');
end
profileDir = fullfile(runRoot, 'profiles');

if ~isfolder(runRoot)
    error('Run directory not found: %s', runRoot);
end
if ~isfolder(profileDir)
    mkdir(profileDir);
end

D = dir(runRoot);
rows = struct([]);
profileYTables = struct();

for k = 1:numel(D)
    if ~D(k).isdir || startsWith(D(k).name, '.') || strcmp(D(k).name, 'params') || strcmp(D(k).name, 'logs') || strcmp(D(k).name, 'profiles')
        continue;
    end

    caseLabel = D(k).name;
    caseDir = fullfile(runRoot, caseLabel);
    csvFile = fullfile(caseDir, 'summary_runtime.csv');
    if ~isfile(csvFile)
        warning('Skipping %s: missing summary_runtime.csv', caseLabel);
        continue;
    end

    T = readtable(csvFile);
    if isempty(T)
        warning('Skipping %s: empty summary_runtime.csv', caseLabel);
        continue;
    end

    paramsFile = fullfile(caseDir, 'params_used.kv');
    finalStateFile = find_final_state_file(caseDir);
    hasState = ~isempty(finalStateFile);

    profileStats = default_profile_stats();
    if hasState && isfile(paramsFile)
        [Y, X, profileStats] = compute_final_profiles(paramsFile, finalStateFile, opts);
        writetable(Y, fullfile(profileDir, sprintf('profiles_y_%s.csv', caseLabel)));
        writetable(X, fullfile(profileDir, sprintf('profiles_x_%s.csv', caseLabel)));
        safeName = matlab.lang.makeValidName(caseLabel);
        profileYTables.(safeName) = Y;
    else
        warning('Skipping profile computation for %s: state or params missing.', caseLabel);
    end

    i1 = 1;
    ie = height(T);
    r = struct();
    r.caseLabel = string(caseLabel);
    r.nRows = height(T);
    r.timeFinal = getv(T, 'time', ie, NaN);
    r.NpFirst = getv(T, 'Np', i1, NaN);
    r.NpFinal = getv(T, 'Np', ie, NaN);
    r.totalMassFirst = getv(T, 'totalMass', i1, NaN);
    r.totalMassFinal = getv(T, 'totalMass', ie, NaN);
    r.meanVxFirst = getv(T, 'meanVx', i1, NaN);
    r.meanVxFinal = getv(T, 'meanVx', ie, NaN);
    r.meanVyFinal = getv(T, 'meanVy', ie, NaN);
    r.kBTMin = mincol(T, 'kBTEstimate');
    r.kBTMean = meancol(T, 'kBTEstimate');
    r.kBTMax = maxcol(T, 'kBTEstimate');
    r.stdNFirst = getv(T, 'stdN', i1, NaN);
    r.stdNFinal = getv(T, 'stdN', ie, NaN);
    r.minNFinal = getv(T, 'minN', ie, NaN);
    r.maxNFinal = getv(T, 'maxN', ie, NaN);

    r.q6AppliedFinal = getv(T, 'q6Applied', ie, NaN);
    r.q6ConvergedFinal = getv(T, 'q6Converged', ie, NaN);
    r.q6DivBeforeFinal = getv(T, 'q6DivBeforeRms', ie, NaN);
    r.q6DivAfterFinal = getv(T, 'q6DivAfterProjectedFluxRms', ie, NaN);
    r.q6DivRatioFinal = safe_ratio(r.q6DivAfterFinal, r.q6DivBeforeFinal);
    r.q6OpenFluxBalanceFinal = getv(T, 'q6OpenBoundaryFluxBalance', ie, NaN);

    r.q9AppliedFinal = getv(T, 'q9Applied', ie, NaN);
    r.q9ConvergedFinal = getv(T, 'q9Converged', ie, NaN);
    r.q9MassDivBeforeFinal = getv(T, 'q9MassFluxDivBeforeRms', ie, NaN);
    r.q9MassDivAfterFinal = getv(T, 'q9MassFluxDivAfterRms', ie, NaN);
    r.q9MassDivRatioFinal = safe_ratio(r.q9MassDivAfterFinal, r.q9MassDivBeforeFinal);
    r.q9DensityMeanFinal = getv(T, 'q9DensityMean', ie, NaN);
    r.q9DensityStdBeforeFinal = getv(T, 'q9DensityStdBefore', ie, NaN);
    r.q9DensityStdAfterEstimateFinal = getv(T, 'q9DensityStdAfterEstimate', ie, NaN);
    r.q9DensityStdRatioEstimateFinal = getv(T, 'q9DensityStdRatioEstimate', ie, NaN);
    r.q9OpenMassFluxBalanceFinal = getv(T, 'q9OpenBoundaryMassFluxBalance', ie, NaN);

    r.virialEnabledFinal = getv(T, 'virialEnabled', ie, NaN);
    r.virialKickAppliedFinal = getv(T, 'virialKickApplied', ie, NaN);
    r.virialExcludedCellsFinal = getv(T, 'virialOpenBoundaryExcludedCells', ie, NaN);
    r.virialActiveCellsFinal = getv(T, 'virialActiveCells', ie, NaN);
    r.virialRhoDefectRelFinal = getv(T, 'virialRhoDefectRelRms', ie, NaN);
    r.PkinMeanFinal = getv(T, 'PkinMean', ie, NaN);
    r.PvirMeanFinal = getv(T, 'PvirMean', ie, NaN);
    r.PtotMeanFinal = getv(T, 'PtotMean', ie, NaN);
    r.gradPdriveRmsFinal = getv(T, 'gradPdriveRms', ie, NaN);
    r.virialDuOverThermalRmsFinal = getv(T, 'virialDuOverThermalRms', ie, NaN);
    r.virialMomentumResidualAfterFinal = getv(T, 'virialMomentumResidualAfterCorrection', ie, NaN);

    fields = fieldnames(profileStats);
    for j = 1:numel(fields)
        r.(fields{j}) = profileStats.(fields{j});
    end

    rows = [rows; r]; %#ok<AGROW>
end

if isempty(rows)
    error('No completed 0065 cases found under %s', runRoot);
end

S = struct2table(rows);
S = sortrows(S, 'caseLabel');
outCsv = fullfile(runRoot, 'summary_open_channel_validation.csv');
writetable(S, outCsv);

disp(S);
fprintf('Wrote %s\n', outCsv);
fprintf('Wrote profile CSV files under %s\n', profileDir);

plot_profiles_if_possible(profileYTables);
end

function opts = parse_options(varargin)
opts.root = '..';
opts.runRoot = '';
opts.openExclusionCells = NaN;
opts.excludeWallCells = 2;
if mod(numel(varargin), 2) ~= 0
    error('Options must be provided as name/value pairs.');
end
for i = 1:2:numel(varargin)
    name = lower(string(varargin{i}));
    value = varargin{i+1};
    switch name
        case 'root'
            opts.root = value;
        case 'runroot'
            opts.runRoot = value;
        case 'openexclusioncells'
            opts.openExclusionCells = value;
        case 'excludewallcells'
            opts.excludeWallCells = value;
        otherwise
            error('Unknown option: %s', name);
    end
end
end

function stateFile = find_final_state_file(caseDir)
D = dir(fullfile(caseDir, 'state_step_*.smpcd'));
if isempty(D)
    stateFile = '';
    return;
end
steps = zeros(numel(D),1);
for i = 1:numel(D)
    tok = regexp(D(i).name, 'state_step_(\d+)\.smpcd', 'tokens', 'once');
    if isempty(tok)
        steps(i) = -1;
    else
        steps(i) = str2double(tok{1});
    end
end
[~, idx] = max(steps);
stateFile = fullfile(caseDir, D(idx).name);
end

function stats = default_profile_stats()
stats = struct();
stats.profileStateFound = 0;
stats.profileOpenExclusionCells = NaN;
stats.profileBulkRhoMean = NaN;
stats.profileBulkRhoStd = NaN;
stats.profileBulkKBTMean = NaN;
stats.profileBulkUxMean = NaN;
stats.profileUxCenter = NaN;
stats.profileUxWallMean = NaN;
stats.profileUxCenterMinusWall = NaN;
stats.profileUxQuadraticR2 = NaN;
stats.profilePkinMean = NaN;
stats.profilePvirMean = NaN;
stats.profilePtotMean = NaN;
end

function [Y, X, stats] = compute_final_profiles(paramsFile, stateFile, opts)
Lx = kv_double(paramsFile, 'Lx', 2.0);
Ly = kv_double(paramsFile, 'Ly', 1.0);
Nx = round(kv_double(paramsFile, 'Nx', 64));
Ny = round(kv_double(paramsFile, 'Ny', 32));
virialK = kv_double(paramsFile, 'virialK', 0.0);
virialEnabled = kv_bool(paramsFile, 'virialKickEnable', false) || kv_bool(paramsFile, 'virialDiagnosticsEnable', false);
ex = opts.openExclusionCells;
if isnan(ex)
    ex = kv_double(paramsFile, 'virialOpenBoundaryExclusionCells', 3);
end
ex = max(0, round(ex));
ex = min(ex, floor((Nx - 1) / 2));

bcLeft = lower(strtrim(kv_string(paramsFile, 'bcLeft', 'periodic')));
bcRight = lower(strtrim(kv_string(paramsFile, 'bcRight', 'periodic')));
excludeX = false(1, Nx);
if is_open_bc(bcLeft)
    excludeX(1:ex) = true;
end
if is_open_bc(bcRight)
    excludeX((Nx-ex+1):Nx) = true;
end
activeX = ~excludeX;
if ~any(activeX)
    activeX(:) = true;
end

state = read_smpcd_state(stateFile);
cellArea = (Lx * Ly) / double(Nx * Ny);

dx = Lx / double(Nx);
dy = Ly / double(Ny);
ix = floor(state.x ./ dx) + 1;
iy = floor(state.y ./ dy) + 1;
ix = max(1, min(Nx, ix));
iy = max(1, min(Ny, iy));
cellId = ix + (iy - 1) .* Nx;
nc = Nx * Ny;

massCell = accumarray(cellId, state.mass, [nc 1], @sum, 0.0);
countCell = accumarray(cellId, ones(size(cellId)), [nc 1], @sum, 0.0);
pxCell = accumarray(cellId, state.mass .* state.vx, [nc 1], @sum, 0.0);
pyCell = accumarray(cellId, state.mass .* state.vy, [nc 1], @sum, 0.0);

uxCellVec = zeros(nc,1);
uyCellVec = zeros(nc,1);
validMass = massCell > 0;
uxCellVec(validMass) = pxCell(validMass) ./ massCell(validMass);
uyCellVec(validMass) = pyCell(validMass) ./ massCell(validMass);

dvx = state.vx - uxCellVec(cellId);
dvy = state.vy - uyCellVec(cellId);
relKCell = accumarray(cellId, state.mass .* (dvx.^2 + dvy.^2), [nc 1], @sum, 0.0);
kBTCellVec = zeros(nc,1);
validTemp = countCell > 1;
kBTCellVec(validTemp) = relKCell(validTemp) ./ (2.0 .* (countCell(validTemp) - 1.0));

rhoCellVec = massCell ./ cellArea;

rho = reshape(rhoCellVec, [Nx Ny])';
count = reshape(countCell, [Nx Ny])';
ux = reshape(uxCellVec, [Nx Ny])';
uy = reshape(uyCellVec, [Nx Ny])';
kBT = reshape(kBTCellVec, [Nx Ny])';

activeMask = repmat(activeX, Ny, 1);
rhoRef = mean(rho(activeMask));
Pkin = rho .* kBT;
if virialEnabled
    Pvir = virialK .* (rho - rhoRef);
else
    Pvir = zeros(size(rho));
end
Ptot = Pkin + Pvir;

xCenter = ((1:Nx)' - 0.5) .* dx;
yCenter = ((1:Ny)' - 0.5) .* dy;

Y = table();
Y.yIndex = (1:Ny)';
Y.yCenter = yCenter;
Y.countMean = mean(count(:, activeX), 2);
Y.rhoMean = mean(rho(:, activeX), 2);
Y.uxMean = mean(ux(:, activeX), 2);
Y.uyMean = mean(uy(:, activeX), 2);
Y.kBTMean = mean(kBT(:, activeX), 2);
Y.PkinMean = mean(Pkin(:, activeX), 2);
Y.PvirMean = mean(Pvir(:, activeX), 2);
Y.PtotMean = mean(Ptot(:, activeX), 2);

X = table();
X.xIndex = (1:Nx)';
X.xCenter = xCenter;
X.isOpenReservoirExcluded = excludeX(:);
X.countMean = mean(count, 1)';
X.rhoMean = mean(rho, 1)';
X.uxMean = mean(ux, 1)';
X.uyMean = mean(uy, 1)';
X.kBTMean = mean(kBT, 1)';
X.PkinMean = mean(Pkin, 1)';
X.PvirMean = mean(Pvir, 1)';
X.PtotMean = mean(Ptot, 1)';

stats = default_profile_stats();
stats.profileStateFound = 1;
stats.profileOpenExclusionCells = ex;
stats.profileBulkRhoMean = mean(rho(activeMask));
stats.profileBulkRhoStd = std(rho(activeMask));
stats.profileBulkKBTMean = mean(kBT(activeMask));
stats.profileBulkUxMean = mean(ux(activeMask));
stats.profilePkinMean = mean(Pkin(activeMask));
stats.profilePvirMean = mean(Pvir(activeMask));
stats.profilePtotMean = mean(Ptot(activeMask));

centerIdx = max(1, min(Ny, round((Ny + 1) / 2)));
stats.profileUxCenter = Y.uxMean(centerIdx);
stats.profileUxWallMean = 0.5 * (Y.uxMean(1) + Y.uxMean(end));
stats.profileUxCenterMinusWall = stats.profileUxCenter - stats.profileUxWallMean;

wallEx = max(0, round(opts.excludeWallCells));
fitIdx = (1+wallEx):(Ny-wallEx);
if numel(fitIdx) >= 4
    yf = Y.yCenter(fitIdx);
    uf = Y.uxMean(fitIdx);
    p = polyfit(yf, uf, 2);
    pred = polyval(p, yf);
    ssRes = sum((uf - pred).^2);
    ssTot = sum((uf - mean(uf)).^2);
    if ssTot > 0
        stats.profileUxQuadraticR2 = 1.0 - ssRes / ssTot;
    end
end
end

function tf = is_open_bc(s)
tf = any(strcmpi(s, {'inlet','input','outlet','output','open'}));
end

function s = kv_string(filename, key, defaultValue)
s = defaultValue;
fid = fopen(filename, 'r');
if fid < 0
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    c = strfind(line, '#');
    if ~isempty(c)
        line = line(1:c(1)-1);
    end
    tok = regexp(line, '^\s*([^=\s]+)\s*=\s*(.*?)\s*$', 'tokens', 'once');
    if ~isempty(tok) && strcmp(tok{1}, key)
        s = tok{2};
        return;
    end
end
end

function x = kv_double(filename, key, defaultValue)
s = kv_string(filename, key, '');
x = str2double(s);
if isnan(x)
    x = defaultValue;
end
end

function b = kv_bool(filename, key, defaultValue)
s = lower(strtrim(kv_string(filename, key, '')));
if any(strcmp(s, {'true','1','yes','on'}))
    b = true;
elseif any(strcmp(s, {'false','0','no','off'}))
    b = false;
else
    b = defaultValue;
end
end

function v = getv(T, name, idx, defaultValue)
if ismember(name, T.Properties.VariableNames)
    v = T.(name)(idx);
else
    v = defaultValue;
end
end

function v = mincol(T, name)
if ismember(name, T.Properties.VariableNames)
    v = min(T.(name));
else
    v = NaN;
end
end

function v = maxcol(T, name)
if ismember(name, T.Properties.VariableNames)
    v = max(T.(name));
else
    v = NaN;
end
end

function v = meancol(T, name)
if ismember(name, T.Properties.VariableNames)
    v = mean(T.(name));
else
    v = NaN;
end
end

function r = safe_ratio(a, b)
if isnan(a) || isnan(b) || abs(b) < eps
    r = NaN;
else
    r = a ./ b;
end
end

function plot_profiles_if_possible(profileYTables)
names = fieldnames(profileYTables);
if isempty(names)
    return;
end
try
    figure('Name','0065 Ux(y) profiles');
    hold on;
    for i = 1:numel(names)
        Y = profileYTables.(names{i});
        plot(Y.uxMean, Y.yCenter, '-o', 'DisplayName', names{i});
    end
    xlabel('Ux');
    ylabel('y');
    legend('Interpreter','none', 'Location','best');
    grid on;
    title('0065 final open-channel Ux(y) profiles');

    figure('Name','0065 rho(y) profiles');
    hold on;
    for i = 1:numel(names)
        Y = profileYTables.(names{i});
        plot(Y.rhoMean, Y.yCenter, '-o', 'DisplayName', names{i});
    end
    xlabel('rho');
    ylabel('y');
    legend('Interpreter','none', 'Location','best');
    grid on;
    title('0065 final density profiles');

    figure('Name','0065 Ptot(y) profiles');
    hold on;
    for i = 1:numel(names)
        Y = profileYTables.(names{i});
        plot(Y.PtotMean, Y.yCenter, '-o', 'DisplayName', names{i});
    end
    xlabel('Ptot');
    ylabel('y');
    legend('Interpreter','none', 'Location','best');
    grid on;
    title('0065 final total pressure profiles');
catch ME
    warning('Plotting failed: %s', ME.message);
end
end
