function results = analyze_0493x14aj_n3_two_phase_jcp(runsRoot, seeds)
%ANALYZE_0493X14AJ_N3_TWO_PHASE_JCP  JCP qualification of the n=3 two-phase drop.
%
% Usage from repository matlab/ directory:
%   analyze_0493x14aj_n3_two_phase_jcp('../runs')
%   analyze_0493x14aj_n3_two_phase_jcp('../runs',[493180 493181 493182])
%
% The analysis deliberately separates:
%   (i) the physical frequency test against the 2-D inviscid two-fluid law,
%       omega_n^2 = n(n^2-1)sigma / ((rhoL+rhoG) R^3), n=3;
%   (ii) numerical/thermal resolvability of the mode.
%
% Thermal-noise safeguards are not physical acceptance criteria.  They prevent
% a frequency fit from being interpreted when the coherent n=3 signal is no
% longer resolved above stochastic fluctuations.  In particular we report:
%   - fit residual SNR,
%   - quadrature leakage/noise,
%   - late-envelope SNR,
%   - frequency stability over 1.5, 2.0 and 2.5 theoretical periods,
%   - inter-seed dispersion,
%   - a global peculiar-energy kBT proxy for each phase.
%
% No toolbox is required.  State files are read directly; the liquid is selected
% by type=1 and role=fluid.  The full two-phase dumps remain untouched.

if nargin < 1 || isempty(runsRoot)
    runsRoot = '../runs';
end
if nargin < 2 || isempty(seeds)
    d = dir(fullfile(runsRoot,'0493x14aj_n3_two_phase_jcp_seed*'));
    seeds = [];
    for k = 1:numel(d)
        tok = regexp(d(k).name,'seed(\d+)$','tokens','once');
        if ~isempty(tok)
            seeds(end+1) = str2double(tok{1}); %#ok<AGROW>
        end
    end
    seeds = sort(unique(seeds));
end
if isempty(seeds)
    error('0493x14aj-JCP: no run directories found under %s', runsRoot);
end

% Frozen qualification point.  Keep these values synchronized with the runner.
p.n = 3;
p.h = 1/256;
p.Rcells = 40;
p.R = p.Rcells*p.h;
p.gamma = 20;
p.mL = 1.0;
p.mG = 0.1;
p.kBTL = 0.02;
p.kBTG = 0.08;
p.sigma = 2560.0;
p.epsilon = 0.04;
p.phase = 0.0;
p.dt = 0.002;
p.rhoL = p.gamma*p.mL/p.h^2;
p.rhoG = p.gamma*p.mG/p.h^2;
p.omegaTheory = sqrt(p.n*(p.n^2-1)*p.sigma/((p.rhoL+p.rhoG)*p.R^3));
p.periodTheory = 2*pi/p.omegaTheory;
p.nuFitScale = 5.1e-4; % numerical search scale only, not a two-fluid damping law
p.betaScale = 2*p.n*(p.n-1)*p.nuFitScale/p.R^2;

fprintf('\n===== 0493x14aj JCP / two-phase oscillating drop n=3 =====\n');
fprintf('rhoL=%.12g rhoG=%.12g rhoG/rhoL=%.6g\n',p.rhoL,p.rhoG,p.rhoG/p.rhoL);
fprintf('R=%.12g R/h=%g sigma=%g epsilon=%g\n',p.R,p.Rcells,p.sigma,p.epsilon);
fprintf('omega_theory=%.12g T_theory=%.12g steps/T=%.3f\n',p.omegaTheory,p.periodTheory,p.periodTheory/p.dt);
fprintf('thermal point: gamma=%g, kBT_L=%g, kBT_G=%g\n',p.gamma,p.kBTL,p.kBTG);

runs = repmat(emptyResult(),0,1);
for ks = 1:numel(seeds)
    seed = seeds(ks);
    runRoot = fullfile(runsRoot,sprintf('0493x14aj_n3_two_phase_jcp_seed%d',seed));
    if ~isfolder(runRoot)
        warning('0493x14aj-JCP: missing run %s; skipped',runRoot);
        continue;
    end
    r = analyzeOne(runRoot,seed,p);
    runs(end+1,1) = r; %#ok<AGROW>
end
if isempty(runs)
    error('0493x14aj-JCP: no usable run analyzed');
end

outDir = fullfile(runsRoot,'0493x14aj_n3_two_phase_jcp_analysis');
if ~isfolder(outDir), mkdir(outDir); end

% Ensemble table.
T = struct2table(rmfield(runs,{'traceTime','traceQ3'}));
writetable(T,fullfile(outDir,'ensemble_n3_two_phase_summary.csv'));

G = [runs.Gomega];
omega = [runs.omega];
beta = [runs.beta];
r2 = [runs.R2];
snr = [runs.snrResidual];
late = [runs.snrLateEnvelope];
wspread = [runs.windowSpreadRel];
qleak = [runs.quadratureOverAmplitude];
kL = [runs.kBTLiquidProxyMean];
kG = [runs.kBTGasProxyMean];

ens = struct();
ens.seeds = [runs.seed];
ens.n = p.n;
ens.rhoLiquid = p.rhoL;
ens.rhoGas = p.rhoG;
ens.rhoGasOverLiquid = p.rhoG/p.rhoL;
ens.radius = p.R;
ens.sigma = p.sigma;
ens.epsilon = p.epsilon;
ens.kBTLiquidTarget = p.kBTL;
ens.kBTGasTarget = p.kBTG;
ens.omegaTheory = p.omegaTheory;
ens.periodTheory = p.periodTheory;
ens.omegaMean = mean(omega);
ens.omegaStd = sampleStd(omega);
ens.GomegaMean = mean(G);
ens.GomegaStd = sampleStd(G);
ens.betaMean = mean(beta);
ens.betaStd = sampleStd(beta);
ens.R2Min = min(r2);
ens.snrResidualMin = min(snr);
ens.snrLateEnvelopeMin = min(late);
ens.windowSpreadRelMax = max(wspread);
ens.quadratureOverAmplitudeMax = max(qleak);
ens.kBTLiquidProxyMean = mean(kL,'omitnan');
ens.kBTGasProxyMean = mean(kG,'omitnan');
ens.thermalResolutionAllSeeds = all([runs.thermalResolutionOK]);
ens.note = ['thermalResolutionAllSeeds is a signal-resolution guard only; ', ...
            'physical accuracy is assessed separately from Gomega and its inter-seed spread.'];

writeJson(fullfile(outDir,'ensemble_n3_two_phase_summary.json'),ens);

fid = fopen(fullfile(outDir,'ensemble_n3_two_phase_report.txt'),'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'===== 0493x14aj JCP TWO-PHASE OSCILLATING DROP n=3 =====\n');
fprintf(fid,'seeds=%s\n',mat2str(ens.seeds));
fprintf(fid,'thermalPoint gamma=%g kBT_L=%g kBT_G=%g epsilon=%g\n',p.gamma,p.kBTL,p.kBTG,p.epsilon);
fprintf(fid,'theory omega=%.12g period=%.12g\n',p.omegaTheory,p.periodTheory);
fprintf(fid,'ensemble omega=%.12g +/- %.5g\n',ens.omegaMean,ens.omegaStd);
fprintf(fid,'ensemble Gomega=%.9g +/- %.5g\n',ens.GomegaMean,ens.GomegaStd);
fprintf(fid,'ensemble beta=%.9g +/- %.5g\n',ens.betaMean,ens.betaStd);
fprintf(fid,'quality R2min=%.6g residualSNRmin=%.6g lateEnvelopeSNRmin=%.6g\n',ens.R2Min,ens.snrResidualMin,ens.snrLateEnvelopeMin);
fprintf(fid,'quality windowSpreadMax=%.6g quadratureOverAmplitudeMax=%.6g\n',ens.windowSpreadRelMax,ens.quadratureOverAmplitudeMax);
fprintf(fid,'temperatureProxy meanLiquid=%.9g target=%.9g meanGas=%.9g target=%.9g\n',ens.kBTLiquidProxyMean,p.kBTL,ens.kBTGasProxyMean,p.kBTG);
fprintf(fid,'thermalResolutionAllSeeds=%d\n',ens.thermalResolutionAllSeeds);
fprintf(fid,'IMPORTANT: thermalResolution is only a resolvability guard; it is not a criterion that Gomega must equal one.\n');
clear cleanup

% Publication-oriented plots.
fig = figure('Visible','off'); hold on; box on;
for k = 1:numel(runs)
    plot(runs(k).traceTime/p.periodTheory,runs(k).traceQ3,'DisplayName',sprintf('seed %d',runs(k).seed));
end
xlabel('t/T_3^{th}'); ylabel('q_3');
title('Two-phase n=3 modal response'); legend('Location','best');
exportgraphics(fig,fullfile(outDir,'n3_two_phase_q3_ensemble.png'),'Resolution',180);
close(fig);

fig = figure('Visible','off'); box on;
errorbar(1,ens.GomegaMean,ens.GomegaStd,'o','LineWidth',1.2); hold on;
yline(1,'--'); xlim([0.5 1.5]); xticks(1); xticklabels({'n=3'});
ylabel('\omega_{num}/\omega_{2-fluid}');
title('Two-phase n=3 frequency gain');
exportgraphics(fig,fullfile(outDir,'n3_two_phase_frequency_gain.png'),'Resolution',180);
close(fig);

results = struct('runs',runs,'ensemble',ens,'outputDir',outDir);
fprintf('\n[0493x14aj-JCP] ensemble Gomega = %.6f +/- %.6f (1 SD, %d seeds)\n',ens.GomegaMean,ens.GomegaStd,numel(runs));
fprintf('[0493x14aj-JCP] thermal-resolution guard all seeds = %d\n',ens.thermalResolutionAllSeeds);
fprintf('[0493x14aj-JCP] outputs: %s\n',outDir);
end

function r = analyzeOne(runRoot,seed,p)
out = fullfile(runRoot,'output');
files = dir(fullfile(out,'state_step_*.smpcd'));
if numel(files) < 20
    error('0493x14aj-JCP seed %d: need >=20 state dumps, got %d',seed,numel(files));
end
steps = zeros(numel(files),1);
for k=1:numel(files)
    tok = regexp(files(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    steps(k)=str2double(tok{1});
end
[steps,ord]=sort(steps); files=files(ord);

q = zeros(numel(files),1); qq = zeros(numel(files),1);
xc = zeros(numel(files),1); yc = zeros(numel(files),1);
kL = nan(numel(files),1); kG = nan(numel(files),1);
ML = zeros(numel(files),1); MG = zeros(numel(files),1);
Px = zeros(numel(files),1); Py = zeros(numel(files),1);
for k=1:numel(files)
    s = readState(fullfile(files(k).folder,files(k).name));
    [q(k),qq(k),xc(k),yc(k),kL(k),ML(k),pxL,pyL] = phaseMetrics(s,1,p.R,p.phase,p.n);
    [~,~,~,~,kG(k),MG(k),pxG,pyG] = phaseMetrics(s,2,p.R,p.phase,p.n);
    Px(k)=pxL+pxG; Py(k)=pyL+pyG;
end
time = steps*p.dt;

% Fit three windows to expose late-time thermal contamination.
windows = [1.5 2.0 2.5];
fits = cell(numel(windows),1);
for j=1:numel(windows)
    mask = time <= time(1)+windows(j)*p.periodTheory+1e-12;
    fj = dampedFit(time(mask),q(mask),p.omegaTheory,p.betaScale);
    fj.periods = windows(j);
    fits{j} = fj;
end
f = fits{end};
mask = time <= time(1)+2.5*p.periodTheory+1e-12;
tf = time(mask); yf = q(mask); qf = qq(mask);

A0 = hypot(f.C,f.D);
res = yf-f.pred;
resRms = sqrt(mean(res.^2));
qQuadRms = sqrt(mean(qf.^2));
snrResidual = safeRatio(A0,resRms);
snrQuad = safeRatio(A0,qQuadRms);
lateAmp = A0*exp(-max(f.beta,0)*(tf(end)-tf(1)));
snrLate = safeRatio(lateAmp,resRms);
quadOverAmp = safeRatio(qQuadRms,A0);
omegas = cellfun(@(fj) fj.omega, fits);
windowSpreadRel = (max(omegas)-min(omegas))/mean(omegas);
[omegaZC,nCross] = zeroCrossOmega(tf,yf,f.offset);

% Global peculiar-energy temperature proxy.  It includes any unresolved
% coherent phase motion and is therefore interpreted as an upper-biased audit,
% not as the exact shifted-cell thermostat diagnostic.
kLmean = mean(kL(mask),'omitnan');
kGmean = mean(kG(mask),'omitnan');

% Signal-resolution guardrails.  These thresholds are deliberately separate
% from the physical frequency accuracy criterion.
thermalResolutionOK = ...
    f.R2 >= 0.98 && ...
    snrResidual >= 5.0 && ...
    snrLate >= 3.0 && ...
    quadOverAmp <= 0.35 && ...
    windowSpreadRel <= 0.03 && ...
    abs(kLmean/p.kBTL-1) <= 0.20 && ...
    abs(kGmean/p.kBTG-1) <= 0.20;

% Total-momentum drift from state dumps.
P0 = [Px(1) Py(1)];
Pdrift = hypot(Px-P0(1),Py-P0(2));
cmDisp = hypot(xc(end)-xc(1),yc(end)-yc(1));

r = emptyResult();
r.seed = seed;
r.runRoot = string(runRoot);
r.omegaTheory = p.omegaTheory;
r.omega = f.omega;
r.Gomega = f.omega/p.omegaTheory;
r.beta = f.beta;
r.R2 = f.R2;
r.zeroCrossOmega = omegaZC;
r.zeroCrossings = nCross;
r.q3Initial = q(1);
r.fitAmplitude = A0;
r.residualRMS = resRms;
r.snrResidual = snrResidual;
r.quadratureRMS = qQuadRms;
r.quadratureOverAmplitude = quadOverAmp;
r.snrLateEnvelope = snrLate;
r.windowG15 = fits{1}.omega/p.omegaTheory;
r.windowG20 = fits{2}.omega/p.omegaTheory;
r.windowG25 = fits{3}.omega/p.omegaTheory;
r.windowSpreadRel = windowSpreadRel;
r.kBTLiquidProxyMean = kLmean;
r.kBTGasProxyMean = kGmean;
r.massLiquidRelSpan = (max(ML)-min(ML))/mean(ML);
r.massGasRelSpan = (max(MG)-min(MG))/mean(MG);
r.maxTotalMomentumDrift = max(Pdrift);
r.cmDisplacementCells = cmDisp/p.h;
r.cmDisplacementOverR = cmDisp/p.R;
r.thermalResolutionOK = thermalResolutionOK;
r.traceTime = time;
r.traceQ3 = q;

analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end
trace = table(steps,time,q,qq,xc,yc,kL,kG,ML,MG,Px,Py, ...
    'VariableNames',{'step','time','q3Parallel','q3Quadrature','xCM','yCM','kBTLiquidProxy','kBTGasProxy','massLiquid','massGas','PxTotal','PyTotal'});
writetable(trace,fullfile(analysisDir,'oscillating_drop_n3_two_phase_trace.csv'));

S = rmfield(r,{'traceTime','traceQ3'});
writeJson(fullfile(analysisDir,'oscillating_drop_n3_two_phase_summary.json'),S);

fid=fopen(fullfile(analysisDir,'oscillating_drop_n3_two_phase_report.txt'),'w');
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'seed=%d\n',seed);
fprintf(fid,'omegaTheory=%.12g omega=%.12g Gomega=%.9g beta=%.9g R2=%.9g\n',p.omegaTheory,f.omega,r.Gomega,f.beta,f.R2);
fprintf(fid,'zeroCrossOmega=%.12g crossings=%d\n',omegaZC,nCross);
fprintf(fid,'q3Initial=%.9g epsilonTarget=%.9g amplitude=%.9g\n',q(1),p.epsilon,A0);
fprintf(fid,'residualRMS=%.9g snrResidual=%.9g qQuadratureRMS=%.9g quadratureOverAmplitude=%.9g lateEnvelopeSNR=%.9g\n',resRms,snrResidual,qQuadRms,quadOverAmp,snrLate);
fprintf(fid,'windowG=[1.5T %.9g, 2.0T %.9g, 2.5T %.9g] spreadRel=%.9g\n',r.windowG15,r.windowG20,r.windowG25,windowSpreadRel);
fprintf(fid,'kBTproxyLiquid=%.9g target=%.9g kBTproxyGas=%.9g target=%.9g\n',kLmean,p.kBTL,kGmean,p.kBTG);
fprintf(fid,'massRelSpan liquid=%.3e gas=%.3e maxTotalMomentumDrift=%.6g\n',r.massLiquidRelSpan,r.massGasRelSpan,r.maxTotalMomentumDrift);
fprintf(fid,'cmDisplacement=%.6g h = %.6g R\n',r.cmDisplacementCells,r.cmDisplacementOverR);
fprintf(fid,'thermalResolutionOK=%d\n',thermalResolutionOK);
fprintf(fid,'NOTE: kBT proxy is global peculiar energy and slightly upper-biased by coherent flow.\n');
fprintf(fid,'NOTE: thermalResolutionOK is a numerical signal-resolution guard, not a physical validation threshold.\n');
clear c

fig=figure('Visible','off');
plot(time/p.periodTheory,q,'o-'); hold on;
plot(tf/p.periodTheory,f.pred,'-','LineWidth',1.2); yline(0,':');
xlabel('t/T_3^{th}'); ylabel('q_3');
title(sprintf('n=3 seed %d: G_\\omega=%.4f, R^2=%.4f',seed,r.Gomega,r.R2));
legend('q_3','2.5T fit','Location','best'); box on;
exportgraphics(fig,fullfile(analysisDir,'oscillating_drop_n3_two_phase_fit.png'),'Resolution',180);
close(fig);

fprintf('[0493x14aj-JCP] seed=%d Gomega=%.6f R2=%.5f SNR=%.2f lateSNR=%.2f windowSpread=%.3g thermalOK=%d\n', ...
    seed,r.Gomega,r.R2,r.snrResidual,r.snrLateEnvelope,r.windowSpreadRel,r.thermalResolutionOK);
end

function f = dampedFit(tAbs,y,omega0,betaScale)
t = tAbs-tAbs(1);
wlo=0.65*omega0; whi=1.25*omega0;
blo=-3*betaScale; bhi=6*betaScale;
best=[];
for pass=1:3
    if pass==1, nw=121; nb=91; elseif pass==2, nw=81; nb=61; else, nw=61; nb=41; end
    ws=linspace(wlo,whi,nw); bs=linspace(blo,bhi,nb);
    for iw=1:numel(ws)
        w=ws(iw);
        for ib=1:numel(bs)
            b=bs(ib);
            [sse,r2,coef,pred]=linearFit(t,y,w,b);
            if isempty(best) || sse<best.sse
                best=struct('sse',sse,'omega',w,'beta',b,'R2',r2,'coef',coef,'pred',pred);
            end
        end
    end
    dw=(whi-wlo)/max(1,nw-1)*3;
    db=(bhi-blo)/max(1,nb-1)*3;
    wlo=max(0.2*omega0,best.omega-dw); whi=best.omega+dw;
    blo=best.beta-db; bhi=best.beta+db;
end
f=best; f.C=best.coef(1); f.D=best.coef(2); f.offset=best.coef(3);
end

function [sse,r2,coef,pred] = linearFit(t,y,w,beta)
e=exp(-beta*t);
X=[e.*cos(w*t), e.*sin(w*t), ones(size(t))];
coef=X\y;
pred=X*coef;
res=y-pred; sse=sum(res.^2);
sst=sum((y-mean(y)).^2);
if sst>0, r2=1-sse/sst; else, r2=NaN; end
end

function [omega,nc]=zeroCrossOmega(t,y,offset)
z=y-offset; cr=[];
for i=2:numel(z)
    a=z(i-1); b=z(i);
    if a==0
        cr(end+1)=t(i-1); %#ok<AGROW>
    elseif a*b<0
        frac=abs(a)/(abs(a)+abs(b));
        cr(end+1)=t(i-1)+frac*(t(i)-t(i-1)); %#ok<AGROW>
    end
end
nc=numel(cr);
if nc<3
    omega=NaN;
else
    hp=median(diff(cr)); omega=pi/hp;
end
end

function s=readState(path)
fid=fopen(path,'rb','ieee-le');
if fid<0, error('cannot open %s',path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
magic=char(fread(fid,16,'uint8=>char')');
if ~startsWith(magic,'SRCMPCD_STATE'), error('%s: bad magic',path); end
version=fread(fid,1,'uint32=>double'); endian=fread(fid,1,'uint32=>double');
dim=fread(fid,1,'uint32=>double'); layout=fread(fid,1,'uint32=>double');
n=fread(fid,1,'uint64=>double'); hasType=fread(fid,1,'uint32=>double');
hasMass=fread(fid,1,'uint32=>double'); nres=fread(fid,1,'uint32=>double'); typeBytes=fread(fid,1,'uint32=>double');
if version~=2 || endian~=hex2dec('01020304') || dim~=2 || layout~=1 || hasType~=1 || hasMass~=1 || typeBytes~=4
    error('%s: unsupported state header',path);
end
if nres>0, fread(fid,nres,'uint64=>uint64'); end
s.x=fread(fid,n,'double=>double'); s.y=fread(fid,n,'double=>double');
s.vx=fread(fid,n,'double=>double'); s.vy=fread(fid,n,'double=>double');
s.type=fread(fid,n,'uint32=>uint32'); s.mass=fread(fid,n,'double=>double');
s.role=fread(fid,n,'uint8=>uint8');
if numel(s.role)~=n, error('%s: truncated state',path); end
end

function [qp,qq,cx,cy,kbtProxy,M,Px,Py]=phaseMetrics(s,typeId,R,phase,n)
idx=(s.role==1 & s.type==uint32(typeId));
if ~any(idx), error('state has no active particles of type %d',typeId); end
m=s.mass(idx); x=s.x(idx); y=s.y(idx); vx=s.vx(idx); vy=s.vy(idx);
M=sum(m); Px=sum(m.*vx); Py=sum(m.*vy);
cx=sum(m.*x)/M; cy=sum(m.*y)/M;
ux=Px/M; uy=Py/M;
Kpec=sum(0.5*m.*((vx-ux).^2+(vy-uy).^2));
kbtProxy=Kpec/numel(m); % 2-D: Kpec/N ~ kBT; coherent internal flow makes this an upper proxy.
z=(x-cx)+1i*(y-cy);
mn=sum(m.*(z.^n))/M;
rot=mn*exp(1i*phase)/(R^n);
qp=real(rot); qq=imag(rot);
end

function y=safeRatio(a,b)
if b>0 && isfinite(b), y=a/b; else, y=Inf; end
end

function s=sampleStd(x)
if numel(x)<=1, s=0; else, s=std(x,0); end
end

function writeJson(path,S)
fid=fopen(path,'w'); if fid<0, error('cannot write %s',path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(S,'PrettyPrint',true)); fwrite(fid,newline);
end

function r=emptyResult()
r=struct( ...
    'seed',NaN,'runRoot',"",'omegaTheory',NaN,'omega',NaN,'Gomega',NaN,'beta',NaN,'R2',NaN, ...
    'zeroCrossOmega',NaN,'zeroCrossings',NaN,'q3Initial',NaN,'fitAmplitude',NaN,'residualRMS',NaN, ...
    'snrResidual',NaN,'quadratureRMS',NaN,'quadratureOverAmplitude',NaN,'snrLateEnvelope',NaN, ...
    'windowG15',NaN,'windowG20',NaN,'windowG25',NaN,'windowSpreadRel',NaN, ...
    'kBTLiquidProxyMean',NaN,'kBTGasProxyMean',NaN,'massLiquidRelSpan',NaN,'massGasRelSpan',NaN, ...
    'maxTotalMomentumDrift',NaN,'cmDisplacementCells',NaN,'cmDisplacementOverR',NaN, ...
    'thermalResolutionOK',false,'traceTime',[],'traceQ3',[]);
end
