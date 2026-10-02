function out = show_livevis_profile(pathIn, varargin)
%SHOW_LIVEVIS_PROFILE Plot one 1-D profile from an SRC/MPCD LiveVis field.
%
% Two convenient forms are supported.
%
% 1) Pass a recording/session directory and choose field + step:
%
%   show_livevis_profile(recordingDir, ...
%       'field','uy', 'step',1501, ...
%       'direction','y', 'position',0.78125);
%
% 2) Pass one recorded .f32 file; field and step are inferred from its name:
%
%   show_livevis_profile('step_0000001501_field_uy.f32', ...
%       'direction','y', 'position',0.78125);
%
% Direction convention:
%   'direction','x' : F(x,y0), with 'position' = y0.
%   'direction','y' : F(x0,y), with 'position' = x0.
%
% The remaining plotting/grid options are forwarded to
% play_livevis_profiles.m. The important ones are:
%   'field'      recorded field name, e.g. 'uy', 'rho2'
%   'step'       solver step to display (directory form only)
%   'direction'  'x' or 'y'
%   'position'   fixed transverse physical coordinate
%   'sampling'   'linear' or 'nearest'
%   'gain'       scalar multiplier
%   'ylim'       profile-value limits
%   'xlim'       spatial-coordinate limits
%   'lineWidth'  profile line width
%   'showGrid'   true/false
%   'interfaceMode' 'current' reconstructs y_interface from rho1 using the
%                   historical Sato alpha=0.5 crossing; 'initial' uses
%                   interfaceInitialY; 'none' disables it.
%   'nozzleExit'     numeric y, 'auto' (search run env), or []/'none'.
%
% Required dependency:
%   play_livevis_profiles.m
%
% SRC/MPCD utility, 2026-09-25.

    if nargin < 1 || isempty(pathIn)
        [fn, fp] = uigetfile( ...
            {'step_*_field_*.f32','SRC/MPCD LiveVis fields (*.f32)'; ...
             '*.f32','Float32 fields (*.f32)'; '*.*','All files'}, ...
            'Select one recorded LiveVis field');
        if isequal(fn,0)
            error('show_livevis_profile:noInput','No LiveVis field selected.');
        end
        pathIn = fullfile(fp,fn);
    end

    if exist('play_livevis_profiles','file') ~= 2
        error('show_livevis_profile:missingDependency', ...
            'play_livevis_profiles.m is not on the MATLAB path.');
    end

    pathIn = char(pathIn);
    [stepOpt, passArgs] = local_extract_step(varargin);

    if isfile(pathIn)
        [sessionDir, base, ext] = fileparts(pathIn);
        filename = [base ext];
        tok = regexp(filename, '^step_(\d+)_field_(.+)\.f32$', 'tokens','once');
        if isempty(tok)
            error('show_livevis_profile:badFilename', ...
                'Expected step_<step>_field_<field>.f32, got %s.', filename);
        end
        selectedStep = str2double(tok{1});
        fieldName = tok{2};
        if ~isempty(stepOpt) && round(stepOpt) ~= round(selectedStep)
            warning('show_livevis_profile:stepIgnored', ...
                'Input is a single file at step %d; supplied step=%d is ignored.', ...
                round(selectedStep), round(stepOpt));
        end
        % Remove any field supplied in passArgs so the filename stays authoritative.
        passArgs = local_remove_option(passArgs, 'field');
        out = play_livevis_profiles(sessionDir, ...
            'field',fieldName, ...
            'startStep',selectedStep, 'endStep',selectedStep, ...
            'frameStride',1, 'pauseTime',0, ...
            passArgs{:});
    elseif isfolder(pathIn)
        if isempty(stepOpt)
            error('show_livevis_profile:missingStep', ...
                'When pathIn is a directory, supply ''step'',<solverStep>.');
        end
        selectedStep = double(stepOpt);
        out = play_livevis_profiles(pathIn, ...
            'startStep',selectedStep, 'endStep',selectedStep, ...
            'frameStride',1, 'pauseTime',0, ...
            passArgs{:});
        if isempty(out.steps) || round(out.steps(1)) ~= round(selectedStep)
            error('show_livevis_profile:stepNotRecorded', ...
                'Step %d was not found among recorded frames.', round(selectedStep));
        end
    else
        error('show_livevis_profile:missingPath','Cannot find %s.',pathIn);
    end

    out.selectedStep = selectedStep;
    fprintf('[show_livevis_profile] field=%s step=%d profileAlong=%s position=%.9g\n', ...
        out.field, round(selectedStep), out.direction, out.positionUsed);
end


function [stepOpt, passArgs] = local_extract_step(args)
    if mod(numel(args),2) ~= 0
        error('show_livevis_profile:badOptions', ...
            'Optional arguments must be name/value pairs.');
    end
    stepOpt = [];
    passArgs = {};
    for k=1:2:numel(args)
        name=args{k}; value=args{k+1};
        if ~(ischar(name) || (isstring(name) && isscalar(name)))
            error('show_livevis_profile:badOptionName','Option names must be strings.');
        end
        key=lower(strtrim(char(name)));
        if strcmp(key,'step')
            if ~(isnumeric(value) && isscalar(value) && isfinite(value))
                error('show_livevis_profile:badStep','step must be a finite scalar.');
            end
            stepOpt=double(value);
        else
            passArgs(end+1:end+2)=args(k:k+1); %#ok<AGROW>
        end
    end
end


function argsOut = local_remove_option(argsIn, target)
    argsOut = {};
    for k=1:2:numel(argsIn)
        if strcmpi(strtrim(char(argsIn{k})), target)
            continue;
        end
        argsOut(end+1:end+2)=argsIn(k:k+1); %#ok<AGROW>
    end
end
