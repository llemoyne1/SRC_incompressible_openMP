function analyze_0493x24c_sato_corrected_H1p7(runRoot)
% ANALYZE_0493X24C_SATO_CORRECTED_H1P7
% Offline comparison of the corrected H/D=1.7, target Fr_m'=0.90 run
% against both the historical x14at H/D=1.7 case and the x24b H/D=0.8
% strong-Brinkman anchor.  No physics is changed by this analysis.
%
% Usage from <repo>/matlab:
%   analyze_0493x24c_sato_corrected_H1p7
%   analyze_0493x24c_sato_corrected_H1p7('../runs/my_run')

if nargin < 1 || isempty(runRoot)
    runRoot = '../runs/0493x24c_sato_corrected_H1p7_Fr0p90_seed493205';
end
summaryFile = fullfile(runRoot,'analysis','sato_stageA_recording_summary.csv');
if ~isfile(summaryFile)
    error('Missing summary file: %s', summaryFile);
end
T = readtable(summaryFile,'VariableNamingRule','preserve');
if height(T) ~= 1
    error('Expected one summary row, found %d',height(T));
end

% Historical H/D=1.7 x14at values from campaign_report_0493x14at_070926.txt.
hist.targetFr = 0.9;
hist.measuredFr = 0.768893965093;
hist.hD = 0.390437070471;
hist.drift = -0.224634725549;
hist.halfDelta = -0.0941706647109;
hist.dpStar = -1.75251174283;

% Current H/D=0.8 x24b anchor with the same alphaMax=8e5 wall model.
anchor.measuredFr = 0.61049825;
anchor.hD = 0.66512731;
anchor.drift = 0.04297;
anchor.halfDelta = 0.02307;

getv = @(name) T{1,name};
new.targetFr = getv('targetModifiedFroude');
new.measuredFr = getv('meanMeasuredModifiedFroude');
new.hD = getv('meanDepthOverJetWidth');
new.drift = getv('relativeDepthDriftAcrossWindow');
new.halfDelta = getv('relativeLateMinusEarlyHalfMean');
status = string(T{1,'stabilityStatus'});

fprintf('\n0493x24c Sato corrected H/D=1.7 comparison\n');
fprintf('================================================\n');
fprintf('runRoot                   : %s\n',runRoot);
fprintf('target Fr_m''              : historical %.12g | x24c %.12g\n',hist.targetFr,new.targetFr);
fprintf('measured Fr_m''            : historical %.12g | x24c %.12g | rel. change %+8.3f %%\n', ...
    hist.measuredFr,new.measuredFr,100*(new.measuredFr/hist.measuredFr-1));
fprintf('h/D                       : historical %.12g | x24c %.12g | rel. change %+8.3f %%\n', ...
    hist.hD,new.hD,100*(new.hD/hist.hD-1));
fprintf('relative drift            : historical %.6g | x24c %.6g\n',hist.drift,new.drift);
fprintf('late-early half delta     : historical %.6g | x24c %.6g\n',hist.halfDelta,new.halfDelta);
fprintf('x24c stability status     : %s\n',status);
fprintf('\nStrong-Brinkman H/D=0.8 anchor (x24b)\n');
fprintf('measured Fr_m''            : %.12g\n',anchor.measuredFr);
fprintf('h/D                       : %.12g\n',anchor.hD);
fprintf('x24c - x24b h/D           : %+ .12g\n',new.hD-anchor.hD);
fprintf('relative H/D response     : %+8.3f %%\n',100*(new.hD/anchor.hD-1));

% Reference-only diagnostic. Not an automatic pass/fail test.
satoHD = 1.30*new.measuredFr;
fprintf('\nSato 1.30*Fr_m''(meas.)    : %.12g\n',satoHD);
fprintf('x24c / Sato reference     : %.6f\n',new.hD/satoHD);
fprintf('\nInterpretation contract:\n');
fprintf('- first compare x24c with historical x14at H/D=1.7;\n');
fprintf('- use x24b only to control the strong-Brinkman wall change;\n');
fprintf('- the Sato 1.30 slope is a 3-D experimental reference, not a strict 2-D threshold.\n');
end
