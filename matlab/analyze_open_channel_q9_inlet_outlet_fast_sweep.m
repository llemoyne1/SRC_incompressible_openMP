function S = analyze_open_channel_q9_inlet_outlet_fast_sweep(varargin)
%ANALYZE_OPEN_CHANNEL_Q9_INLET_OUTLET_FAST_SWEEP Summarize 0063b fast sweep.
%
% Usage from repository root:
%   cd matlab
%   S = analyze_open_channel_q9_inlet_outlet_fast_sweep('root','..');
%   cd ..
%
% The function scans runs/open_channel_q9_inlet_outlet_fast_sweep/* and writes
% summary_fast_sweep.csv in the sweep root.

opts = parse_options(varargin{:});
repoRoot = char(opts.root);
sweepRoot = fullfile(repoRoot, 'runs', 'open_channel_q9_inlet_outlet_fast_sweep');

if ~isfolder(sweepRoot)
    error('Sweep directory not found: %s', sweepRoot);
end

D = dir(sweepRoot);
rows = struct([]);

for k = 1:numel(D)
    if ~D(k).isdir || startsWith(D(k).name, '.') || strcmp(D(k).name, 'params') || strcmp(D(k).name, 'logs')
        continue;
    end

    caseDir = fullfile(sweepRoot, D(k).name);
    csvFile = fullfile(caseDir, 'summary_runtime.csv');
    if ~isfile(csvFile)
        warning('Skipping %s: missing summary_runtime.csv', D(k).name);
        continue;
    end

    T = readtable(csvFile);
    if isempty(T)
        warning('Skipping %s: empty summary_runtime.csv', D(k).name);
        continue;
    end

    i1 = 1;
    ie = height(T);
    r = struct();
    r.caseLabel = string(D(k).name);
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
    r.q9OpenEnabledFinal = getv(T, 'q9OpenBoundaryEnabled', ie, NaN);
    r.q9OpenMassFluxXLowFinal = getv(T, 'q9OpenBoundaryMassFluxXLow', ie, NaN);
    r.q9OpenMassFluxXHighFinal = getv(T, 'q9OpenBoundaryMassFluxXHigh', ie, NaN);
    r.q9OpenMassFluxBalanceFinal = getv(T, 'q9OpenBoundaryMassFluxBalance', ie, NaN);

    rows = [rows; r]; %#ok<AGROW>
end

if isempty(rows)
    error('No completed cases found under %s', sweepRoot);
end

S = struct2table(rows);
S = sortrows(S, 'caseLabel');

outCsv = fullfile(sweepRoot, 'summary_fast_sweep.csv');
writetable(S, outCsv);

disp(S);
fprintf('Wrote %s\n', outCsv);

try
    figure('Name','0063b stdN final');
    bar(categorical(S.caseLabel), S.stdNFinal);
    ylabel('final std(N)');
    grid on;
    title('0063b open-channel population fluctuations');

    figure('Name','0063b q9 density ratio');
    q9Mask = ~isnan(S.q9DensityStdRatioEstimateFinal) & S.q9AppliedFinal > 0;
    bar(categorical(S.caseLabel(q9Mask)), S.q9DensityStdRatioEstimateFinal(q9Mask));
    ylabel('q9 density std ratio estimate');
    grid on;
    title('0063b Q9 density relaxation estimate');
catch ME
    warning('Plotting failed: %s', ME.message);
end
end

function opts = parse_options(varargin)
opts.root = '..';
if mod(numel(varargin), 2) ~= 0
    error('Options must be provided as name/value pairs.');
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    value = varargin{i+1};
    switch lower(name)
        case 'root'
            opts.root = value;
        otherwise
            error('Unknown option: %s', name);
    end
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
