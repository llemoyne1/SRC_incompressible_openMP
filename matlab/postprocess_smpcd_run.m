function out = postprocess_smpcd_run(runDir, varargin)
%POSTPROCESS_SMPCD_RUN Read, bin, tabulate and visualize SRC/MPCD dumps.
%
% out = postprocess_smpcd_run('runs/periodic_base', 'field', 'rho')
%
% This high-level helper keeps diagnostics outside the C++ core. It reads the
% runtime summary, lists .smpcd dumps, optionally displays them sequentially,
% and can convert selected binned frames to MATLAB tables.

    p = inputParser;
    addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'paramsFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameStride', 1, @isnumeric);
    addParameter(p, 'maxFramesToTable', Inf, @isnumeric);
    addParameter(p, 'saveFieldTables', false, @islogical);
    addParameter(p, 'fieldTableFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'makeSummaryPlots', true, @islogical);
    addParameter(p, 'playFrames', true, @islogical);
    addParameter(p, 'pauseTime', 0.05, @isnumeric);
    addParameter(p, 'particleDecimation', 20, @isnumeric);
    addParameter(p, 'showParticles', false, @islogical);
    addParameter(p, 'showVelocityVectors', false, @islogical);
    addParameter(p, 'velocityDecimation', 2, @isnumeric);
    addParameter(p, 'clim', [], @isnumeric);
    parse(p, runDir, varargin{:});

    runDir = char(p.Results.runDir);
    if ~isfolder(runDir)
        error('postprocess_smpcd_run:runDirNotFound', 'Cannot find run directory: %s', runDir);
    end

    paramsFile = char(p.Results.paramsFile);
    if isempty(paramsFile)
        candidate = fullfile(runDir, 'params_used.kv');
        if isfile(candidate)
            paramsFile = candidate;
        end
    end
    if isempty(paramsFile) || ~isfile(paramsFile)
        error('postprocess_smpcd_run:missingParams', 'Cannot find params_used.kv. Pass paramsFile explicitly.');
    end

    params = parse_smpcd_kv(paramsFile);
    grid = local_grid_from_params(params);

    summaryFile = fullfile(runDir, 'summary_runtime.csv');
    if isfile(summaryFile)
        summaryTable = readtable(summaryFile);
    else
        warning('postprocess_smpcd_run:noSummary', 'No summary_runtime.csv found in %s.', runDir);
        summaryTable = table();
    end

    frameTable = list_smpcd_dumps(runDir, 'summaryFile', summaryFile);
    if isempty(frameTable)
        error('postprocess_smpcd_run:noFrames', 'No .smpcd dumps found in %s.', runDir);
    end

    if p.Results.makeSummaryPlots && ~isempty(summaryTable)
        plot_smpcd_summary(runDir, 'summaryFile', summaryFile, 'makePlots', true);
    end

    frameStride = max(1, round(p.Results.frameStride));
    selected = 1:frameStride:height(frameTable);

    fieldTables = {};
    lastFields = [];
    if p.Results.playFrames
        playOut = play_smpcd_dumps(runDir, ...
            'paramsFile', paramsFile, ...
            'field', p.Results.field, ...
            'frameStride', frameStride, ...
            'pauseTime', p.Results.pauseTime, ...
            'particleDecimation', p.Results.particleDecimation, ...
            'showParticles', p.Results.showParticles, ...
            'showVelocityVectors', p.Results.showVelocityVectors, ...
            'velocityDecimation', p.Results.velocityDecimation, ...
            'clim', p.Results.clim);
        lastFields = playOut.lastFields;
    end

    if p.Results.saveFieldTables || isfinite(p.Results.maxFramesToTable)
        maxFrames = min(numel(selected), p.Results.maxFramesToTable);
        selectedForTable = selected(1:maxFrames);
        fieldTables = cell(numel(selectedForTable), 1);
        for kk = 1:numel(selectedForTable)
            idx = selectedForTable(kk);
            state = read_smpcd_state(char(frameTable.fullPath(idx)));
            fields = bin_smpcd_state(state, 'Lx', grid.Lx, 'Ly', grid.Ly, 'Nx', grid.Nx, 'Ny', grid.Ny);
            fieldTables{kk} = smpcd_fields_to_table(fields, 'step', frameTable.step(idx), 'time', frameTable.time(idx));
            lastFields = fields;
        end

        if p.Results.saveFieldTables
            if isempty(p.Results.fieldTableFile)
                fieldTableFile = fullfile(runDir, 'binned_fields_table.mat');
            else
                fieldTableFile = char(p.Results.fieldTableFile);
            end
            combinedFieldTable = vertcat(fieldTables{:}); %#ok<NASGU>
            save(fieldTableFile, 'combinedFieldTable', 'frameTable', 'summaryTable', 'params', '-v7.3');
            fprintf('Saved binned field table: %s\n', fieldTableFile);
        end
    end

    out = struct();
    out.runDir = runDir;
    out.paramsFile = paramsFile;
    out.params = params;
    out.grid = grid;
    out.summaryTable = summaryTable;
    out.frameTable = frameTable;
    out.fieldTables = fieldTables;
    out.lastFields = lastFields;
end

function grid = local_grid_from_params(params)
    required = {'Lx','Ly','Nx','Ny'};
    for k = 1:numel(required)
        if ~isfield(params, required{k})
            error('postprocess_smpcd_run:missingGridParam', 'Missing parameter %s in params file.', required{k});
        end
    end
    grid = struct();
    grid.Lx = double(params.Lx);
    grid.Ly = double(params.Ly);
    grid.Nx = double(params.Nx);
    grid.Ny = double(params.Ny);
end
