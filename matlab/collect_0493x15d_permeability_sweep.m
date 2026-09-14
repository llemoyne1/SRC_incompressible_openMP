function T = collect_0493x15d_permeability_sweep()
%COLLECT_0493X15D_PERMEABILITY_SWEEP
% Agrège les summaries du sweep x15d de perméabilité.
%
% À lancer depuis SRC_GPU-SURF/matlab :
%
%   T = collect_0493x15d_permeability_sweep();
%
% Produit :
%   ../runs/0493x15d_permeability_sweep/analysis/
%       sweep_0493x15d.csv
%       sweep_0493x15d.txt
%
% Le point 1x provient du run x15c de référence.

cases = {
    '0p5x', 0.003152697436026578, '../runs/0493x15d_permeability_sweep/0p5x/fresh'
    '1x',   0.006305394872053156, '../runs/0493x15c_chi_vp_permeability/fresh'
    '2x',   0.012610789744106312, '../runs/0493x15d_permeability_sweep/2x/fresh'
    '4x',   0.025221579488212624, '../runs/0493x15d_permeability_sweep/4x/fresh'
    '8x',   0.050443158976425248, '../runs/0493x15d_permeability_sweep/8x/fresh'
    '16x',  0.100886317952850496, '../runs/0493x15d_permeability_sweep/16x/fresh'
};

n = size(cases,1);

tag = strings(n,1);
bodyAx = nan(n,1);
status = strings(n,1);

steadyNetMassFlux = nan(n,1);
steadyGrossMassFlux = nan(n,1);
steadyDirectionalBias = nan(n,1);
steadyPermeationVelocity = nan(n,1);
steadyGrossCrossingSpeed = nan(n,1);
permeabilityMobility_UoverAx = nan(n,1);
meanBulkUx = nan(n,1);
throughflowOverBulkUx = nan(n,1);

meanDarcyReactionForceX = nan(n,1);
meanChiVpReactionForceX = nan(n,1);
meanTotalReactionForceX = nan(n,1);
meanBodyForceX = nan(n,1);
steadyReactionOverBody = nan(n,1);

meanSolidLeakRms = nan(n,1);

rmsRelativeX = nan(n,1);
rmsRelativeY = nan(n,1);

cumulativeNetCrossingMassFraction = nan(n,1);
cumulativeGrossCrossingMassFraction = nan(n,1);

for i = 1:n
    tag(i) = string(cases{i,1});
    bodyAx(i) = cases{i,2};
    runDir = cases{i,3};

    summaryPath = fullfile(runDir, 'analysis', 'summary_0493x15c.txt');

    % Tolère aussi un summary placé directement sous le run.
    if ~isfile(summaryPath)
        alt = fullfile(runDir, 'summary_0493x15c.txt');
        if isfile(alt)
            summaryPath = alt;
        end
    end

    assert(isfile(summaryPath), ...
        'Missing summary for %s: %s', tag(i), summaryPath);

    S = readKeyValueSummary(summaryPath);

    status(i) = getString(S, 'status');

    steadyNetMassFlux(i) = getNumber(S, 'steadyNetMassFlux');
    steadyGrossMassFlux(i) = getNumber(S, 'steadyGrossMassFlux');
    steadyDirectionalBias(i) = getNumber(S, 'steadyDirectionalBias');
    steadyPermeationVelocity(i) = getNumber(S, 'steadyPermeationVelocity');
    steadyGrossCrossingSpeed(i) = getNumber(S, 'steadyGrossCrossingSpeed');
    permeabilityMobility_UoverAx(i) = getNumber(S, 'permeabilityMobility_UoverAx');

    meanBulkUx(i) = getNumber(S, 'meanBulkUx');
    throughflowOverBulkUx(i) = getNumber(S, 'throughflowOverBulkUx');

    meanDarcyReactionForceX(i) = getNumber(S, 'meanDarcyReactionForceX');
    meanChiVpReactionForceX(i) = getNumber(S, 'meanChiVpReactionForceX');
    meanTotalReactionForceX(i) = getNumber(S, 'meanTotalReactionForceX');
    meanBodyForceX(i) = getNumber(S, 'meanBodyForceX');
    steadyReactionOverBody(i) = getNumber(S, 'steadyReactionOverBody');

    meanSolidLeakRms(i) = getNumber(S, 'meanSolidLeakRms');

    rmsRelativeX(i) = getNumber(S, 'rmsRelativeX');
    rmsRelativeY(i) = getNumber(S, 'rmsRelativeY');

    cumulativeNetCrossingMassFraction(i) = ...
        getNumber(S, 'cumulativeNetCrossingMassFraction');
    cumulativeGrossCrossingMassFraction(i) = ...
        getNumber(S, 'cumulativeGrossCrossingMassFraction');
end

T = table( ...
    tag, bodyAx, status, ...
    steadyPermeationVelocity, permeabilityMobility_UoverAx, ...
    meanBulkUx, throughflowOverBulkUx, ...
    steadyNetMassFlux, steadyGrossMassFlux, steadyDirectionalBias, ...
    steadyGrossCrossingSpeed, ...
    meanDarcyReactionForceX, meanChiVpReactionForceX, ...
    meanTotalReactionForceX, meanBodyForceX, steadyReactionOverBody, ...
    meanSolidLeakRms, ...
    cumulativeNetCrossingMassFraction, ...
    cumulativeGrossCrossingMassFraction, ...
    rmsRelativeX, rmsRelativeY);

outDir = '../runs/0493x15d_permeability_sweep/analysis';
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

csvPath = fullfile(outDir, 'sweep_0493x15d.csv');
writetable(T, csvPath);

txtPath = fullfile(outDir, 'sweep_0493x15d.txt');
fid = fopen(txtPath, 'w');
assert(fid >= 0, 'Cannot create %s', txtPath);

fprintf(fid, '0493x15d permeability sweep\n');
fprintf(fid, '========================================\n\n');

for i = 1:height(T)
    fprintf(fid, ...
        ['%-4s ax=% .10e  Uperm=% .10e  Uperm/ax=% .10e  ' ...
         'Ubulk=% .10e  Uperm/Ubulk=% .6f  ' ...
         'Freact/Fbody=% .6f  bias=% .6e  status=%s\n'], ...
        char(T.tag(i)), ...
        T.bodyAx(i), ...
        T.steadyPermeationVelocity(i), ...
        T.permeabilityMobility_UoverAx(i), ...
        T.meanBulkUx(i), ...
        T.throughflowOverBulkUx(i), ...
        T.steadyReactionOverBody(i), ...
        T.steadyDirectionalBias(i), ...
        char(T.status(i)));
end

fclose(fid);

disp(T(:, { ...
    'tag', ...
    'bodyAx', ...
    'steadyPermeationVelocity', ...
    'permeabilityMobility_UoverAx', ...
    'meanBulkUx', ...
    'throughflowOverBulkUx', ...
    'steadyReactionOverBody', ...
    'steadyDirectionalBias', ...
    'status'}));

fprintf('\nWritten:\n  %s\n  %s\n', csvPath, txtPath);

% --- Courbe principale : Uperm vs ax
figure;
plot(T.bodyAx, T.steadyPermeationVelocity, 'o-');
xlabel('bodyAccelerationX');
ylabel('U_{perm}');
title('0493x15d - permeation velocity');
grid on;

% --- Mobilité : Uperm/ax
figure;
plot(T.bodyAx, T.permeabilityMobility_UoverAx, 'o-');
xlabel('bodyAccelerationX');
ylabel('U_{perm}/a_x');
title('0493x15d - permeability mobility');
grid on;

% --- Comparaison Uperm / Ubulk
figure;
plot(T.bodyAx, T.throughflowOverBulkUx, 'o-');
xlabel('bodyAccelerationX');
ylabel('U_{perm}/U_{bulk}');
title('0493x15d - throughflow / bulk velocity');
grid on;

end


function S = readKeyValueSummary(path)
txt = fileread(path);
lines = regexp(txt, '\r?\n', 'split');

S = struct();

for k = 1:numel(lines)
    line = strtrim(lines{k});

    if isempty(line) || startsWith(line, '#')
        continue;
    end

    tok = regexp(line, '^([^=]+)=(.*)$', 'tokens', 'once');
    if isempty(tok)
        continue;
    end

    key = matlab.lang.makeValidName(strtrim(tok{1}));
    value = strtrim(tok{2});

    S.(key) = value;
end
end


function x = getNumber(S, key)
f = matlab.lang.makeValidName(key);
assert(isfield(S, f), 'Missing key %s', key);

x = str2double(S.(f));
assert(isfinite(x), 'Invalid numeric value for %s: %s', key, S.(f));
end


function s = getString(S, key)
f = matlab.lang.makeValidName(key);
assert(isfield(S, f), 'Missing key %s', key);

s = string(S.(f));
end