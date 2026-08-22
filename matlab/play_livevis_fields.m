function out = play_livevis_fields(recordingDir, varargin)
%PLAY_LIVEVIS_FIELDS Replay SRC/MPCD filtered livevis recordings and make movies.
%
%   out = play_livevis_fields(recordingDir)
%   out = play_livevis_fields(recordingDir, 'field', 'mass')
%
% The input may be either:
%   - one recording session directory containing manifest.kv and .f32 files, or
%   - its parent recordings/ directory. If several sessions are found, the
%     most recently modified session is selected and reported.
%
% Recorded field convention:
%   step_<step>_field_<field>.f32
%   raw float32, x varying fastest. A frame is reshaped to [Ny,Nx].
%
% Common examples
% ---------------
% Replay only:
%   play_livevis_fields(recDir, ...
%       'field','mass', 'colormap','thermal', 'gain',1);
%
% Stable colour scale:
%   play_livevis_fields(recDir, ...
%       'field','mass', 'clim',[0 150], 'colormap','thermal');
%
% MOV movie (requires ffmpeg):
%   play_livevis_fields(recDir, ...
%       'field','mass', ...
%       'videoFile','splash_mass.mov', ...
%       'frameRate',30, ...
%       'clim',[0 150], ...
%       'colormap','thermal');
%
% MPG movie (requires ffmpeg):
%   play_livevis_fields(recDir, ...
%       'field','ux', ...
%       'videoFile','ux.mpg', ...
%       'frameRate',25, ...
%       'centerZero','yes', ...
%       'colormap','blue_red');
%
% Useful options
% --------------
%   'field'          : field name or 'auto' [default: auto]
%   'Nx','Ny'        : override recorded live grid size
%   'Lx','Ly'        : physical display extent
%   'dt'             : time step override
%   'startStep'      : first solver step to include [-Inf]
%   'endStep'        : last solver step to include [Inf]
%   'frameStride'    : keep every Nth recorded frame [1]
%   'pauseTime'      : replay pause per frame in seconds [0.02]
%
% Display:
%   'gain'           : multiplicative display gain [1]
%   'clip'           : livevis-like saturation value; <=0 disables [NaN]
%   'clim'           : explicit [min max], applied after gain [empty]
%   'scaleMode'      : 'global' | 'frame' | 'symmetric' [global]
%   'centerZero'     : 'auto' | 'yes' | 'no' [auto]
%   'colormap'       : 'thermal' | 'blue_red' | 'gray' | MATLAB cmap [thermal]
%   'showColorbar'   : true/false [true]
%   'showAxes'       : true/false [false]
%   'figurePosition' : [left bottom width height]
%   'titlePrefix'    : title prefix
%
% Movie:
%   'videoFile'      : '', .avi, .mov, .mpg/.mpeg, or .mp4
%   'frameRate'      : movie FPS [30]
%   'videoQuality'   : MJPEG staging quality 0..100 [95]
%   'ffmpegPath'     : ffmpeg executable [ffmpeg]
%
% Notes
% -----
% * .mov/.mpg/.mp4 are encoded through ffmpeg from a temporary MJPEG AVI,
%   because MATLAB VideoWriter support for these containers varies by OS.
% * The recorded .f32 field is already the recorder output. This function
%   does not add spatial/temporal filtering.
% * A fixed 'clim' is recommended when comparing several movies.
%
% 2026-08-19

    p = inputParser;
    p.FunctionName = 'play_livevis_fields';

    addRequired(p, 'recordingDir', @(s) ischar(s) || isstring(s));

    addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Nx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    addParameter(p, 'Ny', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    addParameter(p, 'Lx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'Ly', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'dt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));

    addParameter(p, 'startStep', -Inf, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'endStep', Inf, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'pauseTime', 0.02, @(x) isnumeric(x) && isscalar(x) && x >= 0);

    addParameter(p, 'gain', 1000.0, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'clip', NaN, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'clim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2));
    addParameter(p, 'scaleMode', 'global', @(s) ischar(s) || isstring(s));
    addParameter(p, 'centerZero', 'auto', @(s) ischar(s) || isstring(s));
    addParameter(p, 'colormap', 'thermal', @(s) ischar(s) || isstring(s));
    addParameter(p, 'showColorbar', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'showAxes', false, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'figurePosition', [100 100 1000 700], ...
        @(x) isnumeric(x) && numel(x) == 4);
    addParameter(p, 'titlePrefix', 'SRC/MPCD live recording', ...
        @(s) ischar(s) || isstring(s));

    addParameter(p, 'videoFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameRate', 30, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'videoQuality', 95, ...
        @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);
    addParameter(p, 'ffmpegPath', 'ffmpeg', @(s) ischar(s) || isstring(s));

    parse(p, recordingDir, varargin{:});
    opt = p.Results;

    recordingDir = char(recordingDir);
    [sessionDir, sessionCandidates] = local_resolve_session(recordingDir);

    manifestPath = fullfile(sessionDir, 'manifest.kv');
    manifest = struct();
    if isfile(manifestPath)
        manifest = local_read_kv(manifestPath);
    end

    availableFields = local_available_fields(sessionDir);
    if isempty(availableFields)
        error('play_livevis_fields:noFields', ...
            'No step_*_field_*.f32 files found in %s.', sessionDir);
    end

    requestedField = char(opt.field);
    if strcmpi(requestedField, 'auto')
        requestedField = local_manifest_first_field(manifest);
        if isempty(requestedField) || ~any(strcmp(availableFields, requestedField))
            requestedField = availableFields{1};
        end
    end

    kField = find(strcmpi(availableFields, requestedField), 1, 'first');
    if isempty(kField)
        error('play_livevis_fields:unknownField', ...
            'Field "%s" is unavailable. Available fields: %s', ...
            requestedField, strjoin(availableFields, ', '));
    end
    fieldName = availableFields{kField};

    Nx = local_resolve_number(opt.Nx, manifest, {'liveGridNx','Nx'}, NaN);
    Ny = local_resolve_number(opt.Ny, manifest, {'liveGridNy','Ny'}, NaN);
    if ~isfinite(Nx) || ~isfinite(Ny)
        error('play_livevis_fields:missingGrid', ...
            ['Cannot resolve live grid size. Provide ''Nx'' and ''Ny'' or ' ...
             'use a session with liveGridNx/liveGridNy in manifest.kv.']);
    end
    Nx = round(Nx);
    Ny = round(Ny);

    Lx = local_resolve_number(opt.Lx, manifest, {'Lx'}, Nx);
    Ly = local_resolve_number(opt.Ly, manifest, {'Ly'}, Ny);
    dt = local_resolve_number(opt.dt, manifest, {'dt'}, NaN);

    frameTable = local_list_frames(sessionDir, fieldName, Nx, Ny);
    keep = frameTable.step >= opt.startStep & frameTable.step <= opt.endStep;
    frameTable = frameTable(keep, :);
    if isempty(frameTable)
        error('play_livevis_fields:noFramesInRange', ...
            'No complete "%s" frames remain in the requested step range.', fieldName);
    end

    stride = max(1, round(opt.frameStride));
    frameTable = frameTable(1:stride:height(frameTable), :);

    if isfinite(dt)
        frameTable.time = double(frameTable.step) * dt;
    else
        frameTable.time = nan(height(frameTable),1);
    end

    centerZero = local_resolve_center_zero(char(opt.centerZero), fieldName);
    fixedClim = local_resolve_clim(frameTable, Nx, Ny, opt, centerZero);

    % Figure and first image.
    fig = figure('Name', sprintf('SRC/MPCD live recording: %s', fieldName), ...
                 'Color', 'w', ...
                 'Position', double(opt.figurePosition(:).'));
    ax = axes('Parent', fig);

    F0 = double(local_read_f32(frameTable.fullPath{1}, Nx, Ny));
    Z0 = opt.gain * F0;

    imageHandle = imagesc(ax, [0 Lx], [0 Ly], Z0);
    set(ax, 'YDir', 'normal');
    axis(ax, 'equal');
    axis(ax, 'tight');

    local_apply_colormap(fig, char(opt.colormap), 256);
    local_apply_frame_clim(ax, Z0, fixedClim, opt, centerZero);

    if opt.showAxes
        xlabel(ax, 'x');
        ylabel(ax, 'y');
    else
        axis(ax, 'off');
    end

    if opt.showColorbar
        colorbar(ax);
    end

    titleHandle = title(ax, '', 'Interpreter', 'none');
    local_update_title(titleHandle, char(opt.titlePrefix), fieldName, ...
        frameTable.step(1), frameTable.time(1), opt.gain);
    drawnow;

    % Movie staging.
    videoFile = char(opt.videoFile);
    video = local_open_video(videoFile, opt.frameRate, opt.videoQuality, ...
                             char(opt.ffmpegPath));
    videoCleanup = onCleanup(@() local_video_cleanup(video)); %#ok<NASGU>

    % Replay.
    for k = 1:height(frameTable)
        if ~ishandle(fig)
            warning('play_livevis_fields:figureClosed', ...
                'Figure was closed; replay stopped at frame %d/%d.', k, height(frameTable));
            break;
        end

        if k == 1
            Z = Z0;
        else
            F = double(local_read_f32(frameTable.fullPath{k}, Nx, Ny));
            Z = opt.gain * F;
            set(imageHandle, 'CData', Z);
            local_apply_frame_clim(ax, Z, fixedClim, opt, centerZero);
        end

        local_update_title(titleHandle, char(opt.titlePrefix), fieldName, ...
            frameTable.step(k), frameTable.time(k), opt.gain);

        drawnow;

        if video.enabled
            fr = getframe(fig);
            writeVideo(video.writer, fr);
        end

        if opt.pauseTime > 0
            pause(opt.pauseTime);
        end
    end

    if video.enabled
        close(video.writer);
        video.writerClosed = true;
        video = local_finalize_video(video, char(opt.ffmpegPath));
    end

    out = struct();
    out.sessionDir = sessionDir;
    out.sessionCandidates = sessionCandidates;
    out.manifest = manifest;
    out.availableFields = availableFields;
    out.field = fieldName;
    out.Nx = Nx;
    out.Ny = Ny;
    out.Lx = Lx;
    out.Ly = Ly;
    out.dt = dt;
    out.frameTable = frameTable;
    out.clim = get(ax, 'CLim');
    out.gain = opt.gain;
    out.videoFile = video.finalFile;

    fprintf('[play_livevis_fields] session=%s\n', sessionDir);
    fprintf('[play_livevis_fields] field=%s frames=%d grid=%dx%d\n', ...
        fieldName, height(frameTable), Nx, Ny);
    if ~isempty(video.finalFile)
        fprintf('[play_livevis_fields] movie=%s\n', video.finalFile);
    end
end


% =========================================================================
% Session / manifest
% =========================================================================

function [sessionDir, candidates] = local_resolve_session(pathIn)
    if ~isfolder(pathIn)
        error('play_livevis_fields:notFolder', 'Folder not found: %s', pathIn);
    end

    if isfile(fullfile(pathIn, 'manifest.kv'))
        sessionDir = pathIn;
        candidates = {pathIn};
        return;
    end

    D = dir(fullfile(pathIn, '**', 'manifest.kv'));
    D = D(~[D.isdir]);
    if isempty(D)
        error('play_livevis_fields:noManifest', ...
            ['No manifest.kv found in %s or below it. Pass a recording session ' ...
             'directory, or provide a parent recordings/ directory.'], pathIn);
    end

    candidates = cell(numel(D),1);
    for i = 1:numel(D)
        candidates{i} = D(i).folder;
    end

    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);

    if numel(candidates) == 1
        sessionDir = candidates{1};
        return;
    end

    % Choose the session whose manifest is most recently modified.
    stamp = zeros(numel(candidates),1);
    for i = 1:numel(candidates)
        info = dir(fullfile(candidates{i}, 'manifest.kv'));
        if ~isempty(info)
            stamp(i) = info(1).datenum;
        end
    end
    [~, k] = max(stamp);
    sessionDir = candidates{k};

    warning('play_livevis_fields:multipleSessions', ...
        'Found %d recording sessions below %s; using newest: %s', ...
        numel(candidates), pathIn, sessionDir);
end


function kv = local_read_kv(filename)
    kv = struct();
    fid = fopen(filename, 'r');
    if fid < 0
        error('play_livevis_fields:openManifest', 'Cannot open %s.', filename);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end

        % Strip comments.
        j = find(line == '#', 1, 'first');
        if ~isempty(j)
            line = line(1:j-1);
        end
        line = strtrim(line);
        if isempty(line)
            continue;
        end

        eq = find(line == '=', 1, 'first');
        if isempty(eq)
            continue;
        end

        key = strtrim(line(1:eq-1));
        val = strtrim(line(eq+1:end));
        if isempty(key)
            continue;
        end

        key = matlab.lang.makeValidName(key);
        kv.(key) = val;
    end
end


function value = local_resolve_number(override, kv, keys, fallback)
    if ~isempty(override)
        value = double(override);
        return;
    end

    value = fallback;
    for i = 1:numel(keys)
        key = matlab.lang.makeValidName(keys{i});
        if isfield(kv, key)
            x = str2double(kv.(key));
            if isfinite(x)
                value = x;
                return;
            end
        end
    end
end


function field = local_manifest_first_field(kv)
    field = '';
    key = matlab.lang.makeValidName('recordFields');
    if ~isfield(kv, key)
        return;
    end

    raw = kv.(key);
    parts = regexp(raw, '\s*,\s*', 'split');
    parts = parts(~cellfun(@isempty, parts));
    if ~isempty(parts)
        field = strtrim(parts{1});
    end
end


% =========================================================================
% Frames / field IO
% =========================================================================

function fields = local_available_fields(sessionDir)
    D = dir(fullfile(sessionDir, 'step_*_field_*.f32'));
    fields = {};
    for i = 1:numel(D)
        tok = regexp(D(i).name, '^step_(\d+)_field_(.+)\.f32$', 'tokens', 'once');
        if ~isempty(tok)
            fields{end+1,1} = tok{2}; %#ok<AGROW>
        end
    end
    if isempty(fields)
        return;
    end
    fields = unique(fields, 'stable');
end


function T = local_list_frames(sessionDir, fieldName, Nx, Ny)
    D = dir(fullfile(sessionDir, sprintf('step_*_field_%s.f32', fieldName)));
    expectedBytes = Nx * Ny * 4;

    step = zeros(numel(D),1);
    fullPath = cell(numel(D),1);
    bytes = zeros(numel(D),1);
    n = 0;

    for i = 1:numel(D)
        tok = regexp(D(i).name, '^step_(\d+)_field_', 'tokens', 'once');
        if isempty(tok)
            continue;
        end

        if D(i).bytes ~= expectedBytes
            warning('play_livevis_fields:incompleteFrame', ...
                'Skipping %s: %d bytes, expected %d.', ...
                fullfile(D(i).folder,D(i).name), D(i).bytes, expectedBytes);
            continue;
        end

        n = n + 1;
        step(n) = str2double(tok{1});
        fullPath{n} = fullfile(D(i).folder, D(i).name);
        bytes(n) = D(i).bytes;
    end

    step = step(1:n);
    fullPath = fullPath(1:n);
    bytes = bytes(1:n);

    [step, order] = sort(step);
    fullPath = fullPath(order);
    bytes = bytes(order);

    % If duplicate step files somehow exist, keep the last listed copy.
    [~, ia] = unique(step, 'last');
    ia = sort(ia);
    step = step(ia);
    fullPath = fullPath(ia);
    bytes = bytes(ia);

    time = nan(numel(step),1);
    T = table(step, time, bytes, fullPath);
end


function F = local_read_f32(path, Nx, Ny)
    fid = fopen(path, 'rb');
    if fid < 0
        error('play_livevis_fields:openField', 'Cannot open %s.', path);
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

    v = fread(fid, Nx*Ny, 'single=>single');
    if numel(v) ~= Nx*Ny
        error('play_livevis_fields:shortField', ...
            'Unexpected field size in %s: got %d float32, expected %d.', ...
            path, numel(v), Nx*Ny);
    end

    % Recorder convention: x varies fastest.
    F = reshape(v, [Nx Ny]).';
end


% =========================================================================
% Colour scaling / plotting
% =========================================================================

function centerZero = local_resolve_center_zero(mode, fieldName)
    mode = lower(strtrim(mode));
    switch mode
        case {'yes','true','1','on'}
            centerZero = true;
        case {'no','false','0','off'}
            centerZero = false;
        case 'auto'
            f = lower(fieldName);
            signedNames = {'ux','uy','vx','vy','vorticity','omega','curl', ...
                           'kappa','curvature','darcy_power','brinkman_power'};
            centerZero = any(strcmp(f, signedNames)) || ...
                         contains(f,'kappa') || contains(f,'curvature');
        otherwise
            error('play_livevis_fields:centerZero', ...
                'centerZero must be auto, yes, or no.');
    end
end


function fixedClim = local_resolve_clim(frameTable, Nx, Ny, opt, centerZero)
    if ~isempty(opt.clim)
        fixedClim = double(opt.clim(:).');
        if ~(isfinite(fixedClim(1)) && isfinite(fixedClim(2)) && fixedClim(2) > fixedClim(1))
            error('play_livevis_fields:badClim', 'clim must satisfy finite max > min.');
        end
        return;
    end

    if isfinite(opt.clip) && opt.clip > 0
        if centerZero
            fixedClim = [-opt.clip, opt.clip];
        else
            fixedClim = [0, opt.clip];
        end
        return;
    end

    mode = lower(strtrim(char(opt.scaleMode)));
    if strcmp(mode, 'frame')
        fixedClim = [];
        return;
    end

    if ~any(strcmp(mode, {'global','symmetric'}))
        error('play_livevis_fields:scaleMode', ...
            'scaleMode must be global, frame, or symmetric.');
    end

    vmin = Inf;
    vmax = -Inf;
    maxabs = 0;

    fprintf('[play_livevis_fields] scanning %d frame(s) for stable colour scale...\n', ...
        height(frameTable));

    for k = 1:height(frameTable)
        F = double(local_read_f32(frameTable.fullPath{k}, Nx, Ny));
        Z = opt.gain * F;
        finite = Z(isfinite(Z));
        if isempty(finite)
            continue;
        end
        vmin = min(vmin, min(finite));
        vmax = max(vmax, max(finite));
        maxabs = max(maxabs, max(abs(finite)));
    end

    if ~isfinite(vmin) || ~isfinite(vmax)
        fixedClim = [-1 1];
        return;
    end

    if strcmp(mode, 'symmetric') || centerZero
        a = max(maxabs, eps);
        fixedClim = [-a a];
    else
        if vmax <= vmin
            pad = max(abs(vmin)*1e-6, 1e-12);
            fixedClim = [vmin-pad, vmax+pad];
        else
            fixedClim = [vmin vmax];
        end
    end
end


function local_apply_frame_clim(ax, Z, fixedClim, opt, centerZero)
    if ~isempty(fixedClim)
        caxis(ax, fixedClim);
        return;
    end

    finite = Z(isfinite(Z));
    if isempty(finite)
        caxis(ax, [-1 1]);
        return;
    end

    if centerZero
        a = max(abs(finite));
        if ~(isfinite(a) && a > 0)
            a = 1;
        end
        caxis(ax, [-a a]);
    else
        lo = min(finite);
        hi = max(finite);
        if ~(isfinite(lo) && isfinite(hi))
            lo = -1; hi = 1;
        elseif hi <= lo
            pad = max(abs(lo)*1e-6, 1e-12);
            lo = lo-pad;
            hi = hi+pad;
        end
        caxis(ax, [lo hi]);
    end

    %#ok<NASGU>
    opt = opt; % keep signature explicit for future livevis scale extensions
end


function local_apply_colormap(fig, name, n)
    name0 = lower(strtrim(name));
    switch name0
        case {'gray','grey','grayscale','greyscale'}
            cmap = gray(n);

        case {'blue_red','bluered','blue-red'}
            % Diverging blue -> white -> red.
            x = [0 0.5 1];
            c = [0.00 0.15 0.95; ...
                 1.00 1.00 1.00; ...
                 0.95 0.05 0.00];
            xi = linspace(0,1,n).';
            cmap = [interp1(x,c(:,1),xi,'linear'), ...
                    interp1(x,c(:,2),xi,'linear'), ...
                    interp1(x,c(:,3),xi,'linear')];

        case {'thermal','heat','hot'}
            % Close visual analogue of the live renderer's low-blue/high-hot map.
            if exist('turbo','file') || exist('turbo','builtin')
                cmap = turbo(n);
            else
                cmap = jet(n);
            end

        otherwise
            try
                fun = str2func(name);
                cmap = fun(n);
            catch
                error('play_livevis_fields:colormap', ...
                    'Unknown colormap "%s".', name);
            end
    end
    colormap(fig, cmap);
end


function local_update_title(h, prefix, fieldName, step, time, gain)
    if isfinite(time)
        s = sprintf('%s | %s | step %d | t = %.6g | gain = %.4g', ...
            prefix, fieldName, step, time, gain);
    else
        s = sprintf('%s | %s | step %d | gain = %.4g', ...
            prefix, fieldName, step, gain);
    end
    set(h, 'String', s);
end


% =========================================================================
% Movie
% =========================================================================

function video = local_open_video(videoFile, frameRate, quality, ffmpegPath)
    video = struct();
    video.enabled = false;
    video.writer = [];
    video.writerClosed = false;
    video.requestedFile = '';
    video.stagingFile = '';
    video.finalFile = '';
    video.needsFfmpeg = false;
    video.ext = '';

    if isempty(strtrim(videoFile))
        return;
    end

    [folder, base, ext] = fileparts(videoFile);
    if isempty(ext)
        ext = '.mov';
        videoFile = [videoFile ext];
    end
    ext = lower(ext);

    if isempty(folder)
        folder = pwd;
        videoFile = fullfile(folder, [base ext]);
    else
        if ~isfolder(folder)
            mkdir(folder);
        end
        videoFile = fullfile(folder, [base ext]);
    end

    supported = {'.avi','.mov','.mpg','.mpeg','.mp4'};
    if ~any(strcmp(ext, supported))
        error('play_livevis_fields:videoExtension', ...
            'Supported video extensions: .avi, .mov, .mpg, .mpeg, .mp4');
    end

    video.enabled = true;
    video.requestedFile = videoFile;
    video.ext = ext;

    if strcmp(ext, '.avi')
        staging = videoFile;
        needsFfmpeg = false;
    else
        % Probe ffmpeg before spending time rendering the movie.
        local_require_ffmpeg(ffmpegPath);
        staging = fullfile(folder, [base '__livevis_tmp_mjpeg.avi']);
        needsFfmpeg = true;
        if isfile(staging)
            delete(staging);
        end
    end

    writer = VideoWriter(staging, 'Motion JPEG AVI');
    writer.FrameRate = frameRate;
    writer.Quality = quality;
    open(writer);

    video.writer = writer;
    video.stagingFile = staging;
    video.needsFfmpeg = needsFfmpeg;
end


function video = local_finalize_video(video, ffmpegPath)
    if ~video.enabled
        return;
    end

    if ~video.needsFfmpeg
        video.finalFile = video.stagingFile;
        return;
    end

    inq = local_shell_quote(video.stagingFile);
    outq = local_shell_quote(video.requestedFile);
    ffq = local_shell_quote(ffmpegPath);

    switch video.ext
        case {'.mov','.mp4'}
            cmd = sprintf(['%s -y -loglevel warning -i %s -an ' ...
                '-c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p ' ...
                '-movflags +faststart %s'], ffq, inq, outq);

        case {'.mpg','.mpeg'}
            cmd = sprintf(['%s -y -loglevel warning -i %s -an ' ...
                '-c:v mpeg2video -q:v 2 -pix_fmt yuv420p %s'], ...
                ffq, inq, outq);

        otherwise
            error('play_livevis_fields:internalVideo', ...
                'Unexpected ffmpeg extension: %s', video.ext);
    end

    fprintf('[play_livevis_fields] encoding %s ...\n', video.ext);
    [status, msg] = system(cmd);
    if status ~= 0
        error('play_livevis_fields:ffmpeg', ...
            ['ffmpeg conversion failed (status %d).\n%s\n' ...
             'The staging AVI was kept at:\n%s'], ...
            status, msg, video.stagingFile);
    end

    if isfile(video.stagingFile)
        delete(video.stagingFile);
    end
    video.finalFile = video.requestedFile;
end


function local_require_ffmpeg(ffmpegPath)
    ffq = local_shell_quote(ffmpegPath);
    [status, ~] = system(sprintf('%s -version', ffq));
    if status ~= 0
        error('play_livevis_fields:noFfmpeg', ...
            ['ffmpeg is required for .mov/.mpg/.mp4 output but was not found. ' ...
             'Install ffmpeg or pass ''ffmpegPath'', or write an .avi directly.']);
    end
end


function q = local_shell_quote(s)
    s = char(s);
    % Double quotes work for the usual Windows cmd and POSIX shell paths.
    s = strrep(s, '"', '\"');
    q = ['"' s '"'];
end


function local_video_cleanup(video)
    % Best-effort cleanup if an exception occurs while the writer is open.
    if ~isstruct(video) || ~isfield(video,'enabled') || ~video.enabled
        return;
    end

    try
        if ~video.writerClosed && ~isempty(video.writer)
            close(video.writer);
        end
    catch
    end
end
