function T = analyze_open_channel_q9_virial_inlet_outlet_smoke(varargin)
%ANALYZE_OPEN_CHANNEL_Q9_VIRIAL_INLET_OUTLET_SMOKE Summarize 0064 smoke run.
%
% Usage:
%   T = analyze_open_channel_q9_virial_inlet_outlet_smoke('root','..');

opts.root = '..';
opts.runDir = 'runs/open_channel_q9_virial_inlet_outlet_keepmean_64x32';
opts = parse_opts(opts, varargin{:});

csvPath = fullfile(opts.root, opts.runDir, 'summary_runtime.csv');
if ~isfile(csvPath)
    error('Missing summary_runtime.csv: %s', csvPath);
end

T = readtable(csvPath);

fprintf('Np first/last       : %d / %d\n', T.Np(1), T.Np(end));
fprintf('mass first/last     : %.12g / %.12g\n', T.totalMass(1), T.totalMass(end));
fprintf('meanVx first/last   : %.12g / %.12g\n', T.meanVx(1), T.meanVx(end));
fprintf('kBT min/mean/max    : %.12g / %.12g / %.12g\n', ...
    min(T.kBTEstimate), mean(T.kBTEstimate), max(T.kBTEstimate));
fprintf('stdN first/last     : %.12g / %.12g\n', T.stdN(1), T.stdN(end));
fprintf('minN/maxN final     : %d / %d\n', T.minN(end), T.maxN(end));

fprintf('q6 applied/converged last : %d / %d\n', T.q6Applied(end), T.q6Converged(end));
fprintf('q9 applied/converged last : %d / %d\n', T.q9Applied(end), T.q9Converged(end));
fprintf('virial enabled/kick/applied last : %d / %d / %d\n', ...
    T.virialEnabled(end), T.virialKickEnabled(end), T.virialKickApplied(end));

if ismember('virialOpenBoundaryExcludedCells', T.Properties.VariableNames)
    fprintf('virial excluded/active cells final : %d / %d\n', ...
        T.virialOpenBoundaryExcludedCells(end), T.virialActiveCells(end));
end
fprintf('virial rho mean/defect rel final   : %.12g / %.12g\n', ...
    T.virialRhoMean(end), T.virialRhoDefectRelRms(end));
fprintf('Pkin/Pvir/Ptot/Pdrive final        : %.12g / %.12g / %.12g / %.12g\n', ...
    T.PkinMean(end), T.PvirMean(end), T.PtotMean(end), T.PdriveMean(end));
fprintf('gradP rms/max final                : %.12g / %.12g\n', ...
    T.gradPdriveRms(end), T.gradPdriveMaxAbs(end));
fprintf('virial du rms/max/overThermal final: %.12g / %.12g / %.12g\n', ...
    T.virialDuAppliedRms(end), T.virialDuAppliedMaxAbs(end), T.virialDuOverThermalRms(end));
fprintf('virial momentum residual before/after : %.12g / %.12g\n', ...
    T.virialMomentumResidualBeforeCorrection(end), ...
    T.virialMomentumResidualAfterCorrection(end));

figure;
plot(T.time, T.kBTEstimate, '-o');
xlabel('time'); ylabel('kBT estimate'); grid on;
title('0064 Q9+virial open-channel: temperature');

figure;
plot(T.time, T.stdN, '-o');
xlabel('time'); ylabel('std(N)'); grid on;
title('0064 Q9+virial open-channel: population fluctuations');

figure;
plot(T.time, T.virialDuAppliedRms, '-o'); hold on;
plot(T.time, T.virialDuAppliedMaxAbs, '-o');
xlabel('time'); ylabel('velocity kick'); grid on;
legend('RMS','max abs');
title('0064 virial kick amplitude');

end

function opts = parse_opts(opts, varargin)
if mod(numel(varargin), 2) ~= 0
    error('Options must be name/value pairs.');
end
for k = 1:2:numel(varargin)
    name = varargin{k};
    value = varargin{k+1};
    if ~isfield(opts, name)
        error('Unknown option: %s', name);
    end
    opts.(name) = value;
end
end
