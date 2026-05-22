function out = validate_immersed_circle_translation(runDir, varargin)
%VALIDATE_IMMERSED_CIRCLE_TRANSLATION Validate a slowly translating immersed circle.
%
%   out = validate_immersed_circle_translation('runs/immersed_circle_translating_64x64')
%
% The diagnostic is deliberately kinematic and conservative. It verifies that
% the moving analytic circle remains inside the active fluid domain, that no
% dumped real particles are left inside the moving solid, and that mass and
% temperature controls remain healthy. It does not attempt to infer wake physics.

p = inputParser;
p.FunctionName = 'validate_immersed_circle_translation';
addRequired(p, 'runDir', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'field', 'speed', @(s) ischar(s) || isstring(s));
parse(p, runDir, varargin{:});
opts = p.Results;
runDir = char(opts.runDir);

paramsPath = fullfile(runDir, 'params_used.kv');
if ~isfile(paramsPath)
    error('Missing params_used.kv in %s', runDir);
end
params = parse_smpcd_kv(paramsPath);
summaryPath = fullfile(runDir, 'summary_runtime.csv');
if ~isfile(summaryPath)
    error('Missing summary_runtime.csv in %s', runDir);
end
summary = readtable(summaryPath);
frameTable = list_smpcd_dumps(runDir);
if isempty(frameTable)
    error('No .smpcd dumps found in %s', runDir);
end

Lx = local_get_num(params, 'Lx', 1.0);
Ly = local_get_num(params, 'Ly', 1.0);
Nx = local_get_num(params, 'Nx', 64);
Ny = local_get_num(params, 'Ny', 64);
cx0 = local_get_num(params, 'immersedCircleCx', 0.5);
cy0 = local_get_num(params, 'immersedCircleCy', 0.5);
Vx = local_get_num(params, 'immersedCircleVx', 0.0);
Vy = local_get_num(params, 'immersedCircleVy', 0.0);
R = local_get_num(params, 'immersedCircleR', 0.12);
omega = local_get_num(params, 'immersedCircleOmega', 0.0);

nFrames = height(frameTable);
insideCounts = zeros(nFrames, 1);
cxFrame = zeros(nFrames, 1);
cyFrame = zeros(nFrames, 1);
finalState = [];
finalFields = [];
for k = 1:nFrames
    tk = frameTable.time(k);
    if isnan(tk), tk = 0.0; end
    cxFrame(k) = cx0 + Vx * tk;
    cyFrame(k) = cy0 + Vy * tk;
    state = read_smpcd_state(frameTable.fullPath{k});
    r2 = (double(state.x(:)) - cxFrame(k)).^2 + (double(state.y(:)) - cyFrame(k)).^2;
    insideCounts(k) = nnz(r2 < (R * (1 - 1e-10))^2);
    if k == nFrames
        finalState = state;
        finalFields = bin_smpcd_state(state, 'Lx', Lx, 'Ly', Ly, 'Nx', Nx, 'Ny', Ny);
    end
end

if ismember('hitsImmersed', summary.Properties.VariableNames)
    totalHits = sum(summary.hitsImmersed);
else
    totalHits = NaN;
end
if ismember('virtualMassImmersed', summary.Properties.VariableNames)
    meanVirtualMass = mean(summary.virtualMassImmersed, 'omitnan');
else
    meanVirtualMass = NaN;
end

speed = hypot(Vx, Vy);
timeStart = summary.time(1);
timeEnd = summary.time(end);
centerStartX = cx0 + Vx * timeStart;
centerStartY = cy0 + Vy * timeStart;
centerEndX = cx0 + Vx * timeEnd;
centerEndY = cy0 + Vy * timeEnd;
displacement = hypot(centerEndX - centerStartX, centerEndY - centerStartY);

out = struct();
out.runDir = runDir;
out.summary = summary;
out.frameTable = frameTable;
out.insideCounts = insideCounts;
out.centerX = cxFrame;
out.centerY = cyFrame;
out.maxParticlesInsideCircle = max(insideCounts);
out.totalImmersedHits = totalHits;
out.meanImmersedVirtualMass = meanVirtualMass;
out.totalMassRelDrift = summary.totalMass(end) / summary.totalMass(1) - 1;
out.kBTMean = mean(summary.kBTEstimate, 'omitnan');
out.kBTRelDrift = summary.kBTEstimate(end) / summary.kBTEstimate(1) - 1;

out.table = table(string(runDir), nFrames, timeStart, timeEnd, ...
    centerStartX, centerEndX, centerStartY, centerEndY, Vx, Vy, speed, displacement, omega, R, ...
    out.maxParticlesInsideCircle, totalHits, meanVirtualMass, out.kBTMean, out.kBTRelDrift, out.totalMassRelDrift, ...
    'VariableNames', {'runDir','nFrames','timeStart','timeEnd', ...
    'centerStartX','centerEndX','centerStartY','centerEndY','Vx','Vy','speed','displacement','omega','radius', ...
    'maxParticlesInsideCircle','totalImmersedHits','meanImmersedVirtualMass','kBTMean','kBTRelDrift','totalMassRelDrift'});
disp(out.table);

if opts.makePlots
    figure('Name', sprintf('Immersed circle translation validation: %s', runDir), 'Color', 'w');
    tiledlayout(2,2, 'Padding', 'compact', 'TileSpacing', 'compact');

    nexttile;
    plot(cxFrame, cyFrame, '-o');
    axis equal; grid on;
    xlabel('cx'); ylabel('cy'); title('circle center path');
    xlim([0 Lx]); ylim([0 Ly]);

    nexttile;
    plot(frameTable.time, insideCounts, '-o');
    xlabel('time'); ylabel('particles inside'); title('penetration diagnostic'); grid on;

    nexttile;
    plot(summary.time, summary.kBTEstimate, '-o');
    xlabel('time'); ylabel('kBT'); title('thermal control'); grid on;

    nexttile;
    plot_smpcd_frame(finalState, finalFields, 'field', opts.field, ...
        'showParticles', false, 'showVelocityVectors', false);
    hold on;
    th = linspace(0, 2*pi, 256);
    plot(centerEndX + R*cos(th), centerEndY + R*sin(th), 'k-', 'LineWidth', 1.5);
    title(sprintf('final %s with moving circle overlay', char(opts.field)), 'Interpreter', 'none');
    hold off;
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
