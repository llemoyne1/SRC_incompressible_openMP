function out = demo_immersed_circle_combined_motion(runDir, varargin)
%DEMO_IMMERSED_CIRCLE_COMBINED_MOTION Demonstration helper for a translating+rotating immersed circle.
%
%   out = demo_immersed_circle_combined_motion(runDir)
%
%   This helper combines:
%     1) translation diagnostics,
%     2) rotation diagnostics on the late-time window,
%     3) time-averaged fields,
%     4) optional filtered animation.
%
%   Optional name/value pairs:
%     'makePlots'                : true/false (default true)
%     'playAnimation'            : true/false (default true)
%     'animationField'           : 'omega','speed','Ux','Uy','rho' (default 'omega')
%     'timeAverageStartFraction' : fraction discarded before averaging (default 0.5)
%     'filterType'               : 'none' or 'box' (default 'box')
%     'filterWidth'              : odd positive integer (default 3)
%     'temporalHalfWindow'       : temporal smoothing half-window for animation (default 1)
%     'pauseTime'                : animation pause time in seconds (default 0.04)
%
%   Example:
%     out = demo_immersed_circle_combined_motion( ...
%         'runs/immersed_circle_combined_motion_64x64', ...
%         'makePlots', true, ...
%         'playAnimation', true, ...
%         'animationField', 'omega');

p = inputParser;
p.FunctionName = 'demo_immersed_circle_combined_motion';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'playAnimation', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'animationField', 'omega', @(s) ischar(s) || isstring(s));
addParameter(p, 'timeAverageStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'filterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'filterWidth', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'temporalHalfWindow', 1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'pauseTime', 0.04, @(x) isnumeric(x) && isscalar(x) && x >= 0);
parse(p, runDir, varargin{:});
opts = p.Results;

runDir = char(opts.runDir);

out = struct();
out.runDir = runDir;

out.smoke = validate_immersed_circle_smoke(runDir, ...
    'makePlots', opts.makePlots, ...
    'field', char(string(opts.animationField)));

out.translation = validate_immersed_circle_translation(runDir, ...
    'makePlots', opts.makePlots, ...
    'field', 'speed');

out.rotation = validate_immersed_circle_rotation(runDir, ...
    'timeAverageStartFraction', opts.timeAverageStartFraction, ...
    'filterType', opts.filterType, ...
    'filterWidth', opts.filterWidth, ...
    'makePlots', opts.makePlots);

out.timeAverage = analyze_immersed_circle_time_average(runDir, ...
    'fieldList', {'Ux','Uy','omega','speed'}, ...
    'timeAverageStartFraction', opts.timeAverageStartFraction, ...
    'filterType', opts.filterType, ...
    'filterWidth', opts.filterWidth, ...
    'showPlots', opts.makePlots);

if opts.playAnimation
    out.animation = play_smpcd_filtered_animation(runDir, ...
        'field', char(string(opts.animationField)), ...
        'timeAverageStartFraction', opts.timeAverageStartFraction, ...
        'filterType', opts.filterType, ...
        'filterWidth', opts.filterWidth, ...
        'temporalHalfWindow', opts.temporalHalfWindow, ...
        'pauseTime', opts.pauseTime);
else
    out.animation = [];
end

fprintf('\n=== Combined immersed-circle demo summary ===\n');
tr = local_first_table_row(out.translation);
if ~isempty(tr) && all(ismember({'centerStartX','centerEndX','centerStartY','centerEndY'}, tr.Properties.VariableNames))
    fprintf('Translation: x %.6g -> %.6g, y %.6g -> %.6g\n', ...
        tr.centerStartX, tr.centerEndX, tr.centerStartY, tr.centerEndY);
end

rot = local_first_table_row(out.rotation);
if ~isempty(rot) && all(ismember({'nearWallMeanUtheta','expectedSurfaceSpeed'}, rot.Properties.VariableNames))
    fprintf('Rotation: near-wall <u_theta> = %.6g, expected surface speed = %.6g\n', ...
        rot.nearWallMeanUtheta, rot.expectedSurfaceSpeed);
end

sm = local_first_table_row(out.smoke);
if ~isempty(sm) && ismember('maxParticlesInsideCircle', sm.Properties.VariableNames)
    fprintf('Penetration diagnostic: max particles inside circle = %g\n', ...
        sm.maxParticlesInsideCircle);
end
fprintf('================================================\n\n');
end

function row = local_first_table_row(x)
row = [];

if istable(x)
    if height(x) >= 1
        row = x(1,:);
    end
    return;
end

if isstruct(x)
    names = fieldnames(x);
    for k = 1:numel(names)
        candidate = x.(names{k});
        if istable(candidate) && height(candidate) >= 1
            row = candidate(1,:);
            return;
        end
    end
end
end
