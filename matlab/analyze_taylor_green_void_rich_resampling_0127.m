function out = analyze_taylor_green_void_rich_resampling_0127(runRoot, varargin)
%ANALYZE_TAYLOR_GREEN_VOID_RICH_RESAMPLING_0127 Post-process the 0127 run.
%
% This wrapper keeps the existing Taylor--Green analysis path and adds a
% compact trigger table for the void/rich resampling case.  It assumes that
% the OpenMP runs have already been launched by
% scripts/run_taylor_green_void_rich_resampling_validation_0127.sh.

if nargin < 1 || isempty(runRoot)
    % Default assumes MATLAB is launched from the repository matlab/ directory.
    runRoot = fullfile('..','runs','taylor_green_void_rich_resampling_0127');
end
runRoot = char(strrep(string(runRoot), '\', filesep));

p = inputParser;
p.FunctionName = 'analyze_taylor_green_void_rich_resampling_0127';
addParameter(p, 'makePlots', true, @(x) islogical(x) && isscalar(x));
parse(p, varargin{:});
opt = p.Results;

if exist('analyze_taylor_green_resampling_0126', 'file') == 2
    analyze_taylor_green_resampling_0126(runRoot, 'makePlots', opt.makePlots);
else
    warning('analyze_taylor_green_void_rich_resampling_0127:missing0126Analyzer', ...
        'analyze_taylor_green_resampling_0126.m not found on MATLAB path; only trigger summary will be written.');
end

analysisDir = fullfile(runRoot, 'analysis');
if ~isfolder(analysisDir)
    mkdir(analysisDir);
end

cases = {'classic','q6','q6_resampling'};
rows = cell(0, 1);
for k = 1:numel(cases)
    label = cases{k};
    summaryPath = fullfile(runRoot, label, 'summary_runtime.csv');
    if ~isfile(summaryPath)
        fprintf('[0127] skipping missing summary: %s\n', summaryPath);
        continue;
    end
    T = readtable(summaryPath);
    if isempty(T)
        continue;
    end
    first = T(1,:);
    last = T(end,:);
    row = struct();
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
    rows{end+1,1} = row; %#ok<AGROW>
end

if isempty(rows)
    out = table();
else
    out = struct2table(vertcat(rows{:}));
end

outCsv = fullfile(analysisDir, 'tg_void_rich_trigger_summary_0127.csv');
writetable(out, outCsv);
fprintf('[0127] wrote trigger summary: %s\n', outCsv);
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
