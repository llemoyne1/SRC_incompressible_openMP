function analyze_0493x24d_sato_airwater_density_probe(runRoot)
% ANALYZE_0493X24D_SATO_AIRWATER_DENSITY_PROBE
% Offline feasibility summary for the x24d water/air density-ratio probe.
% This is NOT a validation analysis: the run changes rho_G/rho_L and uses a
% shortened time step plus kBT_G proportional to m_G to preserve kBT_G/m_G.
%
% Usage from <repo>/matlab:
%   analyze_0493x24d_sato_airwater_density_probe
%   analyze_0493x24d_sato_airwater_density_probe('../runs/my_run')

if nargin < 1 || isempty(runRoot)
    runRoot = '../runs/0493x24d_sato_airwater_density_probe_seed493205';
end
summaryFile = fullfile(runRoot,'analysis','sato_stageA_recording_summary.csv');
if ~isfile(summaryFile)
    error('Missing summary file: %s', summaryFile);
end
T = readtable(summaryFile,'VariableNamingRule','preserve');
if height(T) ~= 1
    error('Expected one summary row, found %d',height(T));
end

getv = @(name) T{1,name};
fprintf('\n0493x24d Sato water/air density-ratio feasibility probe\n');
fprintf('=======================================================\n');
fprintf('runRoot                         : %s\n',runRoot);
fprintf('target rho_G/rho_L              : %.12g\n',1.17/997);
fprintf('target H/D                      : %.12g\n',getv('targetHOverD'));
fprintf('target modified Fr_m''           : %.12g\n',getv('targetModifiedFroude'));
fprintf('measured modified Fr_m''         : %.12g +/- %.4g\n', ...
    getv('meanMeasuredModifiedFroude'),getv('stdMeasuredModifiedFroude'));
fprintf('measured/target Fr_m''           : %.6f\n',getv('meanMeasuredFrOverTarget'));
fprintf('incident gas mass density       : %.12g\n',getv('meanIncidentGasMassDensity'));
fprintf('incident mean v_y               : %.12g\n',getv('meanIncidentGasMeanVy'));
fprintf('incident advective-stress proxy : %.12g\n',getv('meanIncidentAdvectiveStress'));
fprintf('gas pressure offset/(rho_G g D) : %.12g +/- %.4g\n', ...
    getv('meanGasPressureOffsetOverRhoGd'),getv('stdGasPressureOffsetOverRhoGd'));
fprintf('h/D (diagnostic only)           : %.12g +/- %.4g\n', ...
    getv('meanDepthOverJetWidth'),getv('stdDepthOverJetWidth'));
fprintf('window drift                    : %.6g\n',getv('relativeDepthDriftAcrossWindow'));
fprintf('stability status                : %s\n',string(T{1,'stabilityStatus'}));
fprintf('\nInterpretation: this run only answers whether the current code can carry\n');
fprintf('the water/air density ratio with a resolved gas flight and a measurable\n');
fprintf('incident forcing. Do not use h/D as an article validation point yet.\n');
end
