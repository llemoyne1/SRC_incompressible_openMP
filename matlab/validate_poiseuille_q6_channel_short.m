function out = validate_poiseuille_q6_channel_short(varargin)
%VALIDATE_POISEUILLE_Q6_CHANNEL_SHORT Compare short classic and Q6 channel Poiseuille runs.
%
% Run from the matlab/ directory after launching the C++ examples from the repo root:
%
%   out = validate_poiseuille_q6_channel_short('makePlots', true);

p = inputParser;
p.FunctionName = 'validate_poiseuille_q6_channel_short';
addParameter(p, 'classicRunDir', '../runs/poiseuille_y_classic_solid_thermal_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'q6RunDir', '../runs/poiseuille_y_q6_solid_thermal_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'fitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'excludeWallCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

classic = analyze_poiseuille_profile(char(string(opt.classicRunDir)), ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', opt.fitStartFraction, ...
    'excludeWallCells', opt.excludeWallCells, ...
    'frameStride', opt.frameStride, ...
    'makePlots', logical(opt.makePlots), ...
    'plotConvergence', logical(opt.makePlots));

q6 = analyze_poiseuille_profile(char(string(opt.q6RunDir)), ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', opt.fitStartFraction, ...
    'excludeWallCells', opt.excludeWallCells, ...
    'frameStride', opt.frameStride, ...
    'makePlots', logical(opt.makePlots), ...
    'plotConvergence', logical(opt.makePlots));

classicQ6 = local_q6_tail(classic.summaryTable);
q6Q6 = local_q6_tail(q6.summaryTable);
classicKBTEnd = local_summary_tail_value(classic.summaryTable, 'kBTEstimate');
q6KBTEnd = local_summary_tail_value(q6.summaryTable, 'kBTEstimate');

summary = table( ...
    string({'classic'; 'q6'}), ...
    [height(classic.frameTable); height(q6.frameTable)], ...
    [classic.frameTable.time(1); q6.frameTable.time(1)], ...
    [classic.frameTable.time(end); q6.frameTable.time(end)], ...
    [classic.uCenter; q6.uCenter], ...
    [classic.uMax; q6.uMax], ...
    [classic.fit.r2; q6.fit.r2], ...
    [classic.fit.nuEff; q6.fit.nuEff], ...
    [classicKBTEnd; q6KBTEnd], ...
    [classicQ6.divAfter; q6Q6.divAfter], ...
    [classicQ6.residual; q6Q6.residual], ...
    [classicQ6.iterations; q6Q6.iterations], ...
    'VariableNames', {'run','nFrames','timeStart','timeEnd','uCenter','uMax','fitR2','nuEff','kBTEnd','q6RuntimeDivAfterEnd','q6RuntimeResidualEnd','q6IterationsEnd'});

out = struct();
out.classic = classic;
out.q6 = q6;
out.summary = summary;

disp('=== Poiseuille periodic-x / wall-y Q6 channel validation ===');
disp(summary);

if logical(opt.makePlots)
    local_plot_comparison(classic, q6);
end
end

function value = local_summary_tail_value(T, name)
value = NaN;
if isempty(T) || ~istable(T) || ~ismember(name, T.Properties.VariableNames) || height(T) < 1
    return;
end
v = T.(name);
idx = find(isfinite(v), 1, 'last');
if ~isempty(idx)
    value = v(idx);
end
end

function q = local_q6_tail(T)
q = struct('divAfter', NaN, 'residual', NaN, 'iterations', NaN);
if isempty(T) || ~istable(T) || ~ismember('q6Applied', T.Properties.VariableNames)
    return;
end
mask = T.q6Applied > 0;
if ~any(mask)
    return;
end
TT = T(mask, :);
q.divAfter = TT.q6DivAfterProjectedFluxRms(end);
q.residual = TT.q6ResidualRel(end);
q.iterations = TT.q6Iterations(end);
end

function local_plot_comparison(classic, q6)
figure('Name', 'Poiseuille classic vs Q6 channel profile');
plot(classic.coord, classic.avgProfile, 'o-', 'DisplayName', 'classic');
hold on;
plot(q6.coord, q6.avgProfile, 's-', 'DisplayName', 'q6');
plot(classic.coord, classic.fit.fitProfile, '--', 'DisplayName', 'classic fit');
plot(q6.coord, q6.fit.fitProfile, '--', 'DisplayName', 'q6 fit');
hold off;
grid on;
xlabel('y');
ylabel('Ux');
legend('Location', 'best');
title('Periodic-x / solid-y Poiseuille: classic vs Q6');

if ~isempty(q6.summaryTable) && ismember('q6Applied', q6.summaryTable.Properties.VariableNames)
    T = q6.summaryTable(q6.summaryTable.q6Applied > 0, :);
    if ~isempty(T)
        figure('Name', 'Q6 channel runtime projection diagnostics');
        semilogy(T.time, T.q6DivBeforeRms, '-', 'DisplayName', 'div before');
        hold on;
        semilogy(T.time, T.q6DivAfterProjectedFluxRms, '-', 'DisplayName', 'div after');
        semilogy(T.time, T.q6ResidualRel, '-', 'DisplayName', 'CG residual');
        hold off;
        grid on;
        xlabel('time');
        ylabel('RMS / relative residual');
        legend('Location', 'best');
        title('Q6 channel projection diagnostics');
    end
end
end
