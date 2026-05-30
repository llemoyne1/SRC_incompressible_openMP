function out = analyze_taylor_green_random_population_resampling_0128(runRoot, varargin)
%ANALYZE_TAYLOR_GREEN_RANDOM_POPULATION_RESAMPLING_0128 Post-process 0128.
%
% Usage from the repository matlab/ directory:
%   analyze_taylor_green_random_population_resampling_0128('../runs/taylor_green_random_population_resampling_0128');

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','taylor_green_random_population_resampling_0128');
end
runRoot = char(strrep(string(runRoot), '\', filesep));

p = inputParser;
p.FunctionName = 'analyze_taylor_green_random_population_resampling_0128';
addParameter(p, 'initRoot', fullfile('..','init','taylor_green_random_population_resampling_0128'), @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;
initRoot = char(strrep(string(opt.initRoot), '\', filesep));

if exist('analyze_taylor_green_resampling_0126', 'file') == 2
    analyze_taylor_green_resampling_0126(runRoot, 'makePlots', opt.makePlots);
else
    warning('analyze_taylor_green_random_population_resampling_0128:missing0126Analyzer', ...
        'analyze_taylor_green_resampling_0126.m not found on MATLAB path; only random-population trigger summary will be written.');
end

analysisDir = fullfile(runRoot, 'analysis');
if ~isfolder(analysisDir)
    mkdir(analysisDir);
end

layoutPath = fullfile(initRoot, 'initial_random_population_layout_0128.csv');
initial = struct();
initial.layoutAvailable = isfile(layoutPath);
if initial.layoutAvailable
    L = readtable(layoutPath);
    initial.initialCells = height(L);
    initial.initialMeanN = mean(L.nFluid, 'omitnan');
    initial.initialStdN = std(double(L.nFluid), 1, 'omitnan');
    initial.initialMinN = min(L.nFluid);
    initial.initialMaxN = max(L.nFluid);
    initial.initialPoorCells = sum(logical(L.isPoor));
    initial.initialRichCells = sum(logical(L.isRich));
    initial.initialEmptyCells = sum(logical(L.isEmpty));
else
    warning('analyze_taylor_green_random_population_resampling_0128:missingLayout', ...
        'Initial layout CSV not found: %s', layoutPath);
    initial.initialCells = NaN;
    initial.initialMeanN = NaN;
    initial.initialStdN = NaN;
    initial.initialMinN = NaN;
    initial.initialMaxN = NaN;
    initial.initialPoorCells = NaN;
    initial.initialRichCells = NaN;
    initial.initialEmptyCells = NaN;
end

cases = {'classic','q6','q6_resampling'};
rows = cell(0, 1);
for k = 1:numel(cases)
    label = cases{k};
    summaryPath = fullfile(runRoot, label, 'summary_runtime.csv');
    if ~isfile(summaryPath)
        fprintf('[0128] skipping missing summary: %s\n', summaryPath);
        continue;
    end
    T = readtable(summaryPath);
    if isempty(T)
        continue;
    end
    first = T(1,:);
    last = T(end,:);
    row = initial;
    row.case = string(label);
    row.nRows = height(T);
    row.firstStep = getnum(first, 'step');
    row.lastStep = getnum(last, 'step');
    row.firstMRelRms = getnum(first, 'resampMRelRms');
    row.lastMRelRms = getnum(last, 'resampMRelRms');
    row.maxMRelRms = maxcol(T, 'resampMRelRms');
    row.firstStdN = getnum(first, 'stdN');
    row.lastStdN = getnum(last, 'stdN');
    row.minFluidParticles = mincol(T, 'nFluidParticles');
    row.maxInactiveParticles = maxcol(T, 'nInactiveParticles');
    row.totalExtractionOps = sumcol(T, 'resampExtractionApplyOpsApplied');
    if isnan(row.totalExtractionOps)
        row.totalExtractionOps = sumcol(T, 'resampExtractionOps');
    end
    row.totalInsertionOps = sumcol(T, 'resampInsertionApplyOpsApplied');
    if isnan(row.totalInsertionOps)
        row.totalInsertionOps = sumcol(T, 'resampInsertionOps');
    end
    row.totalRemapCells = sumcol(T, 'resampRemapCells');
    row.totalThermalCells = sumcol(T, 'resampThermalCells');
    row.totalMassGuardParticles = sumcol(T, 'resampMassGuardParticles');
    row.finalResampPoolFreeSlots = getnum(last, 'resampPoolFreeSlots');
    rows{end+1,1} = row; %#ok<AGROW>
end

if isempty(rows)
    out = table();
else
    out = struct2table(vertcat(rows{:}));
end

outCsv = fullfile(analysisDir, 'tg_random_population_trigger_summary_0128.csv');
writetable(out, outCsv);
fprintf('[0128] wrote random-population trigger summary: %s\n', outCsv);
if ~isempty(out)
    disp(out);
end
end

function x = getnum(Trow, name)
if ismember(name, Trow.Properties.VariableNames)
    x = Trow.(name)(1);
else
    x = NaN;
end
end

function x = sumcol(T, name)
if ismember(name, T.Properties.VariableNames)
    x = sum(T.(name), 'omitnan');
else
    x = NaN;
end
end

function x = maxcol(T, name)
if ismember(name, T.Properties.VariableNames)
    x = max(T.(name), [], 'omitnan');
else
    x = NaN;
end
end

function x = mincol(T, name)
if ismember(name, T.Properties.VariableNames)
    x = min(T.(name), [], 'omitnan');
else
    x = NaN;
end
end
