function out = play_livevis_profiles(recordingDir, varargin)
%PLAY_LIVEVIS_PROFILES Replay 1-D profiles from SRC/MPCD LiveVis recordings.
%
%   out = play_livevis_profiles(recordingDir, ...)
%
% Extracts a line profile from each recorded LiveVis field and animates its
% evolution in time. The spatial coordinates and recording grid are read
% from manifest.kv, using the same conventions as play_livevis_fields.m.
%
% The profile direction means:
%   'direction','x' : plot F(x,y0) at the requested y position.
%   'direction','y' : plot F(x0,y) at the requested x position.
%
% Examples
% --------
% Axial jet profile uy(y) on the nozzle centreline x=Lx/2:
%   play_livevis_profiles(recordingDir, ...
%       'field','uy', 'direction','y', 'position',0.78125);
%
% Horizontal rho2 profile at y=0.85:
%   play_livevis_profiles(recordingDir, ...
%       'field','rho2', 'direction','x', 'position',0.85);
%
% Restrict replay and fix vertical limits:
%   play_livevis_profiles(recordingDir, ...
%       'field','uy', 'direction','y', 'position',0.78125, ...
%       'startStep',1000, 'endStep',10000, 'frameStride',2, ...
%       'ylim',[-6 1]);
%
% Save an AVI:
%   play_livevis_profiles(recordingDir, ...
%       'field','uy', 'direction','y', 'position',0.78125, ...
%       'videoFile','uy_axis_profile.avi', 'frameRate',30);
%
% Parameters
% ----------
%   'field'          : recorded field name [default 'rho']
%   'Nx','Ny'        : override live recording grid dimensions
%   'Lx','Ly'        : override physical domain dimensions
%   'dt'             : override solver time step
%   'direction'      : 'x' or 'y' [default 'y']
%   'position'       : transverse physical coordinate. Required.
%                      For direction='x', this is y0.
%                      For direction='y', this is x0.
%   'sampling'       : 'linear' or 'nearest' [default 'linear']
%   'startStep'      : first solver step [-Inf]
%   'endStep'        : last solver step [Inf]
%   'frameStride'    : use one frame every N available frames [1]
%   'pauseTime'      : pause between displayed frames, seconds [0.2]
%   'gain'           : multiply field values by this factor [1]
%   'ylim'           : fixed profile-value limits, [] = automatic/global
%   'xlim'           : fixed spatial-coordinate limits, [] = full profile
%   'lineWidth'      : line width [1.5]
%   'showGrid'       : show axes grid [true]
%   'figurePosition' : figure rectangle [100 100 1000 650]
%   'titlePrefix'    : title prefix ['SRC/MPCD live profile']
%   'videoFile'      : optional .avi or .mp4 output ['']
%   'frameRate'      : movie frame rate [30]
%   'videoQuality'   : VideoWriter quality, 0..100 [95]
%   'interfaceMode'  : 'none', 'current' or 'initial' [default 'none']
%                      current: reconstruct y_interface(step) from rho1 with
%                      the same alpha=0.5 crossing used by the historical Sato analyser.
%                      initial: draw constant 'interfaceInitialY'.
%   'interfaceField' : liquid field used for reconstruction [default 'rho1']
%   'interfaceInitialY': initial/reference interface y for mode='initial' []
%   'interfaceThreshold': alpha threshold [default 0.5]
%   'interfaceSmoothPasses': historical cross-smoothing passes [default 1]
%   'interfaceSmoothLambda': cross-smoother lambda [default 0.125]
%   'interfaceRefMass': nominal liquid mass per recording cell. [] = auto
%                      from run params species0 + solver/live cell areas.
%   'nozzleExit'     : numeric y, []/'none', or 'auto' [default 'auto'].
%                      auto searches the run environment for NOZZLE_EXIT_Y.
%
% Output fields include sessionDir, field, direction, positionRequested,
% positionUsed, coordinate, steps, time, profiles and frameTable.
%
% Notes
% -----
% * Physical cell-centre coordinates are used:
%       x_i=(i-1/2)Lx/Nx, y_j=(j-1/2)Ly/Ny.
% * With sampling='linear', the requested transverse coordinate is linearly
%   interpolated between the two neighbouring recorded rows/columns.
% * The recorded .f32 field is used exactly as stored; recorder smoothing or
%   spatial reduction has already been applied.
%
% SRC/MPCD utility, 2026-09-25.

    p = inputParser;
    p.FunctionName = 'play_livevis_profiles';

    addRequired(p, 'recordingDir', @(s) ischar(s) || isstring(s));
    addParameter(p, 'field', 'rho', @(s) ischar(s) || isstring(s));
    addParameter(p, 'Nx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    addParameter(p, 'Ny', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    addParameter(p, 'Lx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'Ly', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    addParameter(p, 'dt', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));

    addParameter(p, 'direction', 'y', @(s) ischar(s) || isstring(s));
    addParameter(p, 'position', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'sampling', 'linear', @(s) ischar(s) || isstring(s));

    addParameter(p, 'startStep', -Inf, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'endStep', Inf, @(x) isnumeric(x) && isscalar(x));
    addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    addParameter(p, 'pauseTime', 0.2, @(x) isnumeric(x) && isscalar(x) && x >= 0);

    addParameter(p, 'gain', 1.0, @(x) isnumeric(x) && isscalar(x) && isfinite(x));
    addParameter(p, 'ylim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
    addParameter(p, 'xlim', [], @(x) isempty(x) || (isnumeric(x) && numel(x) == 2 && all(isfinite(x))));
    addParameter(p, 'lineWidth', 1.5, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x > 0);
    addParameter(p, 'showGrid', true, @(x) islogical(x) && isscalar(x));
    addParameter(p, 'figurePosition', [100 100 1000 650], @(x) isnumeric(x) && numel(x) == 4);
    addParameter(p, 'titlePrefix', 'SRC/MPCD live profile', @(s) ischar(s) || isstring(s));

    addParameter(p, 'videoFile', '', @(s) ischar(s) || isstring(s));
    addParameter(p, 'frameRate', 30, @(x) isnumeric(x) && isscalar(x) && x > 0);
    addParameter(p, 'videoQuality', 95, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 100);

    addParameter(p, 'interfaceMode', 'none', @(s) ischar(s) || isstring(s));
    addParameter(p, 'interfaceField', 'rho1', @(s) ischar(s) || isstring(s));
    addParameter(p, 'interfaceInitialY', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)));
    addParameter(p, 'interfaceThreshold', 0.5, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x>0 && x<1);
    addParameter(p, 'interfaceSmoothPasses', 1, @(x) isnumeric(x) && isscalar(x) && x>=0);
    addParameter(p, 'interfaceSmoothLambda', 0.125, @(x) isnumeric(x) && isscalar(x) && isfinite(x) && x>=0);
    addParameter(p, 'interfaceRefMass', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x) && x>0));
    addParameter(p, 'nozzleExit', 'auto', @(x) isempty(x) || (isnumeric(x) && isscalar(x) && isfinite(x)) || ischar(x) || isstring(x));

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
        error('play_livevis_profiles:noFields', ...
            'No step_*_field_*.f32 files found in %s.', sessionDir);
    end

    requestedField = char(opt.field);
    if strcmpi(requestedField, 'auto')
        requestedField = local_manifest_first_field(manifest);
        if isempty(requestedField) || ~any(strcmpi(availableFields, requestedField))
            requestedField = availableFields{1};
        end
    end
    kField = find(strcmpi(availableFields, requestedField), 1, 'first');
    if isempty(kField)
        error('play_livevis_profiles:unknownField', ...
            'Field "%s" is unavailable. Available fields: %s', ...
            requestedField, strjoin(availableFields, ', '));
    end
    fieldName = availableFields{kField};

    Nx = local_resolve_number(opt.Nx, manifest, {'liveGridNx','Nx'}, NaN);
    Ny = local_resolve_number(opt.Ny, manifest, {'liveGridNy','Ny'}, NaN);
    if ~isfinite(Nx) || ~isfinite(Ny)
        error('play_livevis_profiles:missingGrid', ...
            'Cannot resolve live grid size from manifest; provide Nx and Ny.');
    end
    Nx = round(Nx); Ny = round(Ny);
    Lx = local_resolve_number(opt.Lx, manifest, {'Lx'}, Nx);
    Ly = local_resolve_number(opt.Ly, manifest, {'Ly'}, Ny);
    dt = local_resolve_number(opt.dt, manifest, {'dt'}, NaN);

    direction = lower(strtrim(char(opt.direction)));
    if ~any(strcmp(direction, {'x','y'}))
        error('play_livevis_profiles:badDirection', ...
            'direction must be ''x'' or ''y''.');
    end
    if isempty(opt.position)
        error('play_livevis_profiles:missingPosition', ...
            ['position is required. For direction=''x'', position is y0; ' ...
             'for direction=''y'', position is x0.']);
    end
    positionRequested = double(opt.position);

    sampling = lower(strtrim(char(opt.sampling)));
    if ~any(strcmp(sampling, {'nearest','linear'}))
        error('play_livevis_profiles:badSampling', ...
            'sampling must be ''nearest'' or ''linear''.');
    end

    xCenters = ((1:Nx) - 0.5) * (Lx / Nx);
    yCenters = ((1:Ny) - 0.5) * (Ly / Ny);

    if strcmp(direction, 'x')
        if positionRequested < 0 || positionRequested > Ly
            error('play_livevis_profiles:positionOutside', ...
                'Requested y=%.9g is outside [0, %.9g].', positionRequested, Ly);
        end
        coordinate = xCenters(:).';
        transverse = yCenters(:).';
        transverseName = 'y';
    else
        if positionRequested < 0 || positionRequested > Lx
            error('play_livevis_profiles:positionOutside', ...
                'Requested x=%.9g is outside [0, %.9g].', positionRequested, Lx);
        end
        coordinate = yCenters(:).';
        transverse = xCenters(:).';
        transverseName = 'x';
    end

    sampleInfo = local_sampling_info(transverse, positionRequested, sampling);

    frameTable = local_list_frames(sessionDir, fieldName, Nx, Ny);
    keep = frameTable.step >= opt.startStep & frameTable.step <= opt.endStep;
    frameTable = frameTable(keep, :);
    if isempty(frameTable)
        error('play_livevis_profiles:noFramesInRange', ...
            'No complete "%s" frames remain in requested step range.', fieldName);
    end
    stride = max(1, round(opt.frameStride));
    frameTable = frameTable(1:stride:height(frameTable), :);
    if isfinite(dt)
        frameTable.time = double(frameTable.step) * dt;
    else
        frameTable.time = nan(height(frameTable),1);
    end

    nFrames = height(frameTable);
    nCoord = numel(coordinate);
    profiles = nan(nFrames, nCoord);
    for k = 1:nFrames
        F = double(local_read_f32(frameTable.fullPath{k}, Nx, Ny));
        profiles(k,:) = opt.gain * local_extract_profile(F, direction, sampleInfo);
    end

    % Optional interface reconstruction and nozzle-exit marker.  The current
    % interface is meaningful for vertical profiles only: it is the y crossing
    % of the liquid occupancy at the same transverse x used for the profile.
    interfaceMode = lower(strtrim(char(opt.interfaceMode)));
    if ~any(strcmp(interfaceMode, {'none','current','initial'}))
        error('play_livevis_profiles:badInterfaceMode', ...
            'interfaceMode must be ''none'', ''current'' or ''initial''.');
    end
    interfaceY = nan(nFrames,1);
    interfaceMeta = struct('mode',interfaceMode,'field',char(opt.interfaceField), ...
        'threshold',double(opt.interfaceThreshold),'refMass',NaN,'refMassSource','', ...
        'smoothPasses',round(opt.interfaceSmoothPasses),'smoothLambda',double(opt.interfaceSmoothLambda));

    if strcmp(interfaceMode,'current')
        if ~strcmp(direction,'y')
            warning('play_livevis_profiles:interfaceDirection', ...
                'interfaceMode=current is only drawn for direction=''y''; disabling marker.');
            interfaceMode='none';
        else
            interfaceField = char(opt.interfaceField);
            if ~any(strcmpi(availableFields, interfaceField))
                error('play_livevis_profiles:noInterfaceField', ...
                    'Interface field "%s" is unavailable. Available fields: %s', ...
                    interfaceField, strjoin(availableFields, ', '));
            end
            [refMass, refSource] = local_resolve_interface_ref_mass( ...
                opt.interfaceRefMass, sessionDir, manifest, Nx, Ny, Lx, Ly);
            interfaceMeta.refMass = refMass;
            interfaceMeta.refMassSource = refSource;
            for k=1:nFrames
                stepk = frameTable.step(k);
                pRho = fullfile(sessionDir, sprintf('step_%010d_field_%s.f32', round(stepk), interfaceField));
                if ~isfile(pRho)
                    pRho = local_find_step_field(sessionDir, stepk, interfaceField);
                end
                if isempty(pRho) || ~isfile(pRho)
                    warning('play_livevis_profiles:missingInterfaceFrame', ...
                        'Missing %s at step %d; interface marker is NaN.', interfaceField, round(stepk));
                    continue;
                end
                R = double(local_read_f32(pRho, Nx, Ny));
                alpha = min(1,max(0,R/refMass));
                for ip=1:round(opt.interfaceSmoothPasses)
                    alpha = local_smooth_cross(alpha, double(opt.interfaceSmoothLambda));
                end
                aProf = local_extract_profile(alpha, 'y', sampleInfo);
                interfaceY(k) = local_alpha_crossing(yCenters, aProf, double(opt.interfaceThreshold));
            end
        end
    elseif strcmp(interfaceMode,'initial')
        if isempty(opt.interfaceInitialY)
            error('play_livevis_profiles:missingInterfaceInitialY', ...
                'interfaceMode=initial requires interfaceInitialY.');
        end
        interfaceY(:)=double(opt.interfaceInitialY);
    end

    nozzleExitY = local_resolve_nozzle_exit(opt.nozzleExit, sessionDir);

    fixedYLim = double(opt.ylim(:).');
    if isempty(fixedYLim)
        finiteVals = profiles(isfinite(profiles));
        if isempty(finiteVals)
            fixedYLim = [-1 1];
        else
            lo = min(finiteVals); hi = max(finiteVals);
            if hi <= lo
                pad = max(1, abs(lo)) * 0.05;
            else
                pad = 0.04 * (hi - lo);
            end
            fixedYLim = [lo-pad, hi+pad];
        end
    end

    fig = figure('Name', sprintf('SRC/MPCD live profile: %s', fieldName), ...
                 'Color', 'w', 'Position', double(opt.figurePosition(:).'));
    ax = axes('Parent', fig);
    lineHandle = plot(ax, coordinate, profiles(1,:), 'LineWidth', opt.lineWidth);
    if strcmp(direction, 'x')
        xlabel(ax, 'x');
    else
        xlabel(ax, 'y');
    end
    ylabel(ax, sprintf('%s × %.9g', fieldName, opt.gain), 'Interpreter','none');
    ylim(ax, fixedYLim);
    if ~isempty(opt.xlim)
        xlim(ax, double(opt.xlim(:).'));
    else
        xlim(ax, [coordinate(1), coordinate(end)]);
    end
    if opt.showGrid, grid(ax, 'on'); else, grid(ax, 'off'); end
    titleHandle = title(ax, '', 'Interpreter','none');

    interfaceHandle = [];
    nozzleHandle = [];
    if strcmp(direction,'y') && ~strcmp(interfaceMode,'none') && any(isfinite(interfaceY))
        k0=find(isfinite(interfaceY),1,'first');
        interfaceHandle = xline(ax, interfaceY(k0), '--', 'y_{interface}', ...
            'LabelVerticalAlignment','bottom', 'HandleVisibility','off');
        if ~isfinite(interfaceY(1)), interfaceHandle.Visible='off'; end
    end
    if strcmp(direction,'y') && isfinite(nozzleExitY)
        nozzleHandle = xline(ax, nozzleExitY, ':', 'y_{nozzle exit}', ...
            'LabelVerticalAlignment','top', 'HandleVisibility','off');
    end

    local_update_title(titleHandle, char(opt.titlePrefix), fieldName, direction, ...
        transverseName, positionRequested, sampleInfo.positionUsed, ...
        frameTable.step(1), frameTable.time(1), interfaceY(1), nozzleExitY);
    drawnow;

    videoFile = char(opt.videoFile);
    [video, videoFinalFile] = local_open_video(videoFile, opt.frameRate, opt.videoQuality);
    videoCleanup = onCleanup(@() local_close_video_safely(video)); %#ok<NASGU>

    nShown = 0;
    for k = 1:nFrames
        if ~ishandle(fig)
            warning('play_livevis_profiles:figureClosed', ...
                'Figure closed; replay stopped at frame %d/%d.', k, nFrames);
            break;
        end
        set(lineHandle, 'YData', profiles(k,:));
        if ~isempty(interfaceHandle) && isgraphics(interfaceHandle)
            if isfinite(interfaceY(k))
                interfaceHandle.Value = interfaceY(k);
                interfaceHandle.Visible='on';
            else
                interfaceHandle.Visible='off';
            end
        end
        local_update_title(titleHandle, char(opt.titlePrefix), fieldName, direction, ...
            transverseName, positionRequested, sampleInfo.positionUsed, ...
            frameTable.step(k), frameTable.time(k), interfaceY(k), nozzleExitY);
        drawnow;
        nShown = k;
        if ~isempty(video)
            writeVideo(video, getframe(fig));
        end
        if opt.pauseTime > 0
            pause(opt.pauseTime);
        end
    end

    if ~isempty(video)
        close(video);
        video = [];
    end

    out = struct();
    out.sessionDir = sessionDir;
    out.sessionCandidates = sessionCandidates;
    out.manifest = manifest;
    out.availableFields = availableFields;
    out.field = fieldName;
    out.Nx = Nx; out.Ny = Ny; out.Lx = Lx; out.Ly = Ly; out.dt = dt;
    out.direction = direction;
    out.transverseCoordinateName = transverseName;
    out.positionRequested = positionRequested;
    out.positionUsed = sampleInfo.positionUsed;
    out.sampling = sampling;
    out.coordinate = coordinate(:);
    out.steps = frameTable.step;
    out.time = frameTable.time;
    out.profiles = profiles;
    out.frameTable = frameTable;
    out.ylim = fixedYLim;
    out.gain = opt.gain;
    out.videoFile = videoFinalFile;
    out.framesShown = nShown;
    out.interfaceMode = interfaceMode;
    out.interfaceY = interfaceY;
    out.interfaceMeta = interfaceMeta;
    out.nozzleExitY = nozzleExitY;
    if isfinite(nozzleExitY)
        out.nozzleToInterface = nozzleExitY - interfaceY;
    else
        out.nozzleToInterface = nan(size(interfaceY));
    end

    fprintf('[play_livevis_profiles] session=%s\n', sessionDir);
    fprintf('[play_livevis_profiles] field=%s frames=%d liveGrid=%dx%d\n', ...
        fieldName, nFrames, Nx, Ny);
    fprintf('[play_livevis_profiles] profileAlong=%s at %sRequested=%.9g %sUsed=%.9g sampling=%s\n', ...
        direction, transverseName, positionRequested, transverseName, sampleInfo.positionUsed, sampling);
    if strcmp(direction,'y') && ~strcmp(interfaceMode,'none')
        finiteI=interfaceY(isfinite(interfaceY));
        if ~isempty(finiteI)
            fprintf('[play_livevis_profiles] interface mode=%s meanY=%.9g range=[%.9g,%.9g] refMass=%.9g (%s)\n', ...
                interfaceMode, mean(finiteI), min(finiteI), max(finiteI), ...
                interfaceMeta.refMass, interfaceMeta.refMassSource);
        end
    end
    if isfinite(nozzleExitY)
        fprintf('[play_livevis_profiles] nozzleExitY=%.9g\n', nozzleExitY);
    end
    if ~isempty(videoFinalFile)
        fprintf('[play_livevis_profiles] movie=%s\n', videoFinalFile);
    end
end


function info = local_sampling_info(coord, p, mode)
    coord = coord(:).';
    if strcmp(mode, 'nearest') || numel(coord) == 1
        [~, i] = min(abs(coord - p));
        info = struct('i0',i, 'i1',i, 'w',0, 'positionUsed',coord(i));
        return;
    end

    if p <= coord(1)
        i0 = 1; i1 = 1; w = 0;
    elseif p >= coord(end)
        i0 = numel(coord); i1 = i0; w = 0;
    else
        i1 = find(coord >= p, 1, 'first');
        i0 = i1 - 1;
        den = coord(i1) - coord(i0);
        w = (p - coord(i0)) / den;
    end
    positionUsed = (1-w)*coord(i0) + w*coord(i1);
    info = struct('i0',i0, 'i1',i1, 'w',w, 'positionUsed',positionUsed);
end


function profile = local_extract_profile(F, direction, info)
    if strcmp(direction, 'x')
        a = F(info.i0,:);
        b = F(info.i1,:);
    else
        a = F(:,info.i0).';
        b = F(:,info.i1).';
    end
    profile = (1-info.w).*a + info.w.*b;
end


function local_update_title(h, prefix, fieldName, direction, transverseName, pReq, pUsed, step, time, interfaceY, nozzleExitY)
    if isfinite(time)
        timeText = sprintf(' | t = %.6g', time);
    else
        timeText = '';
    end
    if abs(pReq - pUsed) <= 100*eps(max(1,abs(pReq)))
        posText = sprintf('%s = %.6g', transverseName, pReq);
    else
        posText = sprintf('%s = %.6g (used %.6g)', transverseName, pReq, pUsed);
    end
    markerText='';
    if strcmp(direction,'y') && isfinite(interfaceY)
        markerText=[markerText sprintf(' | y_i=%.6g',interfaceY)]; %#ok<AGROW>
    end
    if strcmp(direction,'y') && isfinite(nozzleExitY)
        markerText=[markerText sprintf(' | y_e=%.6g',nozzleExitY)]; %#ok<AGROW>
    end
    set(h, 'String', sprintf('%s | %s | profile along %s at %s | step %d%s%s', ...
        prefix, fieldName, direction, posText, round(step), timeText, markerText));
end



function [refMass, source] = local_resolve_interface_ref_mass(override, sessionDir, manifest, Nx, Ny, Lx, Ly)
    if ~isempty(override)
        refMass=double(override); source='explicit'; return;
    end
    solverNx=local_resolve_number([],manifest,{'solverNx','Nx'},Nx);
    solverNy=local_resolve_number([],manifest,{'solverNy','Ny'},Ny);
    solverCellArea=(Lx/solverNx)*(Ly/solverNy);
    liveCellArea=(Lx/Nx)*(Ly/Ny);

    [paramsPath, params] = local_find_params_kv(sessionDir);
    if isempty(paramsPath) || ~isfield(params, matlab.lang.makeValidName('species0'))
        error('play_livevis_profiles:interfaceRefMassAuto', ...
            ['Cannot auto-resolve nominal liquid mass. No params/*.kv with species0 was found above the recording. ' ...
             'Supply interfaceRefMass explicitly.']);
    end
    spec=params.(matlab.lang.makeValidName('species0'));
    tok=regexp(strtrim(spec),'\s+','split');
    if numel(tok)<6
        error('play_livevis_profiles:badSpecies0','Cannot parse species0 in %s: %s',paramsPath,spec);
    end
    liquidMass=str2double(tok{4});
    gamma=str2double(tok{6});
    if ~(isfinite(liquidMass) && liquidMass>0 && isfinite(gamma) && gamma>0)
        error('play_livevis_profiles:badSpecies0Numbers','Invalid mass/gamma in species0: %s',spec);
    end
    rhoLiquid=gamma*liquidMass/solverCellArea;
    refMass=rhoLiquid*liveCellArea;
    source=sprintf('auto species0: gamma=%.9g mass=%.9g params=%s',gamma,liquidMass,paramsPath);
end

function [paramsPath, kv] = local_find_params_kv(sessionDir)
    paramsPath=''; kv=struct();
    d=sessionDir;
    for level=1:8
        pdir=fullfile(d,'params');
        if isfolder(pdir)
            D=dir(fullfile(pdir,'*.kv'));
            D=D(~[D.isdir]);
            if ~isempty(D)
                [~,k]=max([D.datenum]);
                paramsPath=fullfile(D(k).folder,D(k).name);
                kv=local_read_kv(paramsPath);
                return;
            end
        end
        parent=fileparts(d);
        if isempty(parent) || strcmp(parent,d), break; end
        d=parent;
    end
end

function y = local_alpha_crossing(yCenters, alphaProfile, threshold)
    y=NaN;
    a=double(alphaProfile(:)); yc=double(yCenters(:));
    if numel(a)~=numel(yc), return; end
    % Historical Sato convention: liquid below, gas above; retain the highest
    % descending alpha=threshold crossing if several noisy crossings exist.
    idx=find(a(1:end-1)>=threshold & a(2:end)<threshold);
    if isempty(idx), return; end
    i=idx(end); a0=a(i); a1=a(i+1); y0=yc(i); y1=yc(i+1);
    if isfinite(a0) && isfinite(a1) && abs(a1-a0)>1e-14
        y=y0+(threshold-a0)*(y1-y0)/(a1-a0);
    else
        y=0.5*(y0+y1);
    end
end

function out = local_smooth_cross(A, lambda)
    [ny,nx]=size(A); out=zeros(size(A));
    for iy=1:ny
        for ix=1:nx
            c=A(iy,ix); w=c; e=c; s=c; n=c;
            if ix>1, w=A(iy,ix-1); end
            if ix<nx, e=A(iy,ix+1); end
            if iy>1, s=A(iy-1,ix); end
            if iy<ny, n=A(iy+1,ix); end
            v=c+lambda*((w-c)+(e-c)+(s-c)+(n-c));
            out(iy,ix)=min(1,max(0,v));
        end
    end
end

function p = local_find_step_field(sessionDir, step, fieldName)
    p='';
    D=dir(fullfile(sessionDir, sprintf('step_*_field_%s.f32',fieldName)));
    for i=1:numel(D)
        tok=regexp(D(i).name,'^step_(\d+)_field_','tokens','once');
        if ~isempty(tok) && str2double(tok{1})==round(step)
            p=fullfile(D(i).folder,D(i).name); return;
        end
    end
end

function y = local_resolve_nozzle_exit(value, sessionDir)
    y=NaN;
    if isempty(value), return; end
    if isnumeric(value), y=double(value); return; end
    mode=lower(strtrim(char(value)));
    if isempty(mode) || strcmp(mode,'none'), return; end
    if ~strcmp(mode,'auto')
        error('play_livevis_profiles:badNozzleExit','nozzleExit must be numeric, []/none, or auto.');
    end
    d=sessionDir;
    for level=1:8
        logdir=fullfile(d,'logs');
        if isfolder(logdir)
            D=[dir(fullfile(logdir,'*.env')); dir(fullfile(logdir,'*.txt'))]; %#ok<AGROW>
            for j=1:numel(D)
                f=fullfile(D(j).folder,D(j).name);
                yy=local_find_scalar_key(f,'NOZZLE_EXIT_Y');
                if isfinite(yy), y=yy; return; end
            end
        end
        parent=fileparts(d);
        if isempty(parent) || strcmp(parent,d), break; end
        d=parent;
    end
end

function v = local_find_scalar_key(filename, key)
    v=NaN; fid=fopen(filename,'r'); if fid<0, return; end
    c=onCleanup(@() fclose(fid)); %#ok<NASGU>
    expr=['^\s*' regexptranslate('escape',key) '\s*=\s*([^#\s]+)'];
    while true
        line=fgetl(fid); if ~ischar(line), break; end
        tok=regexp(line,expr,'tokens','once');
        if ~isempty(tok)
            x=str2double(tok{1}); if isfinite(x), v=x; return; end
        end
    end
end

function [video, finalFile] = local_open_video(videoFile, frameRate, quality)
    video = [];
    finalFile = '';
    videoFile = strtrim(videoFile);
    if isempty(videoFile), return; end

    [folder, name, ext] = fileparts(videoFile);
    if isempty(folder), folder = pwd; end
    if ~isfolder(folder), mkdir(folder); end
    if isempty(ext), ext = '.avi'; end
    finalFile = fullfile(folder, [name ext]);

    switch lower(ext)
        case '.avi'
            profile = 'Motion JPEG AVI';
        case '.mp4'
            profile = 'MPEG-4';
        otherwise
            error('play_livevis_profiles:videoExtension', ...
                'videoFile must end in .avi or .mp4.');
    end
    video = VideoWriter(finalFile, profile);
    video.FrameRate = frameRate;
    if isprop(video, 'Quality')
        video.Quality = quality;
    end
    open(video);
end


function local_close_video_safely(video)
    if isempty(video), return; end
    try
        close(video);
    catch
    end
end


function [sessionDir, candidates] = local_resolve_session(pathIn)
    if ~isfolder(pathIn)
        error('play_livevis_profiles:notFolder', 'Folder not found: %s', pathIn);
    end
    if isfile(fullfile(pathIn, 'manifest.kv'))
        sessionDir = pathIn;
        candidates = {pathIn};
        return;
    end
    D = dir(fullfile(pathIn, '**', 'manifest.kv'));
    D = D(~[D.isdir]);
    if isempty(D)
        error('play_livevis_profiles:noManifest', ...
            'No manifest.kv found in %s or below it.', pathIn);
    end
    candidates = cell(numel(D),1);
    for i = 1:numel(D), candidates{i} = D(i).folder; end
    [~, ia] = unique(candidates, 'stable');
    candidates = candidates(ia);
    if numel(candidates) == 1
        sessionDir = candidates{1};
        return;
    end
    stamp = zeros(numel(candidates),1);
    for i = 1:numel(candidates)
        info = dir(fullfile(candidates{i}, 'manifest.kv'));
        if ~isempty(info), stamp(i) = info(1).datenum; end
    end
    [~, k] = max(stamp);
    sessionDir = candidates{k};
    warning('play_livevis_profiles:multipleSessions', ...
        'Found %d sessions below %s; using newest: %s', ...
        numel(candidates), pathIn, sessionDir);
end


function kv = local_read_kv(filename)
    kv = struct();
    fid = fopen(filename, 'r');
    if fid < 0, error('play_livevis_profiles:openManifest','Cannot open %s.',filename); end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    while true
        line = fgetl(fid);
        if ~ischar(line), break; end
        j = find(line == '#', 1, 'first');
        if ~isempty(j), line = line(1:j-1); end
        line = strtrim(line);
        if isempty(line), continue; end
        eq = find(line == '=',1,'first');
        if isempty(eq), continue; end
        key = strtrim(line(1:eq-1)); val = strtrim(line(eq+1:end));
        if isempty(key), continue; end
        kv.(matlab.lang.makeValidName(key)) = val;
    end
end


function value = local_resolve_number(override, kv, keys, fallback)
    if ~isempty(override), value = double(override); return; end
    value = fallback;
    for i = 1:numel(keys)
        key = matlab.lang.makeValidName(keys{i});
        if isfield(kv,key)
            x = str2double(kv.(key));
            if isfinite(x), value = x; return; end
        end
    end
end


function field = local_manifest_first_field(kv)
    field = '';
    key = matlab.lang.makeValidName('recordFields');
    if ~isfield(kv,key), return; end
    parts = regexp(kv.(key), '\s*,\s*', 'split');
    parts = parts(~cellfun(@isempty,parts));
    if ~isempty(parts), field = strtrim(parts{1}); end
end


function fields = local_available_fields(sessionDir)
    D = dir(fullfile(sessionDir, 'step_*_field_*.f32'));
    fields = {};
    for i = 1:numel(D)
        tok = regexp(D(i).name, '^step_(\d+)_field_(.+)\.f32$', 'tokens','once');
        if ~isempty(tok), fields{end+1,1} = tok{2}; %#ok<AGROW>
        end
    end
    if ~isempty(fields), fields = unique(fields,'stable'); end
end


function T = local_list_frames(sessionDir, fieldName, Nx, Ny)
    D = dir(fullfile(sessionDir, sprintf('step_*_field_%s.f32', fieldName)));
    expectedBytes = Nx*Ny*4;
    step = zeros(numel(D),1); fullPath = cell(numel(D),1); bytes = zeros(numel(D),1); n=0;
    for i = 1:numel(D)
        tok = regexp(D(i).name, '^step_(\d+)_field_', 'tokens','once');
        if isempty(tok), continue; end
        if D(i).bytes ~= expectedBytes
            warning('play_livevis_profiles:incompleteFrame', ...
                'Skipping %s: %d bytes, expected %d.', ...
                fullfile(D(i).folder,D(i).name),D(i).bytes,expectedBytes);
            continue;
        end
        n=n+1; step(n)=str2double(tok{1});
        fullPath{n}=fullfile(D(i).folder,D(i).name); bytes(n)=D(i).bytes;
    end
    step=step(1:n); fullPath=fullPath(1:n); bytes=bytes(1:n);
    [step,order]=sort(step); fullPath=fullPath(order); bytes=bytes(order);
    [~,ia]=unique(step,'last'); ia=sort(ia);
    step=step(ia); fullPath=fullPath(ia); bytes=bytes(ia);
    time=nan(numel(step),1);
    T=table(step,time,bytes,fullPath);
end


function F = local_read_f32(path, Nx, Ny)
    fid=fopen(path,'rb');
    if fid<0, error('play_livevis_profiles:openField','Cannot open %s.',path); end
    cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
    v=fread(fid,Nx*Ny,'single=>single');
    if numel(v)~=Nx*Ny
        error('play_livevis_profiles:shortField', ...
            'Unexpected field size in %s: got %d, expected %d float32.', ...
            path,numel(v),Nx*Ny);
    end
    F=reshape(v,[Nx Ny]).';
end
