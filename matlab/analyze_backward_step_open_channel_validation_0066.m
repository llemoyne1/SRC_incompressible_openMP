function suite = analyze_backward_step_open_channel_validation_0066(varargin)
%ANALYZE_BACKWARD_STEP_OPEN_CHANNEL_VALIDATION_0066 Analyze 0066 inlet/outlet step runs.
%
% Example from repository root:
%   ./scripts/run_backward_step_open_channel_validation_0066.sh
%   cd matlab
%   suite = analyze_backward_step_open_channel_validation_0066('root','..');
%   cd ..

p = inputParser;
addParameter(p, 'root', '..', @(s) ischar(s) || isstring(s));
addParameter(p, 'runRoot', 'runs/backward_step_open_channel_validation_0066', @(s) ischar(s) || isstring(s));
addParameter(p, 'labels', {}, @(x) iscell(x) || isstring(x));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'field', 'omega', @(s) ischar(s) || isstring(s));
addParameter(p, 'averageLastFraction', 0.50, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1);
parse(p, varargin{:});
opt = p.Results;

root = char(opt.root);
runRoot = char(opt.runRoot);
if ~startsWith(runRoot, filesep) && ~(numel(runRoot) >= 2 && runRoot(2) == ':')
    runRootAbs = fullfile(root, runRoot);
else
    runRootAbs = runRoot;
end

caseNames = { ...
    'backstep_classic_keepmean', ...
    'backstep_q6_keepmean_s050', ...
    'backstep_q9_keepmean_b0001', ...
    'backstep_q9_virial_keepmean_K0p50_b0p05_ex3', ...
    'backstep_q9_virial_nokeep_K0p50_b0p05_ex3'};
defaultLabels = { ...
    'classic keepMean', ...
    'Q6 keepMean', ...
    'Q9 keepMean', ...
    'Q9+virial keepMean', ...
    'Q9+virial no keepMean'};

runDirs = {};
labels = {};
for i = 1:numel(caseNames)
    rd = fullfile(runRootAbs, caseNames{i});
    if exist(rd, 'dir')
        runDirs{end+1} = rd; %#ok<AGROW>
        labels{end+1} = defaultLabels{i}; %#ok<AGROW>
    end
end

if isempty(runDirs)
    error('analyze_backward_step_open_channel_validation_0066:noRuns', ...
        'No 0066 run directories found in %s', runRootAbs);
end

if ~isempty(opt.labels)
    labels = cellstr(string(opt.labels));
    if numel(labels) ~= numel(runDirs)
        error('analyze_backward_step_open_channel_validation_0066:labels', ...
            'labels must have one entry per detected run directory.');
    end
end

outputDir = fullfile(root, 'runs/backward_step_open_channel_validation_0066_analysis');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

suite = validate_backward_step_masked_structure_suite( ...
    'runDirs', runDirs, ...
    'labels', labels, ...
    'makePlots', logical(opt.makePlots), ...
    'field', char(opt.field), ...
    'averageLastFraction', opt.averageLastFraction, ...
    'outputDir', outputDir);

summaryPath = fullfile(outputDir, 'backward_step_open_channel_validation_0066_summary.csv');
profilesPath = fullfile(outputDir, 'backward_step_open_channel_validation_0066_lower_profiles.csv');
writetable(suite.summary, summaryPath);
writetable(suite.lowerLayerProfiles, profilesPath);

fprintf('[0066 analysis] wrote %s\n', summaryPath);
fprintf('[0066 analysis] wrote %s\n', profilesPath);
end
