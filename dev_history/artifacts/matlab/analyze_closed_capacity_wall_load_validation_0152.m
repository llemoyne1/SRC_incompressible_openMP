function Tsum = analyze_closed_capacity_wall_load_validation_0152(runRoot, varargin)
%ANALYZE_CLOSED_CAPACITY_WALL_LOAD_VALIDATION_0152 Summarize static wall-load tests.
%
% The validation target is a uniformly overfilled closed box with no inlet.
% A mechanically consistent wall-load diagnostic should show:
%   1) increasing virial/total wall pressure with overfill;
%   2) similar pressure on left/right/bottom/top walls;
%   3) small net wall force compared with the scalar compressive load.
%
% Usage from repository_root/matlab:
%   T = analyze_closed_capacity_wall_load_validation_0152( ...
%       '../runs/closed_capacity_wall_load_validation_0152');

    if nargin < 1 || isempty(runRoot)
        runRoot = '../runs/closed_capacity_wall_load_validation_0152';
    end

    p = inputParser;
    p.FunctionName = 'analyze_closed_capacity_wall_load_validation_0152';
    addParameter(p, 'showFigures', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'saveFigures', true, @(x) islogical(x) || isnumeric(x));
    addParameter(p, 'analysisDirName', 'matlab_closed_capacity_wall_load_0152', @(s) ischar(s) || isstring(s));
    parse(p, varargin{:});
    opt = p.Results;
    opt.showFigures = logical(opt.showFigures);
    opt.saveFigures = logical(opt.saveFigures);

    runRoot = char(runRoot);
    files = local_find_summary_files(runRoot);
    if isempty(files)
        error('analyze_closed_capacity_wall_load_validation_0152:noFiles', ...
            'No summary_runtime.csv files found under %s', runRoot);
    end

    outDir = fullfile(runRoot, char(opt.analysisDirName));
    if ~exist(outDir, 'dir')
        mkdir(outDir);
    end

    rows = cell(numel(files), 1);
    for k = 1:numel(files)
        csv = files{k};
        T = readtable(csv);
        if isempty(T)
            continue;
        end
        lastIdx = height(T);
        [caseDir, ~, ~] = fileparts(csv);
        [~, caseLabel] = fileparts(caseDir);
        rows{k} = local_summary_row(T, lastIdx, caseLabel, csv);
    end
    rows = rows(~cellfun('isempty', rows));
    Tsum = vertcat(rows{:});

    if ismember('overfillFinal', Tsum.Properties.VariableNames)
        [~, ord] = sort(Tsum.overfillFinal);
        Tsum = Tsum(ord, :);
    end

    outCsv = fullfile(outDir, 'closed_capacity_wall_load_0152_summary.csv');
    writetable(Tsum, outCsv);
    save(fullfile(outDir, 'closed_capacity_wall_load_0152_analysis.mat'), 'Tsum', 'files');

    local_plot_summary(Tsum, outDir, opt);
    local_plot_time_series(files, outDir, opt);

    fprintf('[0152 analysis] wrote summary: %s\n', outCsv);
end

% -------------------------------------------------------------------------
function row = local_summary_row(T, idx, caseLabel, csv)
    totalP = local_get(T, 'capacityWallPressureTotalMeanAll', idx);
    virP   = local_get(T, 'capacityWallPressureVirialMeanAll', idx);
    kinP   = local_get(T, 'capacityWallPressureKineticMeanAll', idx);

    pFaces = [ ...
        local_get(T, 'capacityWallPressureTotalMeanLeft', idx), ...
        local_get(T, 'capacityWallPressureTotalMeanRight', idx), ...
        local_get(T, 'capacityWallPressureTotalMeanBottom', idx), ...
        local_get(T, 'capacityWallPressureTotalMeanTop', idx)];
    pFacesVir = [ ...
        local_get(T, 'capacityWallPressureVirialMeanLeft', idx), ...
        local_get(T, 'capacityWallPressureVirialMeanRight', idx), ...
        local_get(T, 'capacityWallPressureVirialMeanBottom', idx), ...
        local_get(T, 'capacityWallPressureVirialMeanTop', idx)];

    Fx = local_get(T, 'capacityWallForceTotalX', idx);
    Fy = local_get(T, 'capacityWallForceTotalY', idx);
    Fmag = hypot(Fx, Fy);
    Lsolid = local_get(T, 'capacityWallSolidLengthTotal', idx);
    if isnan(Lsolid) || Lsolid <= 0
        Lsolid = 4.0;
    end
    scalarLoad = abs(totalP) * Lsolid;
    forceImbalance = Fmag / max(scalarLoad, eps);

    faceMean = mean(pFaces(~isnan(pFaces)));
    faceStd = std(pFaces(~isnan(pFaces)));
    faceCv = faceStd / max(abs(faceMean), eps);
    faceRangeRel = (max(pFaces) - min(pFaces)) / max(abs(faceMean), eps);

    M = local_get(T, 'totalMass', idx);
    Mref = local_get(T, 'capacityReferenceMass', idx);
    overfill = local_get(T, 'capacityOverfillRatio', idx);
    if isnan(overfill) && ~isnan(M) && ~isnan(Mref) && Mref > 0
        overfill = max(0, (M - Mref) / Mref);
    end

    Keff = local_get(T, 'capacityVirialKEffective', idx);
    expectedVirP = NaN;
    if ~isnan(Keff) && ~isnan(overfill)
        expectedVirP = Keff * overfill;
    end

    row = table();
    row.caseLabel = string(caseLabel);
    row.csvPath = string(csv);
    row.tFinal = local_get(T, 'time', idx);
    row.stepFinal = local_get(T, 'step', idx);
    row.totalMassFinal = M;
    row.referenceMass = Mref;
    row.overfillFinal = overfill;
    row.KvirEffFinal = Keff;
    row.expectedVirialPressureUniform = expectedVirP;
    row.wallPressureKineticMeanAll = kinP;
    row.wallPressureVirialMeanAll = virP;
    row.wallPressureTotalMeanAll = totalP;
    row.wallPressureTotalLeft = pFaces(1);
    row.wallPressureTotalRight = pFaces(2);
    row.wallPressureTotalBottom = pFaces(3);
    row.wallPressureTotalTop = pFaces(4);
    row.wallPressureVirialLeft = pFacesVir(1);
    row.wallPressureVirialRight = pFacesVir(2);
    row.wallPressureVirialBottom = pFacesVir(3);
    row.wallPressureVirialTop = pFacesVir(4);
    row.wallPressureFaceCv = faceCv;
    row.wallPressureFaceRangeRelative = faceRangeRel;
    row.wallForceX = Fx;
    row.wallForceY = Fy;
    row.wallForceMag = Fmag;
    row.wallScalarCompressiveLoad = scalarLoad;
    row.wallForceImbalanceRatio = forceImbalance;
    row.q6StrengthEffFinal = local_get(T, 'q6ProjectionStrength', idx);
    row.capacityQ6FactorFinal = local_get(T, 'capacityQ6ProjectionFactor', idx);
    row.resampTargetMassFinal = local_get(T, 'resampRemapTargetCellMass', idx);
end

% -------------------------------------------------------------------------
function local_plot_summary(Tsum, outDir, opt)
    vis = local_visible(opt.showFigures);
    x = 100 * Tsum.overfillFinal;

    fig = figure('Name', '0152 closed-capacity wall-load validation summary', 'Visible', vis);
    tiledlayout(fig, 2, 2, 'Padding','compact', 'TileSpacing','compact');

    nexttile;
    plot(x, Tsum.wallPressureKineticMeanAll, '-o', 'LineWidth', 1.2); hold on;
    plot(x, Tsum.wallPressureVirialMeanAll, '-o', 'LineWidth', 1.2);
    plot(x, Tsum.wallPressureTotalMeanAll, '-o', 'LineWidth', 1.2);
    if ismember('expectedVirialPressureUniform', Tsum.Properties.VariableNames)
        plot(x, Tsum.expectedVirialPressureUniform, '--', 'LineWidth', 1.0);
        legend({'kinetic','virial','total','Keff * overfill'}, 'Location','best');
    else
        legend({'kinetic','virial','total'}, 'Location','best');
    end
    grid on; xlabel('overfill [%]'); ylabel('mean wall pressure');
    title('mean wall pressure');

    nexttile;
    plot(x, Tsum.wallPressureTotalLeft, '-o', 'LineWidth', 1.2); hold on;
    plot(x, Tsum.wallPressureTotalRight, '-o', 'LineWidth', 1.2);
    plot(x, Tsum.wallPressureTotalBottom, '-o', 'LineWidth', 1.2);
    plot(x, Tsum.wallPressureTotalTop, '-o', 'LineWidth', 1.2);
    grid on; xlabel('overfill [%]'); ylabel('total pressure by face');
    legend({'left','right','bottom','top'}, 'Location','best');
    title('face uniformity target');

    nexttile;
    semilogy(x, max(Tsum.wallForceImbalanceRatio, realmin), '-o', 'LineWidth', 1.2); hold on;
    semilogy(x, max(Tsum.wallPressureFaceCv, realmin), '-o', 'LineWidth', 1.2);
    semilogy(x, max(Tsum.wallPressureFaceRangeRelative, realmin), '-o', 'LineWidth', 1.2);
    grid on; xlabel('overfill [%]'); ylabel('relative defect');
    legend({'|F|/(p L_solid)','face CV','face range/mean'}, 'Location','best');
    title('force-balance and face-uniformity defects');

    nexttile;
    plot(x, Tsum.wallForceX, '-o', 'LineWidth', 1.2); hold on;
    plot(x, Tsum.wallForceY, '-o', 'LineWidth', 1.2);
    plot(x, Tsum.wallForceMag, '-o', 'LineWidth', 1.2);
    grid on; xlabel('overfill [%]'); ylabel('wall force');
    legend({'Fx','Fy','|F|'}, 'Location','best');
    title('net wall force');

    local_save_fig(fig, fullfile(outDir, 'closed_capacity_wall_load_0152_summary'), opt);
end

% -------------------------------------------------------------------------
function local_plot_time_series(files, outDir, opt)
    vis = local_visible(opt.showFigures);
    fig = figure('Name', '0152 closed-capacity wall-load time traces', 'Visible', vis);
    tiledlayout(fig, 2, 2, 'Padding','compact', 'TileSpacing','compact');

    ax1 = nexttile; hold(ax1, 'on'); grid(ax1, 'on'); title(ax1, 'mean total wall pressure'); xlabel(ax1, 'time'); ylabel(ax1, 'p');
    ax2 = nexttile; hold(ax2, 'on'); grid(ax2, 'on'); title(ax2, 'net force ratio'); xlabel(ax2, 'time'); ylabel(ax2, '|F|/(p L)');
    ax3 = nexttile; hold(ax3, 'on'); grid(ax3, 'on'); title(ax3, 'face pressure CV'); xlabel(ax3, 'time'); ylabel(ax3, 'CV');
    ax4 = nexttile; hold(ax4, 'on'); grid(ax4, 'on'); title(ax4, 'overfill'); xlabel(ax4, 'time'); ylabel(ax4, '[%]');

    labels = cell(numel(files), 1);
    for k = 1:numel(files)
        T = readtable(files{k});
        [caseDir, ~, ~] = fileparts(files{k});
        [~, label] = fileparts(caseDir);
        labels{k} = label;
        t = local_col(T, 'time');
        if all(isnan(t)); t = local_col(T, 'step'); end

        p = local_col(T, 'capacityWallPressureTotalMeanAll');
        Fx = local_col(T, 'capacityWallForceTotalX');
        Fy = local_col(T, 'capacityWallForceTotalY');
        L = local_col(T, 'capacityWallSolidLengthTotal');
        L(isnan(L) | L <= 0) = 4.0;
        Fr = hypot(Fx, Fy) ./ max(abs(p).*L, eps);

        pf = [local_col(T, 'capacityWallPressureTotalMeanLeft'), ...
              local_col(T, 'capacityWallPressureTotalMeanRight'), ...
              local_col(T, 'capacityWallPressureTotalMeanBottom'), ...
              local_col(T, 'capacityWallPressureTotalMeanTop')];
        faceCv = nan(size(t));
        for i = 1:numel(t)
            q = pf(i, :);
            q = q(~isnan(q));
            if ~isempty(q)
                faceCv(i) = std(q) / max(abs(mean(q)), eps);
            end
        end
        over = 100 * local_col(T, 'capacityOverfillRatio');

        plot(ax1, t, p, 'LineWidth', 1.0);
        semilogy(ax2, t, max(Fr, realmin), 'LineWidth', 1.0);
        semilogy(ax3, t, max(faceCv, realmin), 'LineWidth', 1.0);
        plot(ax4, t, over, 'LineWidth', 1.0);
    end
    legend(ax1, labels, 'Interpreter','none', 'Location','best');
    legend(ax2, labels, 'Interpreter','none', 'Location','best');
    legend(ax3, labels, 'Interpreter','none', 'Location','best');
    legend(ax4, labels, 'Interpreter','none', 'Location','best');

    local_save_fig(fig, fullfile(outDir, 'closed_capacity_wall_load_0152_time_traces'), opt);
end

% -------------------------------------------------------------------------
function files = local_find_summary_files(rootDir)
    rootDir = char(rootDir);
    if exist('dir', 'builtin') %#ok<EXIST>
        listing = dir(fullfile(rootDir, '**', 'summary_runtime.csv'));
    else
        listing = [];
    end
    files = cell(numel(listing), 1);
    for i = 1:numel(listing)
        files{i} = fullfile(listing(i).folder, listing(i).name);
    end
    if isempty(files)
        files = local_recursive_find(rootDir, 'summary_runtime.csv');
    end
end

% -------------------------------------------------------------------------
function files = local_recursive_find(rootDir, fileName)
    files = {};
    d = dir(rootDir);
    for i = 1:numel(d)
        if d(i).isdir
            name = d(i).name;
            if strcmp(name, '.') || strcmp(name, '..')
                continue;
            end
            files = [files; local_recursive_find(fullfile(rootDir, name), fileName)]; %#ok<AGROW>
        elseif strcmp(d(i).name, fileName)
            files{end+1,1} = fullfile(rootDir, d(i).name); %#ok<AGROW>
        end
    end
end

% -------------------------------------------------------------------------
function v = local_get(T, name, idx)
    if ismember(name, T.Properties.VariableNames)
        v = T.(name)(idx);
    else
        v = NaN;
    end
end

% -------------------------------------------------------------------------
function v = local_col(T, name)
    if ismember(name, T.Properties.VariableNames)
        v = T.(name);
        v = v(:);
    else
        v = NaN(height(T), 1);
    end
end

% -------------------------------------------------------------------------
function local_save_fig(fig, basePath, opts)
    if ~opts.saveFigures
        return;
    end
    try
        savefig(fig, [char(basePath) '.fig']);
    catch
        warning('Could not save FIG: %s.fig', char(basePath));
    end
    try
        exportgraphics(fig, [char(basePath) '.png'], 'Resolution', 180);
    catch
        try
            saveas(fig, [char(basePath) '.png']);
        catch
            warning('Could not save PNG: %s.png', char(basePath));
        end
    end
end

% -------------------------------------------------------------------------
function vis = local_visible(showFigures)
    if showFigures
        vis = 'on';
    else
        vis = 'off';
    end
end
