function results = analyze_0493x19b_fix3_full_angular_audit(runRoot,startStep)
%ANALYZE_0493X19B_FIX3_FULL_ANGULAR_AUDIT
% Complete operator-by-operator moment audit for the short x19b bounceback
% restart.  No physical model is inferred here: the measured global state is
% sampled before/after every mutating top-level operator and differences are
% reported directly.
%
% The wall CSV is the reaction ON THE SOLID.  Therefore the corresponding
% fluid angular impulse is the negative of the wall reaction impulse.

if nargin<1 || isempty(runRoot)
    here=fileparts(mfilename('fullpath'));
    runRoot=fullfile(here,'..','runs','0493x19b_fix3_full_angular_audit','bounceback','fresh');
end
if nargin<2 || isempty(startStep), startStep=20; end

paramsPath=local_first_file(fullfile(runRoot,'params','*.kv'));
P=local_read_kv(paramsPath); dt=str2double(P.dt);
if ~(isfinite(dt)&&dt>0), error('0493x19bFix3:badDt','Invalid dt'); end
stagePath=fullfile(runRoot,'output','angular_balance_stages_0493x19b_fix3.csv');
wallPath=fullfile(runRoot,'output','chi_kinetic_boundary_0493x16j.csv');
if ~isfile(stagePath), error('0493x19bFix3:noStage','Missing %s',stagePath); end
if ~isfile(wallPath), error('0493x19bFix3:noWall','Missing %s',wallPath); end
A=readtable(stagePath,'VariableNamingRule','preserve');
K=readtable(wallPath,'VariableNamingRule','preserve');
local_require(A,{'step','stage','source','mass','momentumX','momentumY','angularMomentumZ','kineticEnergy','polarMassMoment','radialMomentum','tangentialMomentum'});
local_require(K,{'step','x19bInnerTorqueImpulse','x19bOuterTorqueImpulse','x19bInnerTorqueTangentialImpulse','x19bOuterTorqueTangentialImpulse'});

stages=["step_start","post_prestream_sources","post_chi_wall","post_stream", ...
    "post_boundary","post_immersed","post_penetration_diagnostic", ...
    "post_src_collision","post_q6_projection","post_closed_capacity", ...
    "post_thermostat","post_keep_mean_flow","post_darcy", ...
    "post_solid_dynamics","post_mass_recondition","post_population_guard","step_end"];
ops=["prestream_sources","chi_wall","stream","boundary","immersed", ...
    "penetration_or_solid_sync","src_collision","q6_projection","closed_capacity", ...
    "thermostat","keep_mean_flow","darcy","solid_dynamics", ...
    "mass_recondition","population_guard","post_guard_to_end"];

% Keep only steps for which every stage and the wall row are present.
common=unique(double(A.step)); common=common(common>=startStep);
for j=1:numel(stages)
    sj=double(A.step(strcmp(string(A.stage),stages(j))));
    common=intersect(common,sj,'stable');
end
common=intersect(common,double(K.step),'stable');
if numel(common)<50
    error('0493x19bFix3:short','Need >=50 complete steps at step >=%d; found %d',startStep,numel(common));
end

fields={'mass','momentumX','momentumY','angularMomentumZ','kineticEnergy','polarMassMoment','radialMomentum','tangentialMomentum'};
M=struct(); sources=strings(numel(common),numel(stages));
for f=1:numel(fields), M.(fields{f})=nan(numel(common),numel(stages)); end
for j=1:numel(stages)
    rows=strcmp(string(A.stage),stages(j)); T=A(rows,:);
    [tf,loc]=ismember(common,double(T.step));
    if ~all(tf), error('0493x19bFix3:stageGap','Incomplete stage %s',stages(j)); end
    for f=1:numel(fields), M.(fields{f})(:,j)=double(T.(fields{f})(loc)); end
    sources(:,j)=string(T.source(loc));
end
[~,kw]=ismember(common,double(K.step)); K=K(kw,:);

% Exact stage-to-stage measured rates.
rate=struct();
for f=1:numel(fields), rate.(fields{f})=diff(M.(fields{f}),1,2)/dt; end
torque=rate.angularMomentumZ;
meanTorque=mean(torque,1,'omitnan');
rmsTorque=sqrt(mean(torque.^2,1,'omitnan'));
semTorque=nan(size(meanTorque));
for j=1:numel(ops), semTorque(j)=local_block_sem(torque(:,j)); end

fullTorque=(M.angularMomentumZ(:,end)-M.angularMomentumZ(:,1))/dt;
sumTorque=sum(torque,2);
telescope=fullTorque-sumTorque;
telescopeRelRms=sqrt(mean(telescope.^2,'omitnan'))/max(sqrt(mean(fullTorque.^2,'omitnan')),eps);

% Independent x17 wall reaction accounting.
innerR=double(K.x19bInnerTorqueImpulse)/dt;
outerR=double(K.x19bOuterTorqueImpulse)/dt;
innerT=double(K.x19bInnerTorqueTangentialImpulse)/dt;
outerT=double(K.x19bOuterTorqueTangentialImpulse)/dt;
wallFluidDirect=-(innerR+outerR);
wallFluidTangential=-(innerT+outerT);
wallSnapshot=torque(:,2); % post_chi_wall - post_prestream_sources
wallMismatch=wallSnapshot-wallFluidDirect;
wallMismatchRelRms=sqrt(mean(wallMismatch.^2,'omitnan'))/max(sqrt(mean(wallFluidDirect.^2,'omitnan')),eps);

% Full-step rates for independent conservation context.
fullMassRate=(M.mass(:,end)-M.mass(:,1))/dt;
fullPxRate=(M.momentumX(:,end)-M.momentumX(:,1))/dt;
fullPyRate=(M.momentumY(:,end)-M.momentumY(:,1))/dt;
fullEnergyRate=(M.kineticEnergy(:,end)-M.kineticEnergy(:,1))/dt;
fullPolarRate=(M.polarMassMoment(:,end)-M.polarMassMoment(:,1))/dt;

fprintf('\n[0493x19b-fix3] complete steps %d..%d ; n=%d ; stages=%d\n',min(common),max(common),numel(common),numel(stages));
fprintf('[0493x19b-fix3] stage source: CUDA-resident %.3f %% ; host %.3f %%\n', ...
    100*nnz(sources=="cuda_resident")/numel(sources),100*nnz(sources=="host_authoritative")/numel(sources));
fprintf('[0493x19b-fix3] full-step <dL/dt> = % .9g ; block SEM=%.6g\n',mean(fullTorque,'omitnan'),local_block_sem(fullTorque));
fprintf('[0493x19b-fix3] telescoping relRMS = %.3e\n',telescopeRelRms);
fprintf('[0493x19b-fix3] direct fluid-wall torque = % .9g ; snapshot wall torque = % .9g\n',mean(wallFluidDirect,'omitnan'),mean(wallSnapshot,'omitnan'));
fprintf('[0493x19b-fix3] wall direct-vs-snapshot relRMS = %.3e ; tangential direct=% .9g\n',wallMismatchRelRms,mean(wallFluidTangential,'omitnan'));
fprintf('[0493x19b-fix3] full-step <dM/dt>=% .6g <dPx/dt>=% .6g <dPy/dt>=% .6g <dK/dt>=% .6g <dI/dt>=% .6g\n', ...
    mean(fullMassRate,'omitnan'),mean(fullPxRate,'omitnan'),mean(fullPyRate,'omitnan'),mean(fullEnergyRate,'omitnan'),mean(fullPolarRate,'omitnan'));
fprintf('\n[0493x19b-fix3] operator angular-momentum budget (torque units)\n');
fprintf('  %-26s %14s %12s %14s\n','operator','mean','blockSEM','RMS');
for j=1:numel(ops)
    fprintf('  %-26s % 14.7g % 12.5g % 14.7g\n',ops(j),meanTorque(j),semTorque(j),rmsTorque(j));
end

% Per-operator mass, linear momentum and energy diagnostics accompany Lz, so a
% source cannot be hidden behind an angular-only interpretation.
meanMass=mean(rate.mass,1,'omitnan');
meanPx=mean(rate.momentumX,1,'omitnan');
meanPy=mean(rate.momentumY,1,'omitnan');
meanEnergy=mean(rate.kineticEnergy,1,'omitnan');
meanPolar=mean(rate.polarMassMoment,1,'omitnan');
summary=table(ops(:),meanTorque(:),semTorque(:),rmsTorque(:),meanMass(:),meanPx(:),meanPy(:),meanEnergy(:),meanPolar(:), ...
    'VariableNames',{'operator','meanTorque','blockSemTorque','rmsTorque','meanMassRate','meanPxRate','meanPyRate','meanKineticEnergyRate','meanPolarMomentRate'});
writetable(summary,fullfile(runRoot,'output','operator_budget_0493x19b_fix3.csv'));

half=common<=median(common);
results=struct(); results.runRoot=runRoot; results.steps=common; results.stages=stages; results.operators=ops;
results.meanTorque=meanTorque; results.semTorque=semTorque; results.rmsTorque=rmsTorque;
results.fullStepMeanTorque=mean(fullTorque,'omitnan'); results.fullStepSem=local_block_sem(fullTorque);
results.telescopingRelativeRms=telescopeRelRms;
results.wallFluidDirectMean=mean(wallFluidDirect,'omitnan'); results.wallSnapshotMean=mean(wallSnapshot,'omitnan');
results.wallDirectSnapshotRelativeRms=wallMismatchRelRms; results.wallTangentialDirectMean=mean(wallFluidTangential,'omitnan');
results.firstHalfMeanTorque=mean(fullTorque(half),'omitnan'); results.lastHalfMeanTorque=mean(fullTorque(~half),'omitnan');
results.summary=summary; results.stageMoments=M; results.operatorRates=rate;

smoothN=min(31,max(5,2*floor(numel(common)/40)+1));
fig=figure('Color','w','Name','0493x19b-fix3 full angular audit');
tiledlayout(3,1,'Padding','compact','TileSpacing','compact');
nexttile; hold on;
plot(common,movmean(wallSnapshot,smoothN),'DisplayName','wall snapshot');
plot(common,movmean(torque(:,7),smoothN),'DisplayName','SRC');
plot(common,movmean(torque(:,8),smoothN),'DisplayName','Q6');
plot(common,movmean(torque(:,10),smoothN),'DisplayName','thermostat');
plot(common,movmean(fullTorque,smoothN),'k','LineWidth',1.1,'DisplayName','full step');
yline(0,'k:'); grid on; legend('Location','best'); ylabel('torque'); title(sprintf('x19b-fix3 operator budget, movmean %d',smoothN));
nexttile; bar(categorical(ops),meanTorque); grid on; ylabel('<\DeltaL/\Deltat>'); xtickangle(35); title('Mean torque contribution by measured operator');
nexttile; hold on;
plot(common,movmean(wallFluidDirect,smoothN),'DisplayName','direct fluid-wall');
plot(common,movmean(wallSnapshot,smoothN),'DisplayName','snapshot wall delta');
plot(common,movmean(wallMismatch,smoothN),'DisplayName','difference');
yline(0,'k:'); grid on; legend('Location','best'); xlabel('additional restart step'); ylabel('torque'); title('Independent wall-accounting cross-check');
try, exportgraphics(fig,fullfile(runRoot,'output','full_angular_audit_0493x19b_fix3.png'),'Resolution',160); catch, end
end

function s=local_block_sem(x)
x=x(:); n=numel(x); nb=min(8,max(4,floor(n/40))); edges=round(linspace(1,n+1,nb+1)); b=nan(nb,1);
for k=1:nb, ii=edges(k):edges(k+1)-1; b(k)=mean(x(ii),'omitnan'); end
s=std(b,0,'omitnan')/sqrt(nnz(isfinite(b)));
end
function path=local_first_file(pattern), d=dir(pattern); if isempty(d), error('No file matching %s',pattern); end; path=fullfile(d(1).folder,d(1).name); end
function local_require(T,n), m=n(~ismember(n,T.Properties.VariableNames)); if ~isempty(m), error('Missing columns: %s',strjoin(m,', ')); end; end
function kv=local_read_kv(path)
fid=fopen(path,'r'); if fid<0, error('Cannot open %s',path); end; c=onCleanup(@() fclose(fid)); kv=struct();
while true, line=fgetl(fid); if ~ischar(line), break; end; q=strfind(line,'='); if isempty(q), continue; end; key=matlab.lang.makeValidName(strtrim(line(1:q(1)-1))); kv.(key)=strtrim(line(q(1)+1:end)); end
end
