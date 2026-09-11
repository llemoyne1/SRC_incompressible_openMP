function out = show_livevis_field(fieldFile, varargin)
%SHOW_LIVEVIS_FIELD Display one SRC/MPCD recorded LiveVis .f32 field.
%
%   out = show_livevis_field(fieldFile)
%
%   Displays exactly one file written by the filtered LiveVis recorder:
%
%       step_<step>_field_<field>.f32
%
%   The recording session is inferred from the file directory. Grid size,
%   physical extent and other metadata are then recovered by
%   play_livevis_fields.m from manifest.kv. The field name and solver step
%   are taken directly from the selected filename.
%
%   With no input argument, a file-selection dialog is opened.
%
%   Examples
%   --------
%   show_livevis_field(fullfile( ...
%       'runs','case','output','recordings','record_step_0000000001', ...
%       'step_0000000601_field_uy.f32'));
%
%   show_livevis_field('step_0000000601_field_uy.f32', ...
%       'clim',[-0.5 0.5], ...
%       'colormap','blue_red');
%
%   show_livevis_field('step_0000001101_field_rho2.f32', ...
%       'clim',[0 20], ...
%       'colormap','thermal');
%
%   Real solver-grid overlay
%   ------------------------
%   The grid overlay is drawn in physical coordinates using the ORIGINAL
%   solver grid stored in manifest.kv (Nx, Ny), not the possibly reduced
%   LiveVis recording grid (liveGridNx, liveGridNy).
%
%   Automatic readable overlay (recommended for large grids):
%
%       show_livevis_field(file, 'gridOverlay','yes');
%
%   One line every 8 actual solver cells:
%
%       show_livevis_field(file, ...
%           'gridOverlay','yes', ...
%           'gridStrideCells',8);
%
%   Draw every actual solver-cell boundary (can be visually dense):
%
%       show_livevis_field(file, ...
%           'gridOverlay','yes', ...
%           'gridStrideCells',1);
%
%   Anisotropic stride, e.g. every 8 cells in x and 4 in y:
%
%       show_livevis_field(file, ...
%           'gridOverlay','yes', ...
%           'gridStrideCells',[8 4]);
%
%   Grid-specific options handled by this wrapper:
%
%       'gridOverlay'      : 'yes' | 'no' | logical [default: 'no']
%       'gridStrideCells'  : 'auto' | positive integer | [sx sy]
%                            [default: 'auto']
%                            'auto' chooses an integer power-of-two stride
%                            giving roughly 30--80 grid lines across the
%                            largest dimension. The displayed pitch always
%                            remains an integer multiple of the real cell
%                            size.
%       'gridColor'        : RGB triplet [default: [1 1 1]]
%       'gridLineWidth'    : positive scalar [default: 0.35]
%       'gridLineStyle'    : MATLAB line style [default: '-']
%
%   Any other display option accepted by play_livevis_fields.m is appended,
%   for example:
%
%       'clim', [a b]
%       'gain', 1
%       'colormap', 'thermal' | 'blue_red' | 'gray'
%       'centerZero', 'auto' | 'yes' | 'no'
%       'chiOverlay', 'auto' | 'yes' | 'no'
%       'showColorbar', true | false
%       'showAxes', true | false
%       'figurePosition', [left bottom width height]
%
%   This function intentionally does not re-read or re-filter the particle
%   state. It displays the .f32 field exactly as recorded. Spatial
%   reduction and smoothPasses have therefore already been applied by the
%   recorder. The optional grid overlay is purely graphical.
%
%   Required dependency:
%       play_livevis_fields.m
%
%   SRC/MPCD utility, 2026-09-11.

    if nargin < 1 || isempty(fieldFile)
        [fn, fp] = uigetfile( ...
            {'step_*_field_*.f32', 'SRC/MPCD LiveVis fields (*.f32)'; ...
             '*.f32',              'Float32 fields (*.f32)'; ...
             '*.*',                'All files'}, ...
            'Select one recorded LiveVis field');

        if isequal(fn, 0)
            error('show_livevis_field:noInput', 'No LiveVis field selected.');
        end
        fieldFile = fullfile(fp, fn);
    end

    fieldFile = char(fieldFile);
    if ~isfile(fieldFile)
        error('show_livevis_field:missingFile', ...
            'Cannot find LiveVis field: %s', fieldFile);
    end

    if exist('play_livevis_fields', 'file') ~= 2
        error('show_livevis_field:missingDependency', ...
            ['play_livevis_fields.m is not on the MATLAB path. ' ...
             'Install both utilities in the project matlab/ directory.']);
    end

    % Extract the options that belong only to this single-frame wrapper.
    % Everything else is forwarded unchanged to play_livevis_fields.m.
    [gridOpt, playArgs] = local_extract_grid_options(varargin);

    [sessionDir, base, ext] = fileparts(fieldFile);
    if isempty(sessionDir)
        sessionDir = pwd;
    end
    filename = [base ext];

    tok = regexp(filename, ...
        '^step_(\d+)_field_(.+)\.f32$', 'tokens', 'once');
    if isempty(tok)
        error('show_livevis_field:badFilename', ...
            ['Expected recorder filename step_<step>_field_<field>.f32, ' ...
             'got: %s'], filename);
    end

    step = str2double(tok{1});
    fieldName = tok{2};

    if ~isfinite(step)
        error('show_livevis_field:badStep', ...
            'Cannot parse solver step from filename: %s', filename);
    end

    % Use exactly the same rendering path as movie/replay output, but reduce
    % the selected interval to the one step encoded in the chosen filename.
    out = play_livevis_fields(sessionDir, ...
        'field', fieldName, ...
        'startStep', step, ...
        'endStep', step, ...
        'frameStride', 1, ...
        'pauseTime', 0, ...
        playArgs{:});

    out.fieldFile = fieldFile;
    out.selectedStep = step;

    % Optional overlay of the REAL solver grid. The LiveVis field can have
    % been spatially reduced; in that case out.Nx/out.Ny are the recording
    % grid, while manifest Nx/Ny remain the solver grid.
    out.grid = local_empty_grid_info();
    if gridOpt.enabled
        out.grid = local_draw_solver_grid(out, gridOpt);
    end

    fprintf('[show_livevis_field] file=%s\n', fieldFile);
    fprintf('[show_livevis_field] field=%s step=%d liveGrid=%dx%d\n', ...
        fieldName, round(step), out.Nx, out.Ny);

    if out.grid.enabled
        fprintf(['[show_livevis_field] solverGrid=%dx%d h=(%.9g,%.9g) ' ...
                 'strideCells=(%d,%d) overlayPitch=(%.9g,%.9g)\n'], ...
            out.grid.solverNx, out.grid.solverNy, ...
            out.grid.hx, out.grid.hy, ...
            out.grid.strideX, out.grid.strideY, ...
            out.grid.pitchX, out.grid.pitchY);
    else
        fprintf('[show_livevis_field] grid overlay=off\n');
    end
end


% =========================================================================
% Grid-overlay option parsing
% =========================================================================

function [opt, passArgs] = local_extract_grid_options(args)
    opt = struct();
    opt.enabled = false;
    opt.strideCells = 'auto';
    opt.color = [1 1 1];
    opt.lineWidth = 0.35;
    opt.lineStyle = '-';

    if mod(numel(args), 2) ~= 0
        error('show_livevis_field:badOptions', ...
            'Optional arguments must be supplied as name/value pairs.');
    end

    passArgs = {};

    for k = 1:2:numel(args)
        name = args{k};
        value = args{k+1};

        if ~(ischar(name) || (isstring(name) && isscalar(name)))
            error('show_livevis_field:badOptionName', ...
                'Option names must be character vectors or scalar strings.');
        end

        key = lower(strtrim(char(name)));
        switch key
            case 'gridoverlay'
                opt.enabled = local_parse_yes_no(value, 'gridOverlay');

            case 'gridstridecells'
                opt.strideCells = local_validate_stride(value);

            case 'gridcolor'
                if ~(isnumeric(value) && numel(value) == 3 && ...
                     all(isfinite(value(:))) && ...
                     all(value(:) >= 0) && all(value(:) <= 1))
                    error('show_livevis_field:badGridColor', ...
                        'gridColor must be an RGB triplet with values in [0,1].');
                end
                opt.color = double(value(:).');

            case 'gridlinewidth'
                if ~(isnumeric(value) && isscalar(value) && ...
                     isfinite(value) && value > 0)
                    error('show_livevis_field:badGridLineWidth', ...
                        'gridLineWidth must be a positive finite scalar.');
                end
                opt.lineWidth = double(value);

            case 'gridlinestyle'
                if ~(ischar(value) || (isstring(value) && isscalar(value)))
                    error('show_livevis_field:badGridLineStyle', ...
                        'gridLineStyle must be a MATLAB line-style string.');
                end
                style = char(value);
                validStyles = {'-','--',':','-.','none'};
                if ~any(strcmp(style, validStyles))
                    error('show_livevis_field:badGridLineStyle', ...
                        'Unsupported gridLineStyle: %s', style);
                end
                opt.lineStyle = style;

            otherwise
                passArgs(end+1:end+2) = args(k:k+1); %#ok<AGROW>
        end
    end
end


function yes = local_parse_yes_no(value, optionName)
    if islogical(value) && isscalar(value)
        yes = value;
        return;
    end

    if isnumeric(value) && isscalar(value) && isfinite(value) && ...
            (value == 0 || value == 1)
        yes = logical(value);
        return;
    end

    if ischar(value) || (isstring(value) && isscalar(value))
        s = lower(strtrim(char(value)));
        if any(strcmp(s, {'yes','on','true','1'}))
            yes = true;
            return;
        elseif any(strcmp(s, {'no','off','false','0'}))
            yes = false;
            return;
        end
    end

    error('show_livevis_field:badYesNo', ...
        '%s must be yes/no, on/off, true/false or a logical scalar.', optionName);
end


function stride = local_validate_stride(value)
    if ischar(value) || (isstring(value) && isscalar(value))
        s = lower(strtrim(char(value)));
        if strcmp(s, 'auto')
            stride = 'auto';
            return;
        end
        error('show_livevis_field:badGridStride', ...
            'gridStrideCells string value must be ''auto''.');
    end

    if ~(isnumeric(value) && (isscalar(value) || numel(value) == 2) && ...
         all(isfinite(value(:))) && all(value(:) >= 1) && ...
         all(abs(value(:) - round(value(:))) < 1e-12))
        error('show_livevis_field:badGridStride', ...
            ['gridStrideCells must be ''auto'', a positive integer, ' ...
             'or [strideX strideY].']);
    end

    stride = round(double(value(:).'));
    if isscalar(stride)
        stride = [stride stride];
    end
end


% =========================================================================
% Solver-grid recovery and drawing
% =========================================================================

function info = local_draw_solver_grid(out, opt)
    info = local_empty_grid_info();

    if ~isfield(out, 'Lx') || ~isfield(out, 'Ly') || ...
       ~isfinite(out.Lx) || ~isfinite(out.Ly) || out.Lx <= 0 || out.Ly <= 0
        error('show_livevis_field:missingExtent', ...
            'Cannot draw solver grid because Lx/Ly are unavailable.');
    end

    [solverNx, solverNy, source] = local_resolve_solver_grid(out);

    hx = double(out.Lx) / double(solverNx);
    hy = double(out.Ly) / double(solverNy);

    if ischar(opt.strideCells)
        stride = local_auto_stride(solverNx, solverNy);
        strideX = stride;
        strideY = stride;
    else
        strideX = opt.strideCells(1);
        strideY = opt.strideCells(2);
    end

    % Keep the requested strides meaningful even for small grids.
    strideX = max(1, min(solverNx, round(strideX)));
    strideY = max(1, min(solverNy, round(strideY)));

    xIndex = 0:strideX:solverNx;
    yIndex = 0:strideY:solverNy;
    if xIndex(end) ~= solverNx
        xIndex(end+1) = solverNx;
    end
    if yIndex(end) ~= solverNy
        yIndex(end+1) = solverNy;
    end

    xGrid = double(xIndex) * hx;
    yGrid = double(yIndex) * hy;

    ax = local_find_field_axes(out);
    wasHeld = ishold(ax);
    hold(ax, 'on');

    % Use one line object for all vertical lines and one for all horizontal
    % lines. NaN separators avoid creating thousands of graphics objects when
    % gridStrideCells=1 on a large solver grid.
    xv = reshape([xGrid; xGrid; nan(size(xGrid))], 1, []);
    yv = reshape([zeros(size(xGrid)); ...
                  double(out.Ly) * ones(size(xGrid)); ...
                  nan(size(xGrid))], 1, []);

    xh = reshape([zeros(size(yGrid)); ...
                  double(out.Lx) * ones(size(yGrid)); ...
                  nan(size(yGrid))], 1, []);
    yh = reshape([yGrid; yGrid; nan(size(yGrid))], 1, []);

    hVertical = line(ax, xv, yv, ...
        'Color', opt.color, ...
        'LineWidth', opt.lineWidth, ...
        'LineStyle', opt.lineStyle, ...
        'HitTest', 'off', ...
        'Tag', 'SRC_solver_grid_vertical');

    hHorizontal = line(ax, xh, yh, ...
        'Color', opt.color, ...
        'LineWidth', opt.lineWidth, ...
        'LineStyle', opt.lineStyle, ...
        'HitTest', 'off', ...
        'Tag', 'SRC_solver_grid_horizontal');

    if ~wasHeld
        hold(ax, 'off');
    end

    drawnow;

    info.enabled = true;
    info.solverNx = solverNx;
    info.solverNy = solverNy;
    info.source = source;
    info.hx = hx;
    info.hy = hy;
    info.strideX = strideX;
    info.strideY = strideY;
    info.pitchX = strideX * hx;
    info.pitchY = strideY * hy;
    info.xPositions = xGrid;
    info.yPositions = yGrid;
    info.verticalHandle = hVertical;
    info.horizontalHandle = hHorizontal;
end


function [solverNx, solverNy, source] = local_resolve_solver_grid(out)
    solverNx = NaN;
    solverNy = NaN;
    source = 'live-grid-fallback';

    if isfield(out, 'manifest') && isstruct(out.manifest)
        solverNx = local_manifest_number(out.manifest, ...
            {'Nx','solverNx','gridNx'}, NaN);
        solverNy = local_manifest_number(out.manifest, ...
            {'Ny','solverNy','gridNy'}, NaN);

        if isfinite(solverNx) && isfinite(solverNy)
            source = 'manifest-solver-grid';
        else
            % Fallback for manifests that only retain a spatial reduction
            % factor together with liveGridNx/liveGridNy.
            reduce = local_manifest_number(out.manifest, ...
                {'spatialReduce','recordSpatialReduce','liveSpatialReduce'}, NaN);
            if isfinite(reduce) && reduce >= 1 && ...
               isfield(out, 'Nx') && isfield(out, 'Ny')
                solverNx = double(out.Nx) * reduce;
                solverNy = double(out.Ny) * reduce;
                source = 'live-grid-times-spatial-reduce';
            end
        end
    end

    if ~isfinite(solverNx) || solverNx < 1
        solverNx = double(out.Nx);
        source = 'live-grid-fallback';
    end
    if ~isfinite(solverNy) || solverNy < 1
        solverNy = double(out.Ny);
        source = 'live-grid-fallback';
    end

    solverNx = round(solverNx);
    solverNy = round(solverNy);
end


function value = local_manifest_number(kv, keys, fallback)
    value = fallback;
    for i = 1:numel(keys)
        key = matlab.lang.makeValidName(keys{i});
        if isfield(kv, key)
            raw = kv.(key);
            if isnumeric(raw) && isscalar(raw)
                x = double(raw);
            else
                x = str2double(raw);
            end
            if isfinite(x)
                value = x;
                return;
            end
        end
    end
end


function stride = local_auto_stride(Nx, Ny)
    % Aim for O(50) grid intervals across the largest dimension while making
    % the stride a power of two. This is convenient for CFD/MPCD grids and,
    % crucially, remains an exact integer multiple of the true solver cell.
    maxN = max(double(Nx), double(Ny));
    targetIntervals = 60;
    raw = max(1, maxN / targetIntervals);
    stride = 2 ^ round(log2(raw));
    stride = max(1, round(stride));
end


function ax = local_find_field_axes(out)
    % play_livevis_fields leaves its new figure current. Locate the parent
    % axes of the scalar field image rather than relying on gca (which can be
    % the colorbar). Restricting the search to gcf also avoids accidentally
    % overlaying an older LiveVis figure with the same grid dimensions.
    fig = gcf;
    images = findobj(fig, 'Type', 'image');
    ax = [];

    for iImg = 1:numel(images)
        c = get(images(iImg), 'CData');
        if isnumeric(c) && ismatrix(c) && ...
           size(c,1) == out.Ny && size(c,2) == out.Nx
            ax = ancestor(images(iImg), 'axes');
            break;
        end
    end

    if isempty(ax) || ~ishandle(ax)
        error('show_livevis_field:cannotFindAxes', ...
            'Cannot locate the LiveVis image axes for grid overlay.');
    end
end


function info = local_empty_grid_info()
    info = struct();
    info.enabled = false;
    info.solverNx = NaN;
    info.solverNy = NaN;
    info.source = '';
    info.hx = NaN;
    info.hy = NaN;
    info.strideX = NaN;
    info.strideY = NaN;
    info.pitchX = NaN;
    info.pitchY = NaN;
    info.xPositions = [];
    info.yPositions = [];
    info.verticalHandle = [];
    info.horizontalHandle = [];
end
