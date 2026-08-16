function out = analyze_vk_established_0493x8i(varargin)
%ANALYZE_VK_ESTABLISHED_0493X8I Characterize the established VK wake.
%
% Designed for the 0493x8h restart recording produced from global step 27000.
% Run this function from the repository ./matlab directory.
%
% Default input:
%   ../runs/0493x8h_vk_sat_restart27000_dense/src-q6-g-f/output/recordings/...
%
% Main measurements:
%   - stationarity of upstream flow and symmetry-breaking wake amplitude
%   - two-mode POD of the reflection-symmetry-breaking velocity field
%   - continuous-frequency Strouhal estimate from POD phase rotation
%   - independent common-frequency harmonic fit at downstream uy probes
%   - probe phase progression, wavelength and vortex convection velocity
%   - phase-averaged velocity and vorticity maps (8 phase bins by default)
%
% The analyzer uses only base MATLAB functions. It deliberately avoids a long
% chain of strict asserts: missing optional diagnostics lead to warnings/NaNs;
% only an absent recording directory or an unreadable set of velocity fields is
% fatal.
%
% Typical use from ./matlab:
%   out = analyze_vk_established_0493x8i;
%
% Useful overrides:
%   out = analyze_vk_established_0493x8i( ...
%       'RecordingDir','../runs/.../recordings/session_name', ...
%       'OutputDir','../runs/0493x8i_vk_established_analysis', ...
%       'ShowFigures',true);

p = inputParser;
p.FunctionName = 'analyze_vk_established_0493x8i';
addParameter(p,'RecordingDir', ...
    '../runs/0493x8h_vk_sat_restart27000_dense/src-q6-g-f/output/recordings/0493x8f_q6gf_vk_re65_src-q6-g-f');
addParameter(p,'OutputDir','../runs/0493x8i_vk_established_analysis2');
addParameter(p,'RestartStepOffset',27000);
addParameter(p,'Dt',0.002);
addParameter(p,'URef',0.18);
addParameter(p,'NuRef',6.7432658123431854e-4);
addParameter(p,'CylinderD',0.3125);
addParameter(p,'CylinderCx',0.9375);
addParameter(p,'CylinderCy',0.78125);
addParameter(p,'WakeXRangeD',[0.5 7.0]);
addParameter(p,'WakeYHalfWidthD',2.0);
addParameter(p,'PODStride',2);
addParameter(p,'ProbeXD',[2 3 4 5 6]);
addParameter(p,'ProbeHalfWidthXD',0.05);
addParameter(p,'ProbeHalfWidthYD',0.10);
addParameter(p,'StSearchRange',[0.08 0.30]);
addParameter(p,'UpstreamXRangeD',[-2.5 -1.0]);
addParameter(p,'UpstreamYHalfWidthD',1.5);
addParameter(p,'PhaseBins',8);
addParameter(p,'VorticitySmoothPasses',1);
addParameter(p,'MakePlots',true);
addParameter(p,'ShowFigures',false);
addParameter(p,'MinLocalStep',-inf);
addParameter(p,'MaxLocalStep',inf);
parse(p,varargin{:});
opt = p.Results;

recordDir = char(opt.RecordingDir);
outDir = char(opt.OutputDir);
if ~isfolder(recordDir)
    error('0493x8i:missingRecording','Recording directory not found: %s',recordDir);
end
if ~isfolder(outDir)
    mkdir(outDir);
end

manifestPath = fullfile(recordDir,'manifest.kv');
manifest = struct();
if isfile(manifestPath)
    manifest = local_read_kv_0493x8i(manifestPath);
else
    warning('0493x8i:noManifest','manifest.kv not found; using supplied/default geometry where possible.');
end

nx = round(local_kv_number_0493x8i(manifest,'liveGridNx',600));
ny = round(local_kv_number_0493x8i(manifest,'liveGridNy',200));
Lx = local_kv_number_0493x8i(manifest,'Lx',4.6875);
Ly = local_kv_number_0493x8i(manifest,'Ly',1.5625);
dt = double(opt.Dt);
if isfield(manifest,'dt')
    dt = local_kv_number_0493x8i(manifest,'dt',dt);
end

fprintf('\n===== 0493x8i ESTABLISHED VK ANALYSIS =====\n');
fprintf('recording=%s\n',recordDir);
fprintf('grid=%dx%d L=(%.9g,%.9g) dt=%.9g\n',nx,ny,Lx,Ly,dt);
fprintf('D=%.9g Uref=%.9g restartOffset=%d\n', ...
    double(opt.CylinderD),double(opt.URef),round(double(opt.RestartStepOffset)));
if isfield(manifest,'smoothPasses')
    fprintf('recorded smoothPasses=%s filterMode=%s recordEvery=%s\n', ...
        local_kv_text_0493x8i(manifest,'smoothPasses','?'), ...
        local_kv_text_0493x8i(manifest,'filterMode','?'), ...
        local_kv_text_0493x8i(manifest,'recordEvery','?'));
end

stepsUx = local_list_steps_0493x8i(recordDir,'ux');
stepsUy = local_list_steps_0493x8i(recordDir,'uy');
steps = intersect(stepsUx,stepsUy,'stable');

if isempty(steps)
    error('0493x8i:noFrames','No matching ux/uy .f32 frame pairs found in %s',recordDir);
end
if numel(steps) ~= numel(stepsUx) || numel(steps) ~= numel(stepsUy)
    warning('0493x8i:pairMismatch','Using %d common ux/uy frames (%d ux, %d uy).', ...
        numel(steps),numel(stepsUx),numel(stepsUy));
end

steps = local_keep_complete_frames_0493x8i(recordDir,steps,nx,ny);
minLocalStep = double(opt.MinLocalStep);
maxLocalStep = double(opt.MaxLocalStep);

steps = steps(double(steps) >= minLocalStep & double(steps) <= maxLocalStep);

if numel(steps) < 10
    error('0493x8i:tooFewFrames','Only %d complete ux/uy frame pairs remain.',numel(steps));
elseif numel(steps) < 40
    warning('0493x8i:fewFrames','Only %d complete frames; frequency estimates may be weak.',numel(steps));
end

nFrames = numel(steps);
localTime = double(steps(:))*dt;
globalStep = double(opt.RestartStepOffset) + double(steps(:));
globalTime = globalStep*dt;

fprintf('frames=%d localStep=%d..%d localTime=%.6g..%.6g globalStep=%.0f..%.0f\n', ...
    nFrames,steps(1),steps(end),localTime(1),localTime(end),globalStep(1),globalStep(end));

% -------------------------------------------------------------------------
% Read the complete recorded velocity series once.
% -------------------------------------------------------------------------
Ux = zeros(ny,nx,nFrames,'single');
Uy = zeros(ny,nx,nFrames,'single');
for k = 1:nFrames
    sx = fullfile(recordDir,sprintf('step_%010d_field_ux.f32',steps(k)));
    sy = fullfile(recordDir,sprintf('step_%010d_field_uy.f32',steps(k)));
    Ux(:,:,k) = local_read_f32_field_0493x8i(sx,nx,ny);
    Uy(:,:,k) = local_read_f32_field_0493x8i(sy,nx,ny);
end

if any(~isfinite(Ux(:))) || any(~isfinite(Uy(:)))
    warning('0493x8i:nonfinite','Non-finite values found; they will be replaced by zero for POD/fits.');
    Ux(~isfinite(Ux)) = 0;
    Uy(~isfinite(Uy)) = 0;
end

D = double(opt.CylinderD);
xc = double(opt.CylinderCx);
yc = double(opt.CylinderCy);
Uref = double(opt.URef);
nuRef = double(opt.NuRef);
dx = Lx/nx;
dy = Ly/ny;
x = ((0:nx-1)+0.5)*dx;
y = ((0:ny-1)+0.5)*dy;
[Xg,Yg] = meshgrid(x,y);

mirrorI = local_reflection_indices_0493x8i(y,yc);

wakeXR = sort(double(opt.WakeXRangeD(:).'));
wakeMask = (Xg >= xc + wakeXR(1)*D) & (Xg <= xc + wakeXR(2)*D) & ...
           (abs(Yg-yc) <= double(opt.WakeYHalfWidthD)*D);

stride = max(1,round(double(opt.PODStride)));
strideMask = false(ny,nx);
strideMask(1:stride:end,1:stride:end) = true;
podMask = wakeMask & strideMask;
podIdx = find(podMask);
if numel(podIdx) < 100
    warning('0493x8i:smallPODMask','POD mask has only %d cells; using full wake mask instead.',numel(podIdx));
    podMask = wakeMask;
    podIdx = find(podMask);
end

upXR = sort(double(opt.UpstreamXRangeD(:).'));
upMask = (Xg >= xc + upXR(1)*D) & (Xg <= xc + upXR(2)*D) & ...
         (abs(Yg-yc) <= double(opt.UpstreamYHalfWidthD)*D);
if ~any(upMask(:))
    warning('0493x8i:noUpstreamMask','Upstream mask is empty; using x < xc-D and central 60%% of channel.');
    upMask = (Xg < xc-D) & (Yg > 0.2*Ly) & (Yg < 0.8*Ly);
end

% -------------------------------------------------------------------------
% Symmetry-breaking fields + stationarity series + POD snapshot matrix.
% Reflection convention:
%   ux_break = (ux(y)-ux(y'))/2
%   uy_break = (uy(y)+uy(y'))/2
% -------------------------------------------------------------------------
nPodCells = numel(podIdx);
Xpod = zeros(2*nPodCells,nFrames);
breakRms = nan(nFrames,1);
upstreamU = nan(nFrames,1);
for k = 1:nFrames
    ux = double(Ux(:,:,k));
    uy = double(Uy(:,:,k));
    uxb = 0.5*(ux-ux(mirrorI,:));
    uyb = 0.5*(uy+uy(mirrorI,:));
    vx = uxb(podIdx);
    vy = uyb(podIdx);
    Xpod(1:nPodCells,k) = vx;
    Xpod(nPodCells+1:end,k) = vy;
    breakRms(k) = sqrt(mean([vx;vy].^2))/max(abs(Uref),eps);
    upstreamU(k) = mean(ux(upMask));
end

% -------------------------------------------------------------------------
% Snapshot POD.  We only diagonalize a nFrames x nFrames covariance matrix.
% -------------------------------------------------------------------------
XpodMean = mean(Xpod,2);
Xc = bsxfun(@minus,Xpod,XpodMean);
C = Xc.'*Xc;
C = 0.5*(C+C.');
[V,Deig] = eig(C);
lambda = real(diag(Deig));
[lambda,order] = sort(lambda,'descend');
V = real(V(:,order));
lambda(lambda < 0 & abs(lambda) < max(1,max(lambda))*1e-12) = 0;
lambda(lambda < 0) = 0;

podCapture2 = NaN;
a1 = nan(nFrames,1);
a2 = nan(nFrames,1);
podPhase = nan(nFrames,1);
podEnvelope = nan(nFrames,1);
fPod = NaN;
podPhaseR2 = NaN;
podCycles = NaN;
podPhaseDirection = NaN;
mode1 = nan(ny,nx);
mode2 = nan(ny,nx);

if numel(lambda) >= 2 && lambda(2) > 0
    s1 = sqrt(lambda(1));
    s2 = sqrt(lambda(2));
    a1 = s1*V(:,1);
    a2 = s2*V(:,2);
    totalEnergy = sum(lambda);
    if totalEnergy > 0
        podCapture2 = (lambda(1)+lambda(2))/totalEnergy;
    end

    z1 = a1/max(std(a1),eps);
    z2 = a2/max(std(a2),eps);
    phase0 = unwrap(atan2(z2,z1));
    pp0 = polyfit(localTime,phase0,1);
    podPhaseDirection = sign(pp0(1));
    if podPhaseDirection == 0
        podPhaseDirection = 1;
    end
    podPhase = phase0*podPhaseDirection;
    pp = polyfit(localTime,podPhase,1);
    phaseFit = polyval(pp,localTime);
    podPhaseR2 = local_r2_0493x8i(podPhase,phaseFit);
    fPod = abs(pp(1))/(2*pi);
    podCycles = abs(podPhase(end)-podPhase(1))/(2*pi);
    podEnvelope = hypot(z1,z2);

    u1vec = Xc*V(:,1)/s1;
    u2vec = Xc*V(:,2)/s2;
    m1x = nan(ny,nx); m1y = nan(ny,nx);
    m2x = nan(ny,nx); m2y = nan(ny,nx);
    m1x(podIdx) = u1vec(1:nPodCells);
    m1y(podIdx) = u1vec(nPodCells+1:end);
    m2x(podIdx) = u2vec(1:nPodCells);
    m2y(podIdx) = u2vec(nPodCells+1:end);
    mode1 = hypot(m1x,m1y);
    mode2 = hypot(m2x,m2y);
else
    warning('0493x8i:podRank','POD rank below 2; POD frequency will be unavailable.');
end

% -------------------------------------------------------------------------
% Multi-probe uy symmetry-breaking time series.
% -------------------------------------------------------------------------
probeXD = double(opt.ProbeXD(:));
nProbes = numel(probeXD);
probeXTarget = xc + probeXD*D;
probeXActual = nan(nProbes,1);
Q = nan(nFrames,nProbes);
for j = 1:nProbes
    patch = abs(Xg-probeXTarget(j)) <= double(opt.ProbeHalfWidthXD)*D & ...
            abs(Yg-yc) <= double(opt.ProbeHalfWidthYD)*D;
    if ~any(patch(:))
        [~,ix0] = min(abs(x-probeXTarget(j)));
        [~,iy0] = min(abs(y-yc));
        patch(iy0,ix0) = true;
    end
    probeXActual(j) = mean(Xg(patch));
    for k = 1:nFrames
        uy = double(Uy(:,:,k));
        uyb = 0.5*(uy+uy(mirrorI,:));
        Q(k,j) = mean(uyb(patch));
    end
end

stRange = sort(double(opt.StSearchRange(:).'));
fBounds = stRange*abs(Uref)/D;
if fBounds(1) <= 0
    fBounds(1) = max(1e-8,0.01*abs(Uref)/D);
end
if fBounds(2) <= fBounds(1)
    fBounds(2) = 2*fBounds(1);
end
obj = @(f) local_common_harmonic_loss_0493x8i(localTime,Q,f);
try
    fProbe = fminbnd(obj,fBounds(1),fBounds(2),optimset('Display','off','TolX',1e-9));
catch
    fProbe = mean(fBounds);
    warning('0493x8i:fminbnd','Continuous probe-frequency optimization failed; using midpoint of search range.');
end

probeMean = nan(nProbes,1);
probeAmplitude = nan(nProbes,1);
probePhase = nan(nProbes,1);
probeR2 = nan(nProbes,1);
Qfit = nan(size(Q));
for j = 1:nProbes
    [coef,qfit,r2] = local_harmonic_fit_0493x8i(localTime,Q(:,j),fProbe);
    probeMean(j) = coef(1);
    probeAmplitude(j) = hypot(coef(2),coef(3));
    probePhase(j) = atan2(coef(3),coef(2));
    probeR2(j) = r2;
    Qfit(:,j) = qfit;
end

probePhaseUnwrapped = unwrap(probePhase);
phaseXFit = nan(size(probePhaseUnwrapped));
probePhaseXR2 = NaN;
kWave = NaN;
lambdaWave = NaN;
cVortex = NaN;
if nProbes >= 2 && all(isfinite(probePhaseUnwrapped))
    ppx = polyfit(probeXActual,probePhaseUnwrapped,1);
    phaseXFit = polyval(ppx,probeXActual);
    probePhaseXR2 = local_r2_0493x8i(probePhaseUnwrapped,phaseXFit);
    kWave = abs(ppx(1));
    if kWave > 1e-12
        lambdaWave = 2*pi/kWave;
        cVortex = fProbe*lambdaWave;
    end
end

% -------------------------------------------------------------------------
% Main scalar results.
% -------------------------------------------------------------------------
UupMean = mean(upstreamU(isfinite(upstreamU)));
if isempty(UupMean) || ~isfinite(UupMean)
    UupMean = Uref;
end
UupStd = std(upstreamU(isfinite(upstreamU)));
ReNominal = Uref*D/nuRef;
ReMeasured = UupMean*D/nuRef;
StPodNominal = fPod*D/Uref;
StPodMeasured = fPod*D/UupMean;
StProbeNominal = fProbe*D/Uref;
StProbeMeasured = fProbe*D/UupMean;
periodPod = 1/max(fPod,eps);
periodProbe = 1/max(fProbe,eps);
if ~isfinite(fPod) || fPod <= 0
    periodPod = NaN;
end
if ~isfinite(fProbe) || fProbe <= 0
    periodProbe = NaN;
end
frequencyAgreementRel = NaN;
if isfinite(fPod) && isfinite(fProbe) && (fPod+fProbe) > 0
    frequencyAgreementRel = abs(fPod-fProbe)/(0.5*(fPod+fProbe));
end

[firstBreak,midBreak,lastBreak] = local_thirds_0493x8i(breakRms);
[firstU,midU,lastU] = local_thirds_0493x8i(upstreamU);
podEnvelopeCV = std(podEnvelope(isfinite(podEnvelope)))/max(mean(podEnvelope(isfinite(podEnvelope))),eps);
probeR2Mean = mean(probeR2(isfinite(probeR2)));

% -------------------------------------------------------------------------
% Phase averaging. Prefer the POD phase; fall back to probe-fit clock.
% -------------------------------------------------------------------------
phaseSource = "POD";
phaseForBins = podPhase;
if ~all(isfinite(phaseForBins)) || ~isfinite(fPod)
    phaseSource = "probe_harmonic";
    phaseForBins = 2*pi*fProbe*(localTime-localTime(1));
end

nBins = max(4,round(double(opt.PhaseBins)));
phaseWrapped = mod(phaseForBins,2*pi);
phaseBin = floor(phaseWrapped/(2*pi/nBins))+1;
phaseBin(phaseBin > nBins) = nBins;
phaseCounts = zeros(nBins,1);
phaseUx = nan(ny,nx,nBins,'single');
phaseUy = nan(ny,nx,nBins,'single');
for b = 1:nBins
    kb = find(phaseBin == b);
    phaseCounts(b) = numel(kb);
    if isempty(kb)
        continue;
    end
    phaseUx(:,:,b) = mean(Ux(:,:,kb),3);
    phaseUy(:,:,b) = mean(Uy(:,:,kb),3);
end

solidMask = (Xg-xc).^2 + (Yg-yc).^2 <= (0.5*D).^2;
passesMain = max(0,round(double(opt.VorticitySmoothPasses)));
omegaRaw = nan(ny,nx,nBins,'single');
omegaMain = nan(ny,nx,nBins,'single');
omegaTwo = nan(ny,nx,nBins,'single');
for b = 1:nBins
    if phaseCounts(b) == 0
        continue;
    end
    ux0 = double(phaseUx(:,:,b));
    uy0 = double(phaseUy(:,:,b));
    om0 = local_vorticity_0493x8i(ux0,uy0,dx,dy);
    ux1 = local_smooth_binomial_0493x8i(ux0,passesMain);
    uy1 = local_smooth_binomial_0493x8i(uy0,passesMain);
    om1 = local_vorticity_0493x8i(ux1,uy1,dx,dy);
    ux2 = local_smooth_binomial_0493x8i(ux0,2);
    uy2 = local_smooth_binomial_0493x8i(uy0,2);
    om2 = local_vorticity_0493x8i(ux2,uy2,dx,dy);
    om0(solidMask) = NaN;
    om1(solidMask) = NaN;
    om2(solidMask) = NaN;
    omegaRaw(:,:,b) = single(om0*D/UupMean);
    omegaMain(:,:,b) = single(om1*D/UupMean);
    omegaTwo(:,:,b) = single(om2*D/UupMean);
end

% Sensitivity of phase-averaged vorticity to spatial smoothing.
vortPasses = [0 passesMain 2].';
vortRms = nan(3,1);
vortCorrVsRaw = nan(3,1);
for r = 1:3
    if r == 1
        OO = omegaRaw;
    elseif r == 2
        OO = omegaMain;
    else
        OO = omegaTwo;
    end
    vals = [];
    rawVals = [];
    for b = 1:nBins
        o = double(OO(:,:,b));
        o0 = double(omegaRaw(:,:,b));
        m = wakeMask & isfinite(o) & isfinite(o0);
        vals = [vals; o(m)]; %#ok<AGROW>
        rawVals = [rawVals; o0(m)]; %#ok<AGROW>
    end
    if ~isempty(vals)
        vortRms(r) = sqrt(mean(vals.^2));
        vortCorrVsRaw(r) = local_corr_0493x8i(vals,rawVals);
    end
end

% Mean and fluctuation fields for later inspection.
meanUx = mean(Ux,3);
meanUy = mean(Uy,3);
fluctRms = zeros(ny,nx,'single');
for k = 1:nFrames
    du = Ux(:,:,k)-meanUx;
    dv = Uy(:,:,k)-meanUy;
    fluctRms = fluctRms + du.^2 + dv.^2;
end
fluctRms = sqrt(fluctRms/max(nFrames,1));

% -------------------------------------------------------------------------
% Tables and MAT output.
% -------------------------------------------------------------------------
manifestSmoothPasses = local_kv_number_0493x8i(manifest,'smoothPasses',NaN);
manifestRecordEvery = local_kv_number_0493x8i(manifest,'recordEvery',NaN);
manifestFilterMode = string(local_kv_text_0493x8i(manifest,'filterMode','unknown'));

summary = table( ...
    nFrames,steps(1),steps(end),localTime(1),localTime(end), ...
    Uref,UupMean,UupStd,nuRef,ReNominal,ReMeasured,D,Lx,Ly,nx,ny, ...
    manifestSmoothPasses,manifestRecordEvery,manifestFilterMode, ...
    firstU,midU,lastU,firstBreak,midBreak,lastBreak, ...
    podCapture2,podEnvelopeCV,fPod,StPodNominal,StPodMeasured,podPhaseR2,podCycles, ...
    fProbe,StProbeNominal,StProbeMeasured,probeR2Mean,frequencyAgreementRel, ...
    kWave,lambdaWave,lambdaWave/D,cVortex,cVortex/UupMean,probePhaseXR2, ...
    string(phaseSource),nBins,min(phaseCounts),max(phaseCounts), ...
    'VariableNames',{ ...
    'frames','localStepFirst','localStepLast','localTimeFirst','localTimeLast', ...
    'Uref','UupMean','UupStd','nuRef','ReNominal','ReMeasured','D','Lx','Ly','Nx','Ny', ...
    'recordedSmoothPasses','recordEvery','filterMode', ...
    'UupFirstThird','UupMiddleThird','UupLastThird', ...
    'breakRmsFirstThird','breakRmsMiddleThird','breakRmsLastThird', ...
    'podPairCapture','podEnvelopeCV','fPod','StPodNominal','StPodMeasured','podPhaseR2','podCycles', ...
    'fProbe','StProbeNominal','StProbeMeasured','probeR2Mean','frequencyAgreementRel', ...
    'waveNumber','lambda','lambdaOverD','vortexConvectionSpeed','vortexConvectionOverUup','probePhaseXR2', ...
    'phaseSource','phaseBins','phaseBinMinCount','phaseBinMaxCount'});

frameTable = table(double(steps(:)),globalStep,localTime,globalTime,upstreamU,breakRms,a1,a2,podEnvelope,podPhase,phaseWrapped,phaseBin, ...
    'VariableNames',{'localStep','globalStep','localTime','globalTime','Uupstream','breakRmsOverUref', ...
    'podA1','podA2','podEnvelopeNormalized','podPhase','phaseWrapped','phaseBin'});

probeTable = table(probeXD,probeXTarget,probeXActual,(probeXActual-xc)/D, ...
    probeMean,probeAmplitude,probePhase,probePhaseUnwrapped,phaseXFit,probeR2, ...
    'VariableNames',{'targetXD','xTarget','xActual','xActualD','meanUy','amplitudeUy','phase','phaseUnwrapped','phaseFit','fitR2'});

phaseTable = table((1:nBins).',phaseCounts,((0:nBins-1).'+0.5)*(2*pi/nBins), ...
    'VariableNames',{'phaseBin','frameCount','phaseCenterRad'});

vortTable = table(vortPasses,vortRms,vortCorrVsRaw, ...
    'VariableNames',{'velocitySmoothPasses','omegaRmsDoverU','correlationVsRaw'});

writetable(summary,fullfile(outDir,'vk_established_summary_0493x8i.csv'));
writetable(frameTable,fullfile(outDir,'vk_established_timeseries_0493x8i.csv'));
writetable(probeTable,fullfile(outDir,'vk_established_probe_fit_0493x8i.csv'));
writetable(phaseTable,fullfile(outDir,'vk_established_phase_bins_0493x8i.csv'));
writetable(vortTable,fullfile(outDir,'vk_established_vorticity_sensitivity_0493x8i.csv'));

save(fullfile(outDir,'vk_established_fields_0493x8i.mat'), ...
    'x','y','meanUx','meanUy','fluctRms','phaseUx','phaseUy','omegaRaw','omegaMain','omegaTwo', ...
    'wakeMask','solidMask','mode1','mode2','probeXD','probeXActual','Q','Qfit','phaseCounts', ...
    'summary','-v7.3');

% -------------------------------------------------------------------------
% Figures.
% -------------------------------------------------------------------------
plotFiles = strings(0,1);
if logical(opt.MakePlots)
    vis = 'off';
    if logical(opt.ShowFigures)
        vis = 'on';
    end

    % 1) Stationarity + POD cycle.
    f1 = figure('Visible',vis,'Color','w','Name','0493x8i established VK POD');
    tl = tiledlayout(f1,2,2,'Padding','compact','TileSpacing','compact'); %#ok<NASGU>
    nexttile;
    plot(localTime,upstreamU,'-','LineWidth',1.1); hold on;
    yline(UupMean,'--'); grid on;
    xlabel('restart time'); ylabel('U_{up}'); title('Upstream velocity');
    nexttile;
    plot(localTime,breakRms,'-','LineWidth',1.1); grid on;
    xlabel('restart time'); ylabel('A_{break}/U_{ref}'); title('Wake symmetry-breaking RMS');
    nexttile;
    plot(localTime,a1,'-','LineWidth',1.0); hold on;
    plot(localTime,a2,'-','LineWidth',1.0); grid on;
    xlabel('restart time'); ylabel('POD coefficient'); legend({'a_1','a_2'},'Location','best');
    title(sprintf('POD pair capture %.3f',podCapture2));
    nexttile;
    plot(a1,a2,'-o','MarkerSize',3,'LineWidth',1.0); axis equal; grid on;
    xlabel('a_1'); ylabel('a_2'); title(sprintf('phase plane, St_{POD}=%.4f',StPodMeasured));
    sgtitle(sprintf('Q6GF established VK | POD phase R^2=%.4f | cycles=%.2f',podPhaseR2,podCycles));
    plotFiles(end+1,1) = string(local_export_figure_0493x8i(f1,fullfile(outDir,'vk_established_pod_0493x8i'))); %#ok<AGROW>

    % 2) Probe signals and common-frequency harmonic fit.
    f2 = figure('Visible',vis,'Color','w','Name','0493x8i VK probes');
    tiledlayout(f2,nProbes,1,'Padding','compact','TileSpacing','compact');
    for j = 1:nProbes
        nexttile;
        plot(localTime,Q(:,j),'-','LineWidth',0.8); hold on;
        plot(localTime,Qfit(:,j),'-','LineWidth',1.4); grid on;
        ylabel(sprintf('u_y @ %.0fD',probeXD(j)));
        if j == 1
            title(sprintf('common f=%.6g, St=%.5f',fProbe,StProbeMeasured));
        end
        if j == nProbes
            xlabel('restart time');
        end
    end
    plotFiles(end+1,1) = string(local_export_figure_0493x8i(f2,fullfile(outDir,'vk_established_probes_0493x8i'))); %#ok<AGROW>

    % 3) Probe phase progression.
    f3 = figure('Visible',vis,'Color','w','Name','0493x8i VK phase progression');
    plot((probeXActual-xc)/D,probePhaseUnwrapped,'o-','LineWidth',1.1); hold on;
    plot((probeXActual-xc)/D,phaseXFit,'--','LineWidth',1.4); grid on;
    xlabel('(x-x_c)/D'); ylabel('harmonic phase [rad]');
    title(sprintf('lambda/D=%.4g, c_v/U=%.4g, R^2=%.4f',lambdaWave/D,cVortex/UupMean,probePhaseXR2));
    plotFiles(end+1,1) = string(local_export_figure_0493x8i(f3,fullfile(outDir,'vk_established_probe_phase_0493x8i'))); %#ok<AGROW>

    % 4) Phase-averaged dimensionless vorticity.
    f4 = figure('Visible',vis,'Color','w','Name','0493x8i phase averaged vorticity');
    ncol = ceil(nBins/2);
    tiledlayout(f4,2,ncol,'Padding','compact','TileSpacing','compact');
    allOmega = double(omegaMain(repmat(wakeMask,1,1,nBins) & isfinite(omegaMain)));
    if isempty(allOmega)
        clim = 1;
    else
        clim = local_percentile_0493x8i(abs(allOmega),98);
        if ~isfinite(clim) || clim <= 0
            clim = max(abs(allOmega));
        end
        if ~isfinite(clim) || clim <= 0
            clim = 1;
        end
    end
    for b = 1:nBins
        nexttile;
        imagesc(x,y,double(omegaMain(:,:,b))); axis image xy;
        xlim([max(0,xc-0.75*D) min(Lx,xc+7.5*D)]);
        ylim([0 Ly]); caxis([-clim clim]);
        title(sprintf('phase %d/%d, n=%d',b,nBins,phaseCounts(b)));
        if b > ncol
            xlabel('x');
        end
        ylabel('y');
    end
    colormap(f4,local_blue_white_red_0493x8i(256));
    cb = colorbar; cb.Layout.Tile = 'east'; cb.Label.String = '\omega_z D/U_{up}';
    sgtitle(sprintf('Phase-averaged vorticity | velocity smoothing passes=%d',passesMain));
    plotFiles(end+1,1) = string(local_export_figure_0493x8i(f4,fullfile(outDir,'vk_established_phase_vorticity_0493x8i'))); %#ok<AGROW>

    % 5) Mean and fluctuation fields.
    f5 = figure('Visible',vis,'Color','w','Name','0493x8i mean/rms');
    tiledlayout(f5,1,3,'Padding','compact','TileSpacing','compact');
    nexttile; imagesc(x,y,double(meanUx)/UupMean); axis image xy; colorbar; title('<u_x>/U_{up}'); xlabel('x'); ylabel('y');
    nexttile; imagesc(x,y,double(meanUy)/UupMean); axis image xy; colorbar; title('<u_y>/U_{up}'); xlabel('x'); ylabel('y');
    nexttile; imagesc(x,y,double(fluctRms)/UupMean); axis image xy; colorbar; title('u''_{rms}/U_{up}'); xlabel('x'); ylabel('y');
    colormap(f5,'turbo');
    plotFiles(end+1,1) = string(local_export_figure_0493x8i(f5,fullfile(outDir,'vk_established_mean_rms_0493x8i'))); %#ok<AGROW>
end

out = struct();
out.summary = summary;
out.timeseries = frameTable;
out.probeFit = probeTable;
out.phaseBins = phaseTable;
out.vorticitySensitivity = vortTable;
out.outputDir = string(outDir);
out.plotFiles = plotFiles;
out.recordingDir = string(recordDir);

fprintf('\n===== 0493x8i RESULTS =====\n');
fprintf('Uup=%.8g +/- %.3g | Re(measured)=%.5g\n',UupMean,UupStd,ReMeasured);
fprintf('POD:   f=%.8g St(measured)=%.6g phaseR2=%.5f cycles=%.3f pairCapture=%.4f\n', ...
    fPod,StPodMeasured,podPhaseR2,podCycles,podCapture2);
fprintf('PROBE: f=%.8g St(measured)=%.6g meanR2=%.5f\n', ...
    fProbe,StProbeMeasured,probeR2Mean);
fprintf('agreement |df|/fmean=%.4g\n',frequencyAgreementRel);
fprintf('lambda/D=%.6g c_v/Uup=%.6g phaseX_R2=%.5f\n', ...
    lambdaWave/D,cVortex/UupMean,probePhaseXR2);
fprintf('phase bins source=%s counts=%d..%d\n',char(phaseSource),min(phaseCounts),max(phaseCounts));
fprintf('summary=%s\n',fullfile(outDir,'vk_established_summary_0493x8i.csv'));
fprintf('timeseries=%s\n',fullfile(outDir,'vk_established_timeseries_0493x8i.csv'));
fprintf('probeFit=%s\n',fullfile(outDir,'vk_established_probe_fit_0493x8i.csv'));
fprintf('fields=%s\n',fullfile(outDir,'vk_established_fields_0493x8i.mat'));
fprintf('status=COMPLETE\n');
end

% =========================================================================
function kv = local_read_kv_0493x8i(path)
kv = struct();
fid = fopen(path,'r');
if fid < 0
    return;
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
while true
    line = fgetl(fid);
    if ~ischar(line)
        break;
    end
    line = strtrim(line);
    if isempty(line) || startsWith(line,'#')
        continue;
    end
    eq = strfind(line,'=');
    if isempty(eq)
        continue;
    end
    key = strtrim(line(1:eq(1)-1));
    val = strtrim(line(eq(1)+1:end));
    key = matlab.lang.makeValidName(key);
    kv.(key) = val;
end
end

function v = local_kv_number_0493x8i(kv,key,defaultValue)
v = defaultValue;
if ~isstruct(kv) || ~isfield(kv,key)
    return;
end
x = str2double(kv.(key));
if isfinite(x)
    v = x;
end
end

function s = local_kv_text_0493x8i(kv,key,defaultValue)
s = defaultValue;
if isstruct(kv) && isfield(kv,key)
    s = char(kv.(key));
end
end

function steps = local_list_steps_0493x8i(recordDir,fieldName)
D = dir(fullfile(recordDir,sprintf('step_*_field_%s.f32',fieldName)));
steps = zeros(numel(D),1);
n = 0;
for i = 1:numel(D)
    tok = regexp(D(i).name,'^step_(\d+)_field_','tokens','once');
    if isempty(tok)
        continue;
    end
    n = n+1;
    steps(n) = str2double(tok{1});
end
steps = steps(1:n);
steps = unique(sort(steps));
end

function steps = local_keep_complete_frames_0493x8i(recordDir,steps,nx,ny)
expectedBytes = nx*ny*4;
keep = true(size(steps));
for i = 1:numel(steps)
    fx = fullfile(recordDir,sprintf('step_%010d_field_ux.f32',steps(i)));
    fy = fullfile(recordDir,sprintf('step_%010d_field_uy.f32',steps(i)));
    dx = dir(fx);
    dy = dir(fy);
    if isempty(dx) || isempty(dy) || dx(1).bytes ~= expectedBytes || dy(1).bytes ~= expectedBytes
        keep(i) = false;
    end
end
nBad = nnz(~keep);
if nBad > 0
    warning('0493x8i:incompleteFrames','Ignoring %d incomplete frame pairs.',nBad);
end
steps = steps(keep);
end

function F = local_read_f32_field_0493x8i(path,nx,ny)
fid = fopen(path,'rb');
if fid < 0
    error('0493x8i:openField','Cannot open %s',path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
v = fread(fid,nx*ny,'single=>single');
if numel(v) ~= nx*ny
    error('0493x8i:shortField','Unexpected field size in %s',path);
end
% Recorder manifest says row_major, with x varying fastest (iy*Nx+ix).
F = reshape(v,[nx ny]).';
end

function mirrorI = local_reflection_indices_0493x8i(y,y0)
ny = numel(y);
mirrorI = zeros(ny,1);
for i = 1:ny
    yr = 2*y0-y(i);
    [~,j] = min(abs(y-yr));
    mirrorI(i) = j;
end
end

function [a,b,c] = local_thirds_0493x8i(v)
n = numel(v);
i1 = max(1,floor(n/3));
i2 = max(i1+1,floor(2*n/3));
a = local_meanfinite_0493x8i(v(1:i1));
b = local_meanfinite_0493x8i(v(i1+1:i2));
c = local_meanfinite_0493x8i(v(i2+1:end));
end

function m = local_meanfinite_0493x8i(v)
v = v(isfinite(v));
if isempty(v)
    m = NaN;
else
    m = mean(v);
end
end

function r2 = local_r2_0493x8i(y,yhat)
m = isfinite(y) & isfinite(yhat);
y = y(m); yhat = yhat(m);
if numel(y) < 2
    r2 = NaN;
    return;
end
ssr = sum((y-yhat).^2);
sst = sum((y-mean(y)).^2);
if sst <= eps
    r2 = NaN;
else
    r2 = 1-ssr/sst;
end
end

function loss = local_common_harmonic_loss_0493x8i(t,Q,f)
loss = 0;
nUsed = 0;
for j = 1:size(Q,2)
    q = Q(:,j);
    m = isfinite(t) & isfinite(q);
    if nnz(m) < 6
        continue;
    end
    tt = t(m); qq = q(m);
    A = [ones(size(tt)) cos(2*pi*f*tt) sin(2*pi*f*tt)];
    coef = A\qq;
    res = qq-A*coef;
    sst = sum((qq-mean(qq)).^2);
    if sst > eps
        loss = loss + sum(res.^2)/sst;
        nUsed = nUsed+1;
    end
end
if nUsed == 0
    loss = realmax;
else
    loss = loss/nUsed;
end
end

function [coef,qfit,r2] = local_harmonic_fit_0493x8i(t,q,f)
coef = [NaN;NaN;NaN];
qfit = nan(size(q));
r2 = NaN;
m = isfinite(t) & isfinite(q);
if nnz(m) < 4
    return;
end
tt = t(m); qq = q(m);
A = [ones(size(tt)) cos(2*pi*f*tt) sin(2*pi*f*tt)];
coef = A\qq;
qfit(m) = A*coef;
r2 = local_r2_0493x8i(qq,qfit(m));
end

function om = local_vorticity_0493x8i(ux,uy,dx,dy)
[dUy_dx,~] = gradient(uy,dx,dy);
[~,dUx_dy] = gradient(ux,dx,dy);
om = dUy_dx-dUx_dy;
end

function A = local_smooth_binomial_0493x8i(A,passes)
passes = max(0,round(passes));
if passes == 0
    return;
end
K = [1 2 1;2 4 2;1 2 1]/16;
for i = 1:passes
    finiteMask = isfinite(A);
    B = A;
    B(~finiteMask) = 0;
    num = conv2(B,K,'same');
    den = conv2(double(finiteMask),K,'same');
    good = den > 0;
    C = A;
    C(good) = num(good)./den(good);
    A = C;
end
end

function r = local_corr_0493x8i(a,b)
m = isfinite(a) & isfinite(b);
a = a(m); b = b(m);
if numel(a) < 3
    r = NaN;
    return;
end
a = a-mean(a); b = b-mean(b);
den = sqrt(sum(a.^2)*sum(b.^2));
if den <= eps
    r = NaN;
else
    r = sum(a.*b)/den;
end
end

function q = local_percentile_0493x8i(v,pct)
v = sort(v(isfinite(v)));
if isempty(v)
    q = NaN;
    return;
end
pct = min(max(pct,0),100);
pos = 1+(numel(v)-1)*pct/100;
i0 = floor(pos); i1 = ceil(pos);
if i0 == i1
    q = v(i0);
else
    w = pos-i0;
    q = (1-w)*v(i0)+w*v(i1);
end
end

function cmap = local_blue_white_red_0493x8i(n)
if nargin < 1
    n = 256;
end
n1 = floor(n/2);
n2 = n-n1;
blue = [0.1 0.2 0.8];
white = [1 1 1];
red = [0.8 0.1 0.1];
a = linspace(0,1,n1).';
b = linspace(0,1,n2).';
c1 = blue.*(1-a)+white.*a;
c2 = white.*(1-b)+red.*b;
cmap = [c1;c2];
end

function pathOut = local_export_figure_0493x8i(fig,basePath)
pngPath = [basePath '.png'];
try
    exportgraphics(fig,pngPath,'Resolution',180);
catch
    print(fig,pngPath,'-dpng','-r180');
end
pathOut = pngPath;
end
