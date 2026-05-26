function out = validate_immersed_circle_rotation(runDir, varargin)
%VALIDATE_IMMERSED_CIRCLE_ROTATION Validate a fixed rotating immersed circle.
%
%   out = validate_immersed_circle_rotation(runDir)
%
%   This is a lightweight MATLAB-only diagnostic. It computes time-averaged
%   fields, transforms the mean velocity to polar components around the circle,
%   and reports radial averages of the tangential velocity.
%
%   Optional name/value pairs:
%     'timeAverageStartFraction' : default 0.5
%     'frameStride'              : default 1
%     'filterType'               : default 'box'
%     'filterWidth'              : default 3
%     'nRadialBins'              : default 16
%     'rMax'                     : default 0.45
%     'makePlots'                : default true

p = inputParser;
p.FunctionName = 'validate_immersed_circle_rotation';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'timeAverageStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'filterType', 'box', @(s) ischar(s) || isstring(s));
addParameter(p, 'filterWidth', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'nRadialBins', 16, @(x) isnumeric(x) && isscalar(x) && x >= 4);
addParameter(p, 'rMax', 0.45, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, runDir, varargin{:});
opts = p.Results;

runDir = char(opts.runDir);
params = parse_smpcd_kv(fullfile(runDir, 'params_used.kv'));

cx = local_get_num(params, 'immersedCircleCx', 0.5);
cy = local_get_num(params, 'immersedCircleCy', 0.5);
R  = local_get_num(params, 'immersedCircleR', 0.12);
omega = local_get_num(params, 'immersedCircleOmega', 0.0);

avg = analyze_immersed_circle_time_average(runDir, ...
    'fieldList', {'Ux','Uy','omega','speed'}, ...
    'timeAverageStartFraction', opts.timeAverageStartFraction, ...
    'frameStride', opts.frameStride, ...
    'filterType', opts.filterType, ...
    'filterWidth', opts.filterWidth, ...
    'showPlots', false);

X = avg.Xc;
Y = avg.Yc;
Ux = avg.meanFields.Ux;
Uy = avg.meanFields.Uy;
OmegaField = avg.meanFields.omega;

dx = X - cx;
dy = Y - cy;
r = hypot(dx, dy);
exThetaX = -dy ./ max(r, eps);
exThetaY =  dx ./ max(r, eps);
uTheta = Ux .* exThetaX + Uy .* exThetaY;
uRadial = Ux .* dx ./ max(r, eps) + Uy .* dy ./ max(r, eps);

rMin = R;
rMax = min(opts.rMax, max(r(:)));
edges = linspace(rMin, rMax, opts.nRadialBins + 1);
radius = zeros(opts.nRadialBins, 1);
meanUtheta = nan(opts.nRadialBins, 1);
stdUtheta = nan(opts.nRadialBins, 1);
meanUradial = nan(opts.nRadialBins, 1);
meanOmega = nan(opts.nRadialBins, 1);
nCells = zeros(opts.nRadialBins, 1);

for b = 1:opts.nRadialBins
    mask = r >= edges(b) & r < edges(b+1);
    radius(b) = 0.5 * (edges(b) + edges(b+1));
    nCells(b) = nnz(mask);
    if nCells(b) > 0
        vals = uTheta(mask);
        meanUtheta(b) = mean(vals, 'omitnan');
        stdUtheta(b) = std(vals, 0, 'omitnan');
        meanUradial(b) = mean(uRadial(mask), 'omitnan');
        meanOmega(b) = mean(OmegaField(mask), 'omitnan');
    end
end

radialTable = table(radius, meanUtheta, stdUtheta, meanUradial, meanOmega, nCells);

summary = table();
summary.runDir = string(runDir);
summary.omega = omega;
summary.radius = R;
summary.expectedSurfaceSpeed = omega * R;
summary.nAveragedFrames = avg.nAveragedFrames;
summary.timeStart = avg.timeWindow(1);
summary.timeEnd = avg.timeWindow(2);
summary.nearWallMeanUtheta = meanUtheta(1);
summary.nearWallSlip = omega * R - meanUtheta(1);
summary.nearWallMeanUradial = meanUradial(1);

out = struct();
out.runDir = runDir;
out.avg = avg;
out.uTheta = uTheta;
out.uRadial = uRadial;
out.radialTable = radialTable;
out.summary = summary;
out.options = opts;

disp(summary);

if opts.makePlots
    local_plot_rotation(out, X, Y, cx, cy, R, Ux, Uy, uTheta, uRadial, OmegaField, radialTable);
end
end

function val = local_get_num(params, key, defaultVal)
if isfield(params, key)
    val = str2double(string(params.(key)));
    if ~isnan(val)
        return;
    end
end
val = defaultVal;
end

function local_plot_rotation(out, X, Y, cx, cy, R, Ux, Uy, uTheta, uRadial, OmegaField, radialTable)
figure('Name', sprintf('Immersed circle rotation validation: %s', out.runDir), 'Color', 'w');
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
local_imagesc_circle(X, Y, uTheta, cx, cy, R, 'mean tangential velocity');

nexttile;
local_imagesc_circle(X, Y, uRadial, cx, cy, R, 'mean radial velocity');

nexttile;
local_imagesc_circle(X, Y, OmegaField, cx, cy, R, 'mean omega');
hold on;
ss = 4;
quiver(X(1:ss:end,1:ss:end), Y(1:ss:end,1:ss:end), ...
       Ux(1:ss:end,1:ss:end), Uy(1:ss:end,1:ss:end), 'k');
hold off;

nexttile;
plot(radialTable.radius, radialTable.meanUtheta, '-o');
hold on;
yline(out.summary.expectedSurfaceSpeed, '--', 'surface speed');
yline(0, ':');
hold off;
grid on;
xlabel('r');
ylabel('<u_\theta>');
title('radial tangential velocity');
end

function local_imagesc_circle(X, Y, A, cx, cy, R, ttl)
imagesc(X(1,:), Y(:,1), A);
axis image;
set(gca, 'YDir', 'normal');
colorbar;
hold on;
th = linspace(0, 2*pi, 256);
plot(cx + R*cos(th), cy + R*sin(th), 'k-', 'LineWidth', 1.0);
hold off;
title(ttl, 'Interpreter', 'none');
xlabel('x');
ylabel('y');
end
