function results = analyze_0493x19c_free_rotor_annulus(runRoot,analysisStartStep)
%ANALYZE_0493X19C_FREE_ROTOR_ANNULUS
% End-to-end validation of the one-DOF free inner rotor.
% Primary independent reference: late TOTAL inner-wall reaction measured in
% the prescribed x19b-fix4 run at Omega=0.20.  x19c must close the discrete
% mechanics exactly and keep a statistically stationary free rotor near the
% independent prescribed-run operating point.

if nargin<1 || isempty(runRoot)
    here=fileparts(mfilename('fullpath'));
    runRoot=fullfile(here,'..','runs','0493x19c_free_rotor_annulus','fresh');
end
if nargin<2 || isempty(analysisStartStep), analysisStartStep=500; end

paramsPath=local_first_file(fullfile(runRoot,'params','0493x19c_free_rotor_omega020.kv'));
P=local_read_kv(paramsPath);
dt=local_num(P,'dt'); Lx=local_num(P,'Lx'); Ly=local_num(P,'Ly');
Nx=local_num(P,'Nx'); Ny=local_num(P,'Ny');
cx=local_num(P,'chiSolidPrescribedRotationCenterX');
cy=local_num(P,'chiSolidPrescribedRotationCenterY');
inertia=local_num(P,'chiSolidFreeRotorInertia');
targetOmega=local_num(P,'chiSolidFreeRotorInitialOmegaZ');
externalTorque=local_num(P,'chiSolidFreeRotorExternalTorqueZ');
h=min(Lx/Nx,Ly/Ny);

refPath=fullfile(runRoot,'params','0493x19c_reference_from_x19b_fix4.kv');
R=local_read_kv(refPath);
refHydro=local_num(R,'innerTorqueTotalMean');
refHydroSem=local_num(R,'innerTorqueTotalBlockSem');
refOmega=local_num(R,'targetOmega');
refOmegaSem=local_num(R,'targetOmegaReferenceSem');
if abs(targetOmega-refOmega)>1e-10
    error('0493x19c:targetMismatch','Rotor initial target and reference target differ.');
end
if abs(externalTorque+refHydro)>1e-10*max(1,abs(externalTorque))
    error('0493x19c:torqueMismatch','External torque is not the opposite of the independent x19b reference.');
end

outDir=fullfile(runRoot,'output');
rotorPath=fullfile(outDir,'chi_free_rotor_0493x19c.csv');
wallPath=fullfile(outDir,'chi_kinetic_boundary_0493x16j.csv');
meshPath=fullfile(outDir,'chi_lagrangian_mesh_0493x17a.csv');
if ~isfile(rotorPath), error('Missing %s',rotorPath); end
if ~isfile(wallPath), error('Missing %s',wallPath); end
if ~isfile(meshPath), error('Missing %s',meshPath); end

Q=readtable(rotorPath,'VariableNamingRule','preserve');
local_require(Q,{'step','omegaBefore','omegaAfter','hydroTorqueImpulse','hydroNormalTorqueImpulse', ...
    'hydroTangentialTorqueImpulse','externalTorqueImpulse','dampingTorqueImpulse','totalTorqueImpulse', ...
    'mechanicsResidual','hydroTorque','externalTorque','dampingTorque','totalTorque'});
Q=Q(double(Q.step)>=analysisStartStep,:);
if height(Q)<500, error('0493x19c:short','Need >=500 rotor rows after step %d; found %d',analysisStartStep,height(Q)); end
steps=double(Q.step);
omega=double(Q.omegaAfter);
hydro=double(Q.hydroTorque);
netTorque=double(Q.totalTorque);
mechResidual=double(Q.mechanicsResidual);
totalImpulse=double(Q.totalTorqueImpulse);

[semOmega,~]=local_block_sem(omega);
[semHydro,~]=local_block_sem(hydro);
[semNet,~]=local_block_sem(netTorque);
meanOmega=mean(omega,'omitnan'); meanHydro=mean(hydro,'omitnan'); meanNet=mean(netTorque,'omitnan');
omegaRelErr=(meanOmega-refOmega)/refOmega;
hydroRelErr=(meanHydro-refHydro)/max(abs(refHydro),eps);
omegaZ=(meanOmega-refOmega)/max(sqrt(semOmega^2+refOmegaSem^2),eps);
hydroZ=(meanHydro-refHydro)/max(sqrt(semHydro^2+refHydroSem^2),eps);
mechanicsRelRms=sqrt(mean(mechResidual.^2,'omitnan'))/max(sqrt(mean(totalImpulse.^2,'omitnan')),eps);
mechanicsMax=max(abs(mechResidual));

mid=steps<=median(steps);
omegaFirst=mean(omega(mid),'omitnan'); omegaLast=mean(omega(~mid),'omitnan');
hydroFirst=mean(hydro(mid),'omitnan'); hydroLast=mean(hydro(~mid),'omitnan');
netFirst=mean(netTorque(mid),'omitnan'); netLast=mean(netTorque(~mid),'omitnan');
pfit=polyfit(steps,omega,1); omegaSlopePerStep=pfit(1);

% Independent cross-check against the x17 wall CSV: exact same generalized
% inner wall reaction must be seen by the rotor mechanics.
K=readtable(wallPath,'VariableNamingRule','preserve');
local_require(K,{'step','x19bInnerTorqueImpulse','x19bInnerTorqueNormalImpulse','x19bInnerTorqueTangentialImpulse'});
K=K(double(K.step)>=analysisStartStep,:);
[commonSteps,iq,ik]=intersect(double(Q.step),double(K.step),'stable');
if numel(commonSteps)<500, error('0493x19c:crosscheck','Insufficient matched rotor/wall rows.'); end
rotorHydroImpulse=double(Q.hydroTorqueImpulse(iq));
wallHydroImpulse=double(K.x19bInnerTorqueImpulse(ik));
wallCrossRelRms=sqrt(mean((rotorHydroImpulse-wallHydroImpulse).^2))/max(sqrt(mean(wallHydroImpulse.^2)),eps);

% Late profile from full restart dumps.  This is secondary to the generalized
% mechanics closure but verifies that freeing the rotor preserves Couette flow.
riNom=0.20; roNom=0.35;
[ri,ro]=local_effective_mesh_radii(meshPath,cx,cy,riNom,roNom);
D=dir(fullfile(outDir,'state_step_*.smpcd'));
dumpSteps=nan(numel(D),1);
for i=1:numel(D)
    tok=regexp(D(i).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok), dumpSteps(i)=str2double(tok{1}); end
end
valid=isfinite(dumpSteps) & dumpSteps>=analysisStartStep;
D=D(valid); dumpSteps=dumpSteps(valid); [dumpSteps,ord]=sort(dumpSteps); D=D(ord);
profileRelRmse=NaN; profileR2=NaN; profileGain=NaN; radialOverUi=NaN;
rCenter=[]; uTheta=[]; uRadial=[]; theory=[];
if numel(D)>=3
    nBins=max(20,round((ro-ri)/h)); rEdges=linspace(ri,ro,nBins+1)';
    rCenter=0.5*(rEdges(1:end-1)+rEdges(2:end));
    massBin=zeros(nBins,1); ptBin=zeros(nBins,1); prBin=zeros(nBins,1);
    for k=1:numel(D)
        S=local_read_smpcd_state(fullfile(D(k).folder,D(k).name)); fluid=(S.role==1);
        x=S.x(fluid); y=S.y(fluid); vx=S.vx(fluid); vy=S.vy(fluid); m=S.mass(fluid);
        rx=x-cx; ry=y-cy; r=hypot(rx,ry); good=isfinite(r)&r>0&r>=ri&r<=ro;
        rx=rx(good); ry=ry(good); r=r(good); vx=vx(good); vy=vy(good); m=m(good);
        ut=(-ry./r).*vx+(rx./r).*vy; ur=(rx./r).*vx+(ry./r).*vy;
        ib=discretize(r,rEdges); keep=~isnan(ib); ib=ib(keep); m=m(keep); ut=ut(keep); ur=ur(keep);
        massBin=massBin+accumarray(ib,m,[nBins 1],@sum,0);
        ptBin=ptBin+accumarray(ib,m.*ut,[nBins 1],@sum,0);
        prBin=prBin+accumarray(ib,m.*ur,[nBins 1],@sum,0);
    end
    uTheta=ptBin./max(massBin,eps); uRadial=prBin./max(massBin,eps);
    theory=meanOmega*ri^2/(ro^2-ri^2).*(ro^2./rCenter-rCenter);
    ui=abs(meanOmega*ri); pv=massBin>0 & rCenter>(ri+1.5*h) & rCenter<(ro-1.5*h);
    err=uTheta(pv)-theory(pv); profileRelRmse=sqrt(mean(err.^2))/max(ui,eps);
    den=sum((theory(pv)-mean(theory(pv))).^2); profileR2=1-sum(err.^2)/max(den,eps);
    profileGain=sum(uTheta(pv).*theory(pv))/max(sum(theory(pv).^2),eps);
    radialOverUi=mean(abs(uRadial(pv)))/max(ui,eps);
end

mechanicsPass=mechanicsRelRms<1e-10 && wallCrossRelRms<1e-12;
omegaPass=abs(omegaZ)<=3 && abs(omegaRelErr)<=0.10;
hydroPass=abs(hydroZ)<=3;
stationaryPass=abs(meanNet)<=3*max(semNet,eps);
profilePass=isnan(profileRelRmse) || (profileRelRmse<=0.06 && profileR2>=0.97 && radialOverUi<=0.05);
overallPass=mechanicsPass && omegaPass && hydroPass && stationaryPass && profilePass;
status='REVIEW'; if overallPass, status='PASS'; end

fprintf('\n[0493x19c] free-rotor window %d..%d ; rows=%d ; I=%.9g\n',min(steps),max(steps),height(Q),inertia);
fprintf('[0493x19c] mechanics closure relRMS=%.3e maxAbs=%.3e ; wall-cross relRMS=%.3e\n',mechanicsRelRms,mechanicsMax,wallCrossRelRms);
fprintf('[0493x19c] omega mean=%.9g +/- %.6g blockSEM ; target=%.9g +/- %.6g refSEM ; rel.err=% .6g ; z=% .6g\n', ...
    meanOmega,semOmega,refOmega,refOmegaSem,omegaRelErr,omegaZ);
fprintf('[0493x19c] hydro torque=% .9g +/- %.6g ; x19b reference=% .9g +/- %.6g ; rel.diff=% .6g ; z=% .6g\n', ...
    meanHydro,semHydro,refHydro,refHydroSem,hydroRelErr,hydroZ);
fprintf('[0493x19c] external torque=% .9g ; net torque=% .9g +/- %.6g blockSEM\n',externalTorque,meanNet,semNet);
fprintf('[0493x19c] first/last: omega %.9g -> %.9g ; hydro % .9g -> % .9g ; net % .9g -> % .9g ; omegaSlope/step=% .3e\n', ...
    omegaFirst,omegaLast,hydroFirst,hydroLast,netFirst,netLast,omegaSlopePerStep);
if ~isnan(profileRelRmse)
    fprintf('[0493x19c] profile relRMSE=%.6g R2=%.6g gain=%.6g radial/Ui=%.6g ; dumps=%d\n', ...
        profileRelRmse,profileR2,profileGain,radialOverUi,numel(D));
end
fprintf('[0493x19c] gates mechanics=%s omega=%s hydro=%s stationary=%s profile=%s => %s\n', ...
    local_pf(mechanicsPass),local_pf(omegaPass),local_pf(hydroPass),local_pf(stationaryPass),local_pf(profilePass),status);

summary=table(meanOmega,semOmega,refOmega,refOmegaSem,omegaRelErr,omegaZ,meanHydro,semHydro,refHydro,refHydroSem,hydroRelErr,hydroZ, ...
    externalTorque,meanNet,semNet,mechanicsRelRms,mechanicsMax,wallCrossRelRms,omegaFirst,omegaLast,hydroFirst,hydroLast,netFirst,netLast,omegaSlopePerStep, ...
    profileRelRmse,profileR2,profileGain,radialOverUi,mechanicsPass,omegaPass,hydroPass,stationaryPass,profilePass,overallPass, ...
    'VariableNames',{'omegaMean','omegaBlockSem','omegaReference','omegaReferenceSem','omegaRelativeError','omegaCombinedZ', ...
    'hydroTorqueMean','hydroTorqueBlockSem','hydroTorqueReference','hydroTorqueReferenceSem','hydroTorqueRelativeDifference','hydroTorqueCombinedZ', ...
    'externalTorque','netTorqueMean','netTorqueBlockSem','mechanicsClosureRelRms','mechanicsClosureMaxAbs','wallCrosscheckRelRms', ...
    'omegaFirstHalf','omegaLastHalf','hydroFirstHalf','hydroLastHalf','netFirstHalf','netLastHalf','omegaSlopePerStep', ...
    'profileRelativeRmse','profileR2','profileGain','radialOverUi','mechanicsPass','omegaPass','hydroPass','stationaryPass','profilePass','overallPass'});
writetable(summary,fullfile(outDir,'summary_0493x19c_free_rotor.csv'));

fig=figure('Color','w','Name','0493x19c free-rotor end-to-end validation');
tiledlayout(4,1,'Padding','compact','TileSpacing','compact');
nexttile; hold on; plot(steps,omega,'Color',[0.75 0.75 0.75]); plot(steps,cummean(omega),'LineWidth',1.3); yline(refOmega,'--'); grid on; ylabel('\Omega'); title('Free rotor: instantaneous and cumulative mean');
nexttile; hold on; plot(steps,cummean(hydro),'DisplayName','hydro'); yline(refHydro,'--','DisplayName','x19b prescribed ref'); yline(-externalTorque,':','DisplayName','-T_{ext}'); grid on; ylabel('torque'); legend('Location','best'); title('Hydrodynamic generalized load');
nexttile; hold on; plot(steps,movmean(netTorque,51)); yline(0,'--'); grid on; ylabel('net torque'); title('Solid torque balance, movmean 51');
nexttile; hold on;
if ~isempty(rCenter), plot(rCenter,uTheta,'.-'); plot(rCenter,theory,'--'); legend('measured','Couette at mean \Omega','Location','best'); end
grid on; xlabel('r'); ylabel('<u_\theta>'); title(sprintf('Late profile; status %s',status));
try, exportgraphics(fig,fullfile(outDir,'qualification_0493x19c_free_rotor.png'),'Resolution',160); catch, end

results=struct(); results.runRoot=runRoot; results.status=status; results.summary=summary;
results.meanOmega=meanOmega; results.omegaBlockSem=semOmega; results.omegaReference=refOmega; results.omegaZ=omegaZ;
results.meanHydroTorque=meanHydro; results.hydroBlockSem=semHydro; results.hydroReference=refHydro; results.hydroZ=hydroZ;
results.meanNetTorque=meanNet; results.netBlockSem=semNet; results.mechanicsClosureRelRms=mechanicsRelRms; results.wallCrosscheckRelRms=wallCrossRelRms;
results.profileRelativeRmse=profileRelRmse; results.profileR2=profileR2; results.profileGain=profileGain; results.radialOverUi=radialOverUi;
end

function s=local_pf(v), if v, s='PASS'; else, s='REVIEW'; end, end
function y=cummean(x), x=x(:); g=isfinite(x); z=x; z(~g)=0; y=cumsum(z)./max(cumsum(g),1); y(cumsum(g)==0)=NaN; end
function [s,b]=local_block_sem(x)
x=x(:); n=numel(x); nb=min(10,max(5,floor(n/300))); nb=min(nb,max(2,floor(n/80))); e=round(linspace(1,n+1,nb+1)); b=nan(nb,1);
for k=1:nb, ii=e(k):e(k+1)-1; b(k)=mean(x(ii),'omitnan'); end
s=std(b,0,'omitnan')/sqrt(nnz(isfinite(b)));
end
function [ri,ro]=local_effective_mesh_radii(path,cx,cy,riNom,roNom)
M=readtable(path,'VariableNamingRule','preserve'); local_require(M,{'ax','ay','bx','by'}); mx=0.5*(M.ax+M.bx); my=0.5*(M.ay+M.by); r=hypot(mx-cx,my-cy); len=hypot(M.bx-M.ax,M.by-M.ay); split=0.5*(riNom+roNom); a=r<split; b=r>split; ri=sum(r(a).*len(a))/sum(len(a)); ro=sum(r(b).*len(b))/sum(len(b));
end
function S=local_read_smpcd_state(path)
fid=fopen(path,'r','ieee-le'); if fid<0, error('Cannot open %s',path); end; c=onCleanup(@() fclose(fid)); magic=char(fread(fid,16,'*uint8')'); if ~startsWith(magic,'SRCMPCD_STATE'), error('Bad smpcd magic'); end
version=fread(fid,1,'uint32=>double'); endian=fread(fid,1,'uint32=>uint32'); dim=fread(fid,1,'uint32=>double'); layout=fread(fid,1,'uint32=>double'); n=fread(fid,1,'uint64=>double'); hasType=fread(fid,1,'uint32=>double'); hasMass=fread(fid,1,'uint32=>double'); realSize=fread(fid,1,'uint32=>double'); typeSize=fread(fid,1,'uint32=>double'); reserved=fread(fid,8,'uint64=>double');
if endian~=hex2dec('01020304')||dim~=2||layout~=1||hasType~=1||hasMass~=1||realSize~=8||typeSize~=4, error('Unsupported smpcd layout'); end
S.x=fread(fid,n,'double=>double'); S.y=fread(fid,n,'double=>double'); S.vx=fread(fid,n,'double=>double'); S.vy=fread(fid,n,'double=>double'); S.type=fread(fid,n,'uint32=>uint32'); S.mass=fread(fid,n,'double=>double'); if version>=2, roleSize=reserved(2); if roleSize==0, roleSize=1; end; if roleSize~=1, error('Unsupported role size'); end; S.role=fread(fid,n,'uint8=>uint8'); else, S.role=ones(n,1,'uint8'); end
end
function path=local_first_file(pattern), d=dir(pattern); if isempty(d), error('No file matching %s',pattern); end; path=fullfile(d(1).folder,d(1).name); end
function local_require(T,n), m=n(~ismember(n,T.Properties.VariableNames)); if ~isempty(m), error('Missing columns: %s',strjoin(m,', ')); end, end
function kv=local_read_kv(path)
fid=fopen(path,'r'); if fid<0, error('Cannot open %s',path); end; c=onCleanup(@() fclose(fid)); kv=struct(); while true, line=fgetl(fid); if ~ischar(line), break; end; q=strfind(line,'='); if isempty(q), continue; end; key=matlab.lang.makeValidName(strtrim(line(1:q(1)-1))); kv.(key)=strtrim(line(q(1)+1:end)); end
end
function v=local_num(P,key), if ~isfield(P,key), error('Missing parameter %s',key); end; v=str2double(P.(key)); if ~isfinite(v), error('Bad numeric parameter %s',key); end, end
