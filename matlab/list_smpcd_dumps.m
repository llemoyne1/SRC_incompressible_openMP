function frameTable = list_smpcd_dumps(runDir, varargin)
%LIST_SMPCD_DUMPS List .smpcd dumps from a run directory.
%
% frameTable = list_smpcd_dumps(runDir)
%
% The returned table contains file, fullPath, step and, when available, time
% interpolated from summary_runtime.csv.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'pattern', 'state_step_*.smpcd', @(s) ischar(s) || isstring(s));
    addParameter(p, 'summaryFile', '', @(s) ischar(s) || isstring(s));
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    pattern = char(p.Results.pattern);
    if ~isfolder(runDir)
        error('list_smpcd_dumps:runDirNotFound', 'Cannot find run directory: %s', runDir);
    end

    files = dir(fullfile(runDir, pattern));
    if isempty(files)
        frameTable = table(string.empty(0,1), string.empty(0,1), zeros(0,1), nan(0,1), ...
            'VariableNames', {'file','fullPath','step','time'});
        return;
    end

    names = string({files.name}).';
    paths = fullfile(string({files.folder}).', names);
    steps = nan(numel(files), 1);
    for k = 1:numel(files)
        token = regexp(files(k).name, 'state_step_(\d+)\.smpcd$', 'tokens', 'once');
        if ~isempty(token)
            steps(k) = str2double(token{1});
        end
    end

    [steps, order] = sort(steps);
    names = names(order);
    paths = paths(order);

    times = nan(size(steps));
    summaryFile = char(p.Results.summaryFile);
    if isempty(summaryFile)
        summaryFile = fullfile(runDir, 'summary_runtime.csv');
    end
    if isfile(summaryFile)
        summary = readtable(summaryFile);
        timeName = '';
        if ismember('time', summary.Properties.VariableNames)
            timeName = 'time';
        elseif ismember('t', summary.Properties.VariableNames)
            timeName = 't';
        end
        if ismember('step', summary.Properties.VariableNames) && ~isempty(timeName)
            for k = 1:numel(steps)
                idx = find(summary.step == steps(k), 1, 'first');
                if ~isempty(idx)
                    times(k) = summary.(timeName)(idx);
                end
            end
        end
    end

    frameTable = table(names, paths, steps, times, ...
        'VariableNames', {'file','fullPath','step','time'});
end
