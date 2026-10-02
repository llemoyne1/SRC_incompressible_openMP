function analyze_0493x24b_sato_anchor(runRoot)
% ANALYZE_0493X24B_SATO_ANCHOR
% Offline comparison of the x24b H/D=0.8, target Fr_m'=0.90 anchor run
% against the historical x14at result.  This script does not alter physics.
%
% Usage from <repo>/matlab:
%   analyze_0493x24b_sato_anchor
%   analyze_0493x24b_sato_anchor('../runs/my_run')

if nargin < 1 || isempty(runRoot)
    runRoot = '../runs/0493x24b_sato_anchor_H0p8_Fr0p90_seed493205';
end
summaryFile = fullfile(runRoot,'analysis','sato_stageA_recording_summary.csv');
if ~isfile(summaryFile)
    error('Missing summary file: %s', summaryFile);
end
T = readtable(summaryFile,'VariableNamingRule','preserve');
if height(T) ~= 1
    error('Expected one summary row, found %d',height(T));
end

% Historical authoritative values from campaign_report_0493x14at_070926.txt
hist.targetFr = 0.9;
hist.measuredFr = 0.585866384469;
hist.hD = 0.686147221146;
hist.drift = 0.00480608905447;
hist.halfDelta = 0.00996629669984;

getv = @(name) T{1,name};
new.targetFr = getv('targetModifiedFroude');
new.measuredFr = getv('meanMeasuredModifiedFroude');
new.hD = getv('meanDepthOverJetWidth');
new.drift = getv('relativeDepthDriftAcrossWindow');
new.halfDelta = getv('relativeLateMinusEarlyHalfMean');
status = string(T{1,'stabilityStatus'});

fprintf('\n0493x24b Sato anchor comparison\n');
fprintf('================================\n');
fprintf('runRoot                 : %s\n',runRoot);
fprintf('target Fr_m''            : historical %.12g | x24b %.12g\n',hist.targetFr,new.targetFr);
fprintf('measured Fr_m''          : historical %.12g | x24b %.12g | rel. change %+8.3f %%\n', ...
    hist.measuredFr,new.measuredFr,100*(new.measuredFr/hist.measuredFr-1));
fprintf('h/D                     : historical %.12g | x24b %.12g | rel. change %+8.3f %%\n', ...
    hist.hD,new.hD,100*(new.hD/hist.hD-1));
fprintf('relative drift          : historical %.6g | x24b %.6g\n',hist.drift,new.drift);
fprintf('late-early half delta   : historical %.6g | x24b %.6g\n',hist.halfDelta,new.halfDelta);
fprintf('x24b stability status   : %s\n',status);

% Reference-only diagnostic: Sato experimental Stage-A law evaluated at the
% measured incident Froude.  It is not used as an automatic pass/fail test.
satoHD = 1.30*new.measuredFr;
fprintf('Sato 1.30*Fr_m''(meas.)  : %.12g\n',satoHD);
fprintf('x24b / Sato reference   : %.6f\n',new.hD/satoHD);
fprintf('\nInterpretation: first compare x24b with x14at.  The 1.30 slope is a\n');
fprintf('3-D experimental reference and is not a strict 2-D acceptance threshold.\n');
end
