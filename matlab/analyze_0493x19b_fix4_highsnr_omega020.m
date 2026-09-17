function results = analyze_0493x19b_fix4_highsnr_omega020(runRoot,analysisStartStep)
%ANALYZE_0493X19B_FIX4_HIGHSNR_OMEGA020
% High-SNR single-bounceback qualification for prescribed annular Couette flow.
% The physical torque estimator is the antisymmetric tangential wall reaction
%   T_C = (T_outer - T_inner)/2.
% The common mode
%   T_common = (T_outer + T_inner)/2
% should be statistically compatible with zero in a stationary annulus.
%
% Reference viscosity is the matched 4-seed TG calibration:
% nu = 2.3313138152e-4, SEM = 5.2849208326e-6.

if nargin<1 || isempty(runRoot)
    here=fileparts(mfilename('fullpath'));
    runRoot=fullfile(here,'..','runs','0493x19b_fix4_highsnr_omega020','bounceback','fresh');
end
if nargin<2 || isempty(analysisStartStep), analysisStartStep=500; end

paramsPath=local_first_file(fullfile(runRoot,'params','*.kv'));
P=local_read_kv(paramsPath);
dt=local_num(P,'dt'); Lx=local_num(P,'Lx'); Ly=local_num(P,'Ly');
Nx=local_num(P,'Nx'); Ny=local_num(P,'Ny');
omega=local_num(P,'chiSolidPrescribedInnerOmegaZ');
cx=local_num(P,'chiSolidPrescribedRotationCenterX');
cy=local_num(P,'chiSolidPrescribedRotationCenterY');
if abs(omega-0.20)>1e-10
    error('0493x19bFix4:omega','Expected Omega=0.20, got %.17g',omega);
end
h=min(Lx/Nx,Ly/Ny);

nuRef=2.3313138152e-4;
nuStd=1.0569841665e-5;
nuSem=5.2849208326e-6;
nuN=4;
t95_3=3.182446305284263; % 95%% two-sided Student factor, df=3
nu95Half=t95_3*nuSem;

outDir=fullfile(runRoot,'output');
wallPath=fullfile(outDir,'chi_kinetic_boundary_0493x16j.csv');
meshPath=fullfile(outDir,'chi_lagrangian_mesh_0493x17a.csv');
if ~isfile(wallPath), error('Missing %s',wallPath); end
if ~isfile(meshPath), error('Missing %s',meshPath); end

% Effective radii are measured from the actual x17 facet mesh, not assumed.
riNom=0.20; roNom=0.35;
[ri,ro,riStd,roStd]=local_effective_mesh_radii(meshPath,cx,cy,riNom,roNom);

K=readtable(wallPath,'VariableNamingRule','preserve');
local_require(K,{'step','x19bInnerTorqueTangentialImpulse','x19bOuterTorqueTangentialImpulse', ...
    'x19bInnerTorqueNormalImpulse','x19bOuterTorqueNormalImpulse'});
kmask=double(K.step)>=analysisStartStep;
K=K(kmask,:);
if height(K)<200
    error('0493x19bFix4:shortTorque','Need >=200 every-step torque rows after step %d; found %d',analysisStartStep,height(K));
end
steps=double(K.step);
TiT=double(K.x19bInnerTorqueTangentialImpulse)/dt;
ToT=double(K.x19bOuterTorqueTangentialImpulse)/dt;
TiN=double(K.x19bInnerTorqueNormalImpulse)/dt;
ToN=double(K.x19bOuterTorqueNormalImpulse)/dt;
TC=0.5*(ToT-TiT);
Tcommon=0.5*(ToT+TiT);
TCnormal=0.5*(ToN-TiN);
TcommonNormal=0.5*(ToN+TiN);

[semTC,blockTC]=local_block_sem(TC);
[semCommon,blockCommon]=local_block_sem(Tcommon);
[semTi,~]=local_block_sem(TiT);
[semTo,~]=local_block_sem(ToT);
meanTC=mean(TC,'omitnan'); meanCommon=mean(Tcommon,'omitnan');
meanTi=mean(TiT,'omitnan'); meanTo=mean(ToT,'omitnan');
meanTCN=mean(TCnormal,'omitnan'); meanCommonN=mean(TcommonNormal,'omitnan');

% Read all full states in/after the analysis window.  They provide both the
% velocity profile and a measured 2-D mass density for the torque reference.
D=dir(fullfile(outDir,'state_step_*.smpcd'));
dumpSteps=nan(numel(D),1);
for i=1:numel(D)
    tok=regexp(D(i).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok), dumpSteps(i)=str2double(tok{1}); end
end
validDump=isfinite(dumpSteps) & dumpSteps>=analysisStartStep;
D=D(validDump); dumpSteps=dumpSteps(validDump);
[dumpSteps,ord]=sort(dumpSteps); D=D(ord);
if numel(D)<3
    error('0493x19bFix4:shortProfile','Need >=3 state dumps after step %d; found %d',analysisStartStep,numel(D));
end

nBins=max(20,round((ro-ri)/h));
rEdges=linspace(ri,ro,nBins+1)';
rCenter=0.5*(rEdges(1:end-1)+rEdges(2:end));
massBin=zeros(nBins,1); ptBin=zeros(nBins,1); prBin=zeros(nBins,1);
rhoDump=nan(numel(D),1);
for k=1:numel(D)
    S=local_read_smpcd_state(fullfile(D(k).folder,D(k).name));
    fluid=(S.role==1);
    rhoDump(k)=sum(S.mass(fluid))/(pi*(ro^2-ri^2));
    x=S.x(fluid); y=S.y(fluid); vx=S.vx(fluid); vy=S.vy(fluid); m=S.mass(fluid);
    rx=x-cx; ry=y-cy; r=hypot(rx,ry);
    good=isfinite(r) & r>0 & r>=ri & r<=ro;
    rx=rx(good); ry=ry(good); r=r(good); vx=vx(good); vy=vy(good); m=m(good);
    ut=(-ry./r).*vx + (rx./r).*vy;
    ur=( rx./r).*vx + (ry./r).*vy;
    ib=discretize(r,rEdges); keep=~isnan(ib);
    ib=ib(keep); m=m(keep); ut=ut(keep); ur=ur(keep);
    massBin=massBin+accumarray(ib,m,[nBins 1],@sum,0);
    ptBin=ptBin+accumarray(ib,m.*ut,[nBins 1],@sum,0);
    prBin=prBin+accumarray(ib,m.*ur,[nBins 1],@sum,0);
end
rhoMean=mean(rhoDump,'omitnan');
uTheta=ptBin./max(massBin,eps); uRadial=prBin./max(massBin,eps);
theory=omega*ri^2/(ro^2-ri^2).*(ro^2./rCenter-rCenter);
ui=abs(omega*ri);
profileValid=massBin>0 & rCenter>(ri+1.5*h) & rCenter<(ro-1.5*h);
err=uTheta(profileValid)-theory(profileValid);
profileRelRmse=sqrt(mean(err.^2))/max(ui,eps);
den=sum((theory(profileValid)-mean(theory(profileValid))).^2);
profileR2=1-sum(err.^2)/max(den,eps);
profileGain=sum(uTheta(profileValid).*theory(profileValid))/max(sum(theory(profileValid).^2),eps);
radialOverUi=mean(abs(uRadial(profileValid)))/max(ui,eps);

geomCoeff=4*pi*ri^2*ro^2/(ro^2-ri^2);
Tref=geomCoeff*rhoMean*nuRef*abs(omega);
TrefStd=Tref*(nuStd/nuRef);
TrefSem=Tref*(nuSem/nuRef);
Tref95Half=Tref*(nu95Half/nuRef);
TrelErr=(meanTC-Tref)/Tref;
combinedSem=sqrt(semTC^2+TrefSem^2);
zDiff=(meanTC-Tref)/max(combinedSem,eps);
commonOverRef=meanCommon/Tref;
normalOverRef=meanTCN/Tref;

mid=steps<=median(steps);
TCfirst=mean(TC(mid),'omitnan'); TClast=mean(TC(~mid),'omitnan');
CommonFirst=mean(Tcommon(mid),'omitnan'); CommonLast=mean(Tcommon(~mid),'omitnan');

fprintf('\n[0493x19b-fix4] torque window %d..%d ; rows=%d ; profile dumps=%d (%d..%d)\n', ...
    min(steps),max(steps),numel(steps),numel(D),dumpSteps(1),dumpSteps(end));
fprintf('[0493x19b-fix4] effective radii Ri=%.9g Ro=%.9g ; rho2D=%.9g\n',ri,ro,rhoMean);
fprintf('[0493x19b-fix4] tangential wall reaction inner=% .9g +/- %.6g  outer=% .9g +/- %.6g (block SEM)\n', ...
    meanTi,semTi,meanTo,semTo);
fprintf('[0493x19b-fix4] Couette half-difference = % .9g ; block SEM=%.6g\n',meanTC,semTC);
fprintf('[0493x19b-fix4] common half-sum        = % .9g ; block SEM=%.6g ; common/Tref=% .6g\n',meanCommon,semCommon,commonOverRef);
fprintf('[0493x19b-fix4] normal half-difference = % .9g ; normal/Tref=% .6g\n',meanTCN,normalOverRef);
fprintf('[0493x19b-fix4] matched TG nu = %.10g +/- %.6g SEM (n=%d); 95%% half-width=%.6g\n',nuRef,nuSem,nuN,nu95Half);
fprintf('[0493x19b-fix4] theory |T| = %.9g ; TG-SEM=%.6g ; TG-95%% half-width=%.6g\n',Tref,TrefSem,Tref95Half);
fprintf('[0493x19b-fix4] Couette-theory rel.diff = % .6g ; combined-SEM z=% .6g\n',TrelErr,zDiff);
fprintf('[0493x19b-fix4] Couette firstHalf=% .9g lastHalf=% .9g ; common firstHalf=% .9g lastHalf=% .9g\n', ...
    TCfirst,TClast,CommonFirst,CommonLast);
fprintf('[0493x19b-fix4] profile relRMSE=%.6g R2=%.6g gain=%.6g radial/Ui=%.6g\n', ...
    profileRelRmse,profileR2,profileGain,radialOverUi);

summary=table(meanTi,semTi,meanTo,semTo,meanTC,semTC,meanCommon,semCommon,meanTCN,meanCommonN, ...
    ri,ro,rhoMean,nuRef,nuStd,nuSem,Tref,TrefStd,TrefSem,Tref95Half,TrelErr,zDiff, ...
    TCfirst,TClast,CommonFirst,CommonLast,profileRelRmse,profileR2,profileGain,radialOverUi, ...
    'VariableNames',{'innerTangential','innerBlockSem','outerTangential','outerBlockSem', ...
    'couetteHalfDifference','couetteBlockSem','commonHalfSum','commonBlockSem','normalHalfDifference','normalCommonHalfSum', ...
    'riEffective','roEffective','density2D','referenceNu','referenceNuStd','referenceNuSem', ...
    'referenceTorque','referenceTorqueStd','referenceTorqueSem','referenceTorque95HalfWidth','torqueRelativeDifference','combinedSemZ', ...
    'couetteFirstHalf','couetteLastHalf','commonFirstHalf','commonLastHalf','profileRelativeRmse','profileR2','profileGain','radialOverUi'});
writetable(summary,fullfile(outDir,'summary_0493x19b_fix4_highsnr.csv'));
profileTable=table(rCenter,uTheta,uRadial,theory,massBin,'VariableNames',{'r','uThetaMean','uRadialMean','uThetaTheory','sampleMass'});
writetable(profileTable,fullfile(outDir,'profile_0493x19b_fix4_highsnr.csv'));

fig=figure('Color','w','Name','0493x19b-fix4 high-SNR torque qualification');
tiledlayout(3,1,'Padding','compact','TileSpacing','compact');
nexttile; hold on;
plot(steps,cummean(TC),'DisplayName','cumulative T_C');
yline(Tref,'--','DisplayName','TG theory');
yline(Tref+Tref95Half,':','DisplayName','TG 95% band');
yline(Tref-Tref95Half,':','HandleVisibility','off');
yline(0,'k:','HandleVisibility','off');
grid on; ylabel('torque'); legend('Location','best'); title('Couette torque cumulative mean');
nexttile; hold on;
plot(steps,cummean(Tcommon),'DisplayName','cumulative common mode');
yline(0,'k--'); grid on; ylabel('torque'); legend('Location','best'); title('Stationarity/common-mode control');
nexttile; hold on;
plot(rCenter(profileValid),uTheta(profileValid),'.-','DisplayName','measured');
plot(rCenter(profileValid),theory(profileValid),'--','DisplayName','analytic Couette');
grid on; xlabel('r'); ylabel('<u_\theta>'); legend('Location','best'); title('Late velocity profile');
try, exportgraphics(fig,fullfile(outDir,'qualification_0493x19b_fix4_highsnr.png'),'Resolution',160); catch, end

results=struct();
results.runRoot=runRoot; results.analysisStartStep=analysisStartStep; results.steps=steps;
results.innerTangential=TiT; results.outerTangential=ToT; results.couette=TC; results.common=Tcommon;
results.meanCouette=meanTC; results.couetteBlockSem=semTC; results.meanCommon=meanCommon; results.commonBlockSem=semCommon;
results.referenceNu=nuRef; results.referenceNuSem=nuSem; results.referenceTorque=Tref; results.referenceTorqueSem=TrefSem;
results.referenceTorque95HalfWidth=Tref95Half; results.torqueRelativeDifference=TrelErr; results.combinedSemZ=zDiff;
results.profileRelativeRmse=profileRelRmse; results.profileR2=profileR2; results.profileGain=profileGain; results.radialOverUi=radialOverUi;
results.riEffective=ri; results.roEffective=ro; results.density2D=rhoMean; results.blockCouette=blockTC; results.blockCommon=blockCommon;
results.summary=summary;
end

function y=cummean(x)
x=x(:); good=isfinite(x); x0=x; x0(~good)=0; sx=cumsum(x0); n=cumsum(good); y=sx./max(n,1); y(n==0)=NaN;
end

function [s,b]=local_block_sem(x)
x=x(:); n=numel(x); nb=min(10,max(5,floor(n/300))); nb=min(nb,max(2,floor(n/80)));
edges=round(linspace(1,n+1,nb+1)); b=nan(nb,1);
for k=1:nb
    ii=edges(k):edges(k+1)-1;
    b(k)=mean(x(ii),'omitnan');
end
s=std(b,0,'omitnan')/sqrt(nnz(isfinite(b)));
end

function [ri,ro,riStd,roStd]=local_effective_mesh_radii(path,cx,cy,riNom,roNom)
M=readtable(path,'VariableNamingRule','preserve');
local_require(M,{'ax','ay','bx','by'});
mx=0.5*(M.ax+M.bx); my=0.5*(M.ay+M.by);
r=hypot(mx-cx,my-cy); len=hypot(M.bx-M.ax,M.by-M.ay);
split=0.5*(riNom+roNom); in=r<split; out=r>split;
if nnz(in)<8 || nnz(out)<8, error('x19b mesh does not contain two radial branches'); end
ri=sum(r(in).*len(in))/sum(len(in)); ro=sum(r(out).*len(out))/sum(len(out));
riStd=sqrt(sum(len(in).*(r(in)-ri).^2)/sum(len(in)));
roStd=sqrt(sum(len(out).*(r(out)-ro).^2)/sum(len(out)));
end

function S=local_read_smpcd_state(path)
fid=fopen(path,'r','ieee-le'); if fid<0, error('Cannot open %s',path); end
c=onCleanup(@() fclose(fid));
magic=char(fread(fid,16,'*uint8')'); if ~startsWith(magic,'SRCMPCD_STATE'), error('Bad smpcd magic: %s',path); end
version=fread(fid,1,'uint32=>double'); endian=fread(fid,1,'uint32=>uint32');
dim=fread(fid,1,'uint32=>double'); layout=fread(fid,1,'uint32=>double'); n=fread(fid,1,'uint64=>double');
hasType=fread(fid,1,'uint32=>double'); hasMass=fread(fid,1,'uint32=>double'); realSize=fread(fid,1,'uint32=>double'); typeSize=fread(fid,1,'uint32=>double');
reserved=fread(fid,8,'uint64=>double');
if endian~=hex2dec('01020304') || dim~=2 || layout~=1 || hasType~=1 || hasMass~=1 || realSize~=8 || typeSize~=4
    error('Unsupported smpcd layout: %s',path);
end
S.x=fread(fid,n,'double=>double'); S.y=fread(fid,n,'double=>double');
S.vx=fread(fid,n,'double=>double'); S.vy=fread(fid,n,'double=>double');
S.type=fread(fid,n,'uint32=>uint32'); S.mass=fread(fid,n,'double=>double');
if version>=2
    roleSize=reserved(2); if roleSize==0, roleSize=1; end
    if roleSize~=1, error('Unsupported role size in %s',path); end
    S.role=fread(fid,n,'uint8=>uint8');
else
    S.role=ones(n,1,'uint8');
end
end

function path=local_first_file(pattern)
d=dir(pattern); if isempty(d), error('No file matching %s',pattern); end; path=fullfile(d(1).folder,d(1).name);
end
function local_require(T,n)
m=n(~ismember(n,T.Properties.VariableNames)); if ~isempty(m), error('Missing columns: %s',strjoin(m,', ')); end
end
function kv=local_read_kv(path)
fid=fopen(path,'r'); if fid<0, error('Cannot open %s',path); end; c=onCleanup(@() fclose(fid)); kv=struct();
while true
    line=fgetl(fid); if ~ischar(line), break; end; q=strfind(line,'='); if isempty(q), continue; end
    key=matlab.lang.makeValidName(strtrim(line(1:q(1)-1))); kv.(key)=strtrim(line(q(1)+1:end));
end
end
function v=local_num(P,key)
if ~isfield(P,key), error('Missing parameter %s',key); end; v=str2double(P.(key)); if ~isfinite(v), error('Bad numeric parameter %s',key); end
end
