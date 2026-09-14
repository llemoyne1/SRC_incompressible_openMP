function result = analyze_0493x16d_capture_channels(pairRoot)
% 0493x16d — diagnostic attribution of Galilean grid-phase impulses.
%
% This analyzer reuses the EXISTING x16d rest/boost runs.  It does not
% require a solver modification or a rerun.  The raw dynamic-solid CSV
% already contains the exact separated fluid impulses produced by
% Brinkman, outward_bath and chiVP, plus the x16c fictitious-fluid inventory.
%
% Main questions:
%   1) Do the large boost impulses occur when the binary solid mask changes
%      by one Eulerian cell column?
%   2) Are those events accompanied by a jump in fictitious-fluid mass?
%   3) Which exact coupling channel (Brinkman / outward_bath / chiVP)
%      carries the event impulse?
%
% IMPORTANT timing note:
% fictitiousFluidMass0493x16c is sampled after the Darcy/bath stage of the
% current step.  Delta M_fict is therefore an AFTER-COUPLING inventory
% change, not an exact pre-coupling count of newly engulfed particles.
%
% Run from repository matlab/:
%   analyze_0493x16d_capture_channels('../runs/0493x16d_galilean_pair')

if nargin < 1 || isempty(pairRoot)
    pairRoot = fullfile('..','runs','0493x16d_galilean_pair');
end

restRoot  = fullfile(pairRoot,'rest','fresh');
boostRoot = fullfile(pairRoot,'boost','fresh');
R = loadCase(restRoot);
B = loadCase(boostRoot);

analysisDir = fullfile(pairRoot,'analysis_capture_channels');
if ~isfolder(analysisDir), mkdir(analysisDir); end

AR = analyzeCase(R);
AB = analyzeCase(B);

% ---- detailed step table (boost is the decisive moving case) ----
T = table(B.step, B.time, B.phase, B.centerX, B.solidVx, ...
    AB.maskShift, AB.deltaFictMass, B.fictMass, ...
    B.brinkmanIx, B.bathIx, B.chiVpIx, B.totalIx, ...
    abs(B.brinkmanIx), abs(B.bathIx), abs(B.chiVpIx), abs(B.totalIx), ...
    'VariableNames', {'step','time','phase','centerX','solidVx', ...
    'maskShift','deltaFictitiousMass','fictitiousMass', ...
    'brinkmanFluidImpulseX','outwardBathFluidImpulseX','chiVpFluidImpulseX', ...
    'totalFluidImpulseX','absBrinkmanImpulseX','absOutwardBathImpulseX', ...
    'absChiVpImpulseX','absTotalImpulseX'});
writetable(T, fullfile(analysisDir,'capture_steps_0493x16d.csv'));

% ---- all steady mask-shift events ----
eventIdx = find(AB.steady & AB.maskShift);
E = T(eventIdx,:);
writetable(E, fullfile(analysisDir,'capture_events_0493x16d.csv'));

% ---- strongest positive inventory jumps, irrespective of exact event tag ----
steadyIdx = find(AB.steady & isfinite(AB.deltaFictMass));
[~,ord] = sort(AB.deltaFictMass(steadyIdx),'descend');
nTop = min(20,numel(ord));
topIdx = steadyIdx(ord(1:nTop));
Top = T(topIdx,:);
writetable(Top, fullfile(analysisDir,'capture_top_mass_gain_events_0493x16d.csv'));

% ---- phase-binned diagnostic ----
nBins = 40;
edges = linspace(0,1,nBins+1);
phaseBin = discretize(B.phase,edges);
rows = [];
for b = 1:nBins
    q = AB.steady & phaseBin==b;
    if ~any(q), continue; end
    center = 0.5*(edges(b)+edges(b+1));
    row = [center, sum(q), sum(AB.maskShift(q)), ...
        mean(B.fictMass(q)), meanFinite(AB.deltaFictMass(q)), meanFinite(abs(AB.deltaFictMass(q))), ...
        mean(B.brinkmanIx(q)), mean(B.bathIx(q)), mean(B.chiVpIx(q)), mean(B.totalIx(q)), ...
        mean(abs(B.brinkmanIx(q))), mean(abs(B.bathIx(q))), mean(abs(B.chiVpIx(q))), mean(abs(B.totalIx(q)))];
    rows = [rows; row]; %#ok<AGROW>
end
P = array2table(rows,'VariableNames',{'phaseCenter','samples','maskShiftEvents', ...
    'meanFictitiousMass','meanDeltaFictitiousMass','meanAbsDeltaFictitiousMass', ...
    'meanBrinkmanImpulseX','meanOutwardBathImpulseX','meanChiVpImpulseX','meanTotalImpulseX', ...
    'meanAbsBrinkmanImpulseX','meanAbsOutwardBathImpulseX','meanAbsChiVpImpulseX','meanAbsTotalImpulseX'});
writetable(P, fullfile(analysisDir,'capture_phase_bins_0493x16d.csv'));

% ---- compact channel summary ----
channelNames = {'brinkman';'outward_bath';'chiVP';'total'};
boostEventRms = [AB.rmsBrinkmanEvent; AB.rmsBathEvent; AB.rmsChiVpEvent; AB.rmsTotalEvent];
boostAwayRms  = [AB.rmsBrinkmanAway;  AB.rmsBathAway;  AB.rmsChiVpAway;  AB.rmsTotalAway];
boostAmp      = boostEventRms ./ max(boostAwayRms,1e-30);
boostAbsShare = [AB.absShareBrinkmanEvent; AB.absShareBathEvent; AB.absShareChiVpEvent; 1.0];
boostCorrDM   = [AB.corrAbsBrinkmanAbsDeltaM; AB.corrAbsBathAbsDeltaM; AB.corrAbsChiVpAbsDeltaM; AB.corrAbsTotalAbsDeltaM];
C = table(channelNames,boostEventRms,boostAwayRms,boostAmp,boostAbsShare,boostCorrDM, ...
    'VariableNames',{'channel','rmsImpulseAtMaskShift','rmsImpulseAwayFromMaskShift', ...
    'eventToAwayRmsRatio','absoluteChannelShareAtMaskShift','corrAbsImpulseVsAbsDeltaM'});
writetable(C, fullfile(analysisDir,'capture_channel_summary_0493x16d.csv'));

% ---- summary text ----
[~,iStrong] = max([AB.rmsBrinkmanEvent,AB.rmsBathEvent,AB.rmsChiVpEvent]);
strongNames = {'brinkman','outward_bath','chiVP'};
strongest = strongNames{iStrong};

fid = fopen(fullfile(analysisDir,'summary_capture_channels_0493x16d.txt'),'w');
assert(fid>=0,'Cannot create x16d capture-channel summary');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid,'0493x16d Galilean mask-capture / impulse-channel attribution\n');
fprintf(fid,'sourceRuns=%s\n',pairRoot);
fprintf(fid,'diagnosticOnly=1\n');
fprintf(fid,'rerunRequired=0\n');
fprintf(fid,'fictitiousMassTiming=post_Darcy_bath_current_step\n');
fprintf(fid,'steadyDefinition=second_half_of_each_run\n');
fprintf(fid,'\n');
fprintf(fid,'boostSteadySamples=%d\n',sum(AB.steady));
fprintf(fid,'boostMaskShiftEvents=%d\n',sum(AB.steady & AB.maskShift));
fprintf(fid,'boostMaskShiftEventFraction=%.17g\n',sum(AB.steady & AB.maskShift)/max(sum(AB.steady),1));
fprintf(fid,'boostMeanPhaseAtMaskShift=%.17g\n',circularMean01(B.phase(AB.steady & AB.maskShift)));
fprintf(fid,'boostMeanDeltaFictMassAtMaskShift=%.17g\n',meanFinite(AB.deltaFictMass(AB.steady & AB.maskShift)));
fprintf(fid,'boostMeanAbsDeltaFictMassAtMaskShift=%.17g\n',meanFinite(abs(AB.deltaFictMass(AB.steady & AB.maskShift))));
fprintf(fid,'boostMeanAbsDeltaFictMassAway=%.17g\n',meanFinite(abs(AB.deltaFictMass(AB.steady & ~AB.maskShift))));
fprintf(fid,'boostCorrAbsTotalImpulseAbsDeltaM=%.17g\n',AB.corrAbsTotalAbsDeltaM);
fprintf(fid,'boostCorrAbsBrinkmanImpulseAbsDeltaM=%.17g\n',AB.corrAbsBrinkmanAbsDeltaM);
fprintf(fid,'boostCorrAbsBathImpulseAbsDeltaM=%.17g\n',AB.corrAbsBathAbsDeltaM);
fprintf(fid,'boostCorrAbsChiVpImpulseAbsDeltaM=%.17g\n',AB.corrAbsChiVpAbsDeltaM);
fprintf(fid,'\n');
fprintf(fid,'boostRmsTotalImpulseAtMaskShift=%.17g\n',AB.rmsTotalEvent);
fprintf(fid,'boostRmsTotalImpulseAway=%.17g\n',AB.rmsTotalAway);
fprintf(fid,'boostTotalEventAmplification=%.17g\n',AB.rmsTotalEvent/max(AB.rmsTotalAway,1e-30));
fprintf(fid,'boostRmsBrinkmanAtMaskShift=%.17g\n',AB.rmsBrinkmanEvent);
fprintf(fid,'boostRmsOutwardBathAtMaskShift=%.17g\n',AB.rmsBathEvent);
fprintf(fid,'boostRmsChiVpAtMaskShift=%.17g\n',AB.rmsChiVpEvent);
fprintf(fid,'boostAbsShareBrinkmanAtMaskShift=%.17g\n',AB.absShareBrinkmanEvent);
fprintf(fid,'boostAbsShareOutwardBathAtMaskShift=%.17g\n',AB.absShareBathEvent);
fprintf(fid,'boostAbsShareChiVpAtMaskShift=%.17g\n',AB.absShareChiVpEvent);
fprintf(fid,'strongestRmsChannelAtMaskShift=%s\n',strongest);
fprintf(fid,'\n');
fprintf(fid,'restMaskShiftEventsSteady=%d\n',sum(AR.steady & AR.maskShift));
fprintf(fid,'restRmsTotalImpulse=%.17g\n',rmsFinite(R.totalIx(AR.steady)));
fprintf(fid,'boostRmsTotalImpulse=%.17g\n',rmsFinite(B.totalIx(AB.steady)));

fprintf('\n===== 0493x16d CAPTURE / CHANNEL ATTRIBUTION =====\n');
fprintf('existing x16d runs only; no rerun required\n');
fprintf('boost steady mask shifts             = %d\n',sum(AB.steady & AB.maskShift));
fprintf('mean |Delta M_fict| shift / away     = %.6g / %.6g\n', ...
    meanFinite(abs(AB.deltaFictMass(AB.steady & AB.maskShift))), ...
    meanFinite(abs(AB.deltaFictMass(AB.steady & ~AB.maskShift))));
fprintf('corr |I_total| vs |Delta M_fict|     = %.6f\n',AB.corrAbsTotalAbsDeltaM);
fprintf('RMS I_total shift / away             = %.6g / %.6g (x%.3f)\n', ...
    AB.rmsTotalEvent,AB.rmsTotalAway,AB.rmsTotalEvent/max(AB.rmsTotalAway,1e-30));
fprintf('RMS at shift: Brinkman / bath / VP   = %.6g / %.6g / %.6g\n', ...
    AB.rmsBrinkmanEvent,AB.rmsBathEvent,AB.rmsChiVpEvent);
fprintf('|I| shares at shift B / bath / VP    = %.3f / %.3f / %.3f\n', ...
    AB.absShareBrinkmanEvent,AB.absShareBathEvent,AB.absShareChiVpEvent);
fprintf('strongest RMS channel at shift       = %s\n',strongest);
fprintf('analysis                             = %s\n',analysisDir);
fprintf('NOTE: Delta M_fict is post-coupling inventory, not exact newly engulfed mass.\n');
fprintf('=====================================================\n');

% ---- figures ----
figure;
plot(B.step(AB.steady),AB.deltaFictMass(AB.steady),'-'); hold on;
idx = AB.steady & AB.maskShift;
plot(B.step(idx),AB.deltaFictMass(idx),'o');
xlabel('step'); ylabel('\Delta M_{fict}');
title('0493x16d boost: fictitious-mass changes at binary-mask shifts');
grid on; legend('\Delta M_{fict}','mask shift','Location','best');

figure;
plot(B.phase(AB.steady),B.brinkmanIx(AB.steady),'.'); hold on;
plot(B.phase(AB.steady),B.bathIx(AB.steady),'.');
plot(B.phase(AB.steady),B.chiVpIx(AB.steady),'.');
xlabel('sub-cell slab phase'); ylabel('fluid impulse x / step');
title('0493x16d boost: exact coupling channels versus grid phase');
grid on; legend('Brinkman','outward bath','chiVP','Location','best');

figure;
plot(AB.deltaFictMass(AB.steady),abs(B.totalIx(AB.steady)),'.'); hold on;
plot(AB.deltaFictMass(idx),abs(B.totalIx(idx)),'o');
xlabel('\Delta M_{fict}'); ylabel('|I_{total,x}|');
title('0493x16d boost: impulse amplitude versus fictitious-mass change');
grid on; legend('steady samples','mask shifts','Location','best');

result = struct();
result.analysisDir = analysisDir;
result.boostMaskShiftEvents = sum(AB.steady & AB.maskShift);
result.corrAbsTotalImpulseAbsDeltaM = AB.corrAbsTotalAbsDeltaM;
result.strongestRmsChannelAtMaskShift = strongest;
result.rmsBrinkmanAtMaskShift = AB.rmsBrinkmanEvent;
result.rmsOutwardBathAtMaskShift = AB.rmsBathEvent;
result.rmsChiVpAtMaskShift = AB.rmsChiVpEvent;
result.rmsTotalAtMaskShift = AB.rmsTotalEvent;
result.rmsTotalAway = AB.rmsTotalAway;
end

function C = loadCase(runRoot)
outDir = fullfile(runRoot,'output');
dynPath = fullfile(outDir,'chi_solid_dynamics_0493x16a.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(dynPath),'Missing %s',dynPath);
assert(isfile(paramPath),'Missing %s',paramPath);
D = readtable(dynPath,'VariableNamingRule','preserve');
assert(~isempty(D),'Empty %s',dynPath);

required = {'step','time','centerXBefore','velocityXBefore', ...
    'brinkmanFluidImpulseX','bathFluidImpulseX','chiVpFluidImpulseX','totalFluidImpulseX', ...
    'fictitiousFluidDiagnostic0493x16c','fictitiousFluidMass0493x16c'};
for j=1:numel(required)
    assert(ismember(required{j},D.Properties.VariableNames), ...
        'Missing column %s in %s',required{j},dynPath);
end
assert(all(D.fictitiousFluidDiagnostic0493x16c~=0), ...
    'x16c fictitious-fluid diagnostic is not available on every row of %s',dynPath);

C.step = D.step;
C.time = D.time;
C.centerX = D.centerXBefore;
C.solidVx = D.velocityXBefore;
C.brinkmanIx = D.brinkmanFluidImpulseX;
C.bathIx = D.bathFluidImpulseX;
C.chiVpIx = D.chiVpFluidImpulseX;
C.totalIx = D.totalFluidImpulseX;
C.fictMass = D.fictitiousFluidMass0493x16c;
C.Lx = readKvNumber(paramPath,'Lx');
C.Nx = round(readKvNumber(paramPath,'Nx'));
C.dx = C.Lx/C.Nx;
C.phase = mod(C.centerX/C.dx,1.0);
end

function A = analyzeCase(C)
n = numel(C.step);
A.steady = C.step >= 0.5*max(C.step);
A.deltaFictMass = [NaN; diff(C.fictMass)];

% Unwrap periodic center motion, then detect changes of the binary cell-center
% mask.  For the even-width slab used by x16d, the mask changes when the
% nearest grid-aligned slab-center index changes, i.e. at sub-cell phase 0.5.
c = C.centerX(:);
dc = diff(c);
dc(dc >  0.5*C.Lx) = dc(dc >  0.5*C.Lx) - C.Lx;
dc(dc < -0.5*C.Lx) = dc(dc < -0.5*C.Lx) + C.Lx;
cu = [c(1); c(1)+cumsum(dc)];
maskIndex = floor(cu/C.dx + 0.5);
A.maskShift = [false; diff(maskIndex)~=0];

valid = A.steady & isfinite(A.deltaFictMass);
A.corrAbsTotalAbsDeltaM = safeCorr(abs(C.totalIx(valid)),abs(A.deltaFictMass(valid)));
A.corrAbsBrinkmanAbsDeltaM = safeCorr(abs(C.brinkmanIx(valid)),abs(A.deltaFictMass(valid)));
A.corrAbsBathAbsDeltaM = safeCorr(abs(C.bathIx(valid)),abs(A.deltaFictMass(valid)));
A.corrAbsChiVpAbsDeltaM = safeCorr(abs(C.chiVpIx(valid)),abs(A.deltaFictMass(valid)));

evt = A.steady & A.maskShift;
away = A.steady & ~A.maskShift;
A.rmsBrinkmanEvent = rmsFinite(C.brinkmanIx(evt));
A.rmsBathEvent = rmsFinite(C.bathIx(evt));
A.rmsChiVpEvent = rmsFinite(C.chiVpIx(evt));
A.rmsTotalEvent = rmsFinite(C.totalIx(evt));
A.rmsBrinkmanAway = rmsFinite(C.brinkmanIx(away));
A.rmsBathAway = rmsFinite(C.bathIx(away));
A.rmsChiVpAway = rmsFinite(C.chiVpIx(away));
A.rmsTotalAway = rmsFinite(C.totalIx(away));

den = sum(abs(C.brinkmanIx(evt))) + sum(abs(C.bathIx(evt))) + sum(abs(C.chiVpIx(evt)));
if den>0
    A.absShareBrinkmanEvent = sum(abs(C.brinkmanIx(evt)))/den;
    A.absShareBathEvent = sum(abs(C.bathIx(evt)))/den;
    A.absShareChiVpEvent = sum(abs(C.chiVpIx(evt)))/den;
else
    A.absShareBrinkmanEvent = NaN;
    A.absShareBathEvent = NaN;
    A.absShareChiVpEvent = NaN;
end
end

function r = safeCorr(a,b)
a=a(:); b=b(:); q=isfinite(a)&isfinite(b);
a=a(q); b=b(q);
if numel(a)<3 || std(a)==0 || std(b)==0
    r=NaN; return;
end
R=corrcoef(a,b); r=R(1,2);
end

function x = rmsFinite(v)
v=v(isfinite(v));
if isempty(v), x=NaN; else, x=sqrt(mean(v.^2)); end
end

function x = meanFinite(v)
v=v(isfinite(v));
if isempty(v), x=NaN; else, x=mean(v); end
end

function m = circularMean01(p)
p=p(isfinite(p));
if isempty(p), m=NaN; return; end
z=mean(exp(2i*pi*p));
m=mod(angle(z)/(2*pi),1.0);
end

function value = readKvNumber(path,key)
value = str2double(readKvString(path,key));
assert(isfinite(value),'Invalid numeric key %s in %s',key,path);
end

function value = readKvString(path,key)
txt = fileread(path);
expr = ['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok = regexp(txt,expr,'tokens','once');
assert(~isempty(tok),'Missing key %s in %s',key,path);
value = strtrim(tok{1});
end
