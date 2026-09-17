function results = analyze_0493x19b_prescribed_rotating_annulus(baseRoot, lateStartStep, referenceNu)
% 0493x19b prescribed rotating annulus.
% Compares specular and bounceback against exact concentric cylindrical
% Couette velocity.  Also measures inner/outer wall torque directly from the
% x17 kinetic impacts.  A reference viscosity is OPTIONAL: by default the
% torque law is inverted to a measured nu because the current SRC collision
% operator's angular-momentum closure is itself part of this qualification.
%
% Default paths are relative to matlab/, following the SRC workflow.
if nargin < 1 || isempty(baseRoot)
    baseRoot = '../runs/0493x19b_prescribed_rotating_annulus_pair';
end
if nargin < 2 || isempty(lateStartStep)
    lateStartStep = 5000;
end
if nargin < 3 || isempty(referenceNu)
    referenceNu = NaN;
end

cases = {'specular','bounceback'};
results = struct();
fig = figure('Name','0493x19b cylindrical Couette','Color','w');
hold on;

for ic = 1:numel(cases)
    name = cases{ic};
    runRoot = fullfile(baseRoot,name,'fresh');
    meta = read_kv_file(fullfile(runRoot,'run_meta_0493x19b.txt'));
    outDir = fullfile(runRoot,'output');

    Lx = str2double(meta.Lx); Ly = str2double(meta.Ly);
    Nx = str2double(meta.Nx); Ny = str2double(meta.Ny);
    dt = str2double(meta.dt);
    cx = str2double(meta.centerX); cy = str2double(meta.centerY);
    riNom = str2double(meta.innerRadiusNominal);
    roNom = str2double(meta.outerRadiusNominal);
    omega = str2double(meta.omegaZ);
    h = min(Lx/Nx,Ly/Ny);

    meshPath = fullfile(outDir,'chi_lagrangian_mesh_0493x17a.csv');
    [ri,ro,riStd,roStd] = effective_mesh_radii(meshPath,cx,cy,riNom,roNom);
    if ~(ri > 0 && ro > ri)
        error('0493x19b:badMesh','Invalid effective annulus radii in %s',meshPath);
    end

    files = dir(fullfile(outDir,'state_step_*.smpcd'));
    if isempty(files)
        error('0493x19b:noDumps','No state dumps found under %s',outDir);
    end
    steps = zeros(numel(files),1);
    for k=1:numel(files)
        tok = regexp(files(k).name,'state_step_(\d+)\.smpcd','tokens','once');
        steps(k)=str2double(tok{1});
    end
    [steps,ord]=sort(steps); files=files(ord);
    lateMask = steps >= lateStartStep;
    if ~any(lateMask)
        error('0493x19b:noLateDumps', ...
              'No dumps at or after step %d under %s (last available step=%d)', ...
              lateStartStep,outDir,steps(end));
    end
    files=files(lateMask); steps=steps(lateMask);

    nBins = max(16,round((ro-ri)/h));
    rEdges = linspace(ri,ro,nBins+1)';
    rCenter = 0.5*(rEdges(1:end-1)+rEdges(2:end));
    massBin=zeros(nBins,1); ptBin=zeros(nBins,1); prBin=zeros(nBins,1);
    rhoDump=nan(numel(files),1);
    for k=1:numel(files)
        S=read_smpcd_state(fullfile(files(k).folder,files(k).name));
        fluid=(S.role==1);
        x=S.x(fluid); y=S.y(fluid); vx=S.vx(fluid); vy=S.vy(fluid); m=S.mass(fluid);
        rx=x-cx; ry=y-cy; r=hypot(rx,ry);
        good=isfinite(r) & r>0 & r>=ri & r<=ro;
        rx=rx(good); ry=ry(good); r=r(good); vx=vx(good); vy=vy(good); m=m(good);
        ut=(-ry./r).*vx + (rx./r).*vy;
        ur=( rx./r).*vx + (ry./r).*vy;
        ib=discretize(r,rEdges);
        keep=~isnan(ib);
        ib=ib(keep); m=m(keep); ut=ut(keep); ur=ur(keep);
        massBin = massBin + accumarray(ib,m,[nBins 1],@sum,0);
        ptBin   = ptBin   + accumarray(ib,m.*ut,[nBins 1],@sum,0);
        prBin   = prBin   + accumarray(ib,m.*ur,[nBins 1],@sum,0);
        rhoDump(k)=sum(S.mass(fluid))/(pi*(ro^2-ri^2));
    end
    uTheta=ptBin./max(massBin,eps);
    uRadial=prBin./max(massBin,eps);
    theory=omega*ri^2/(ro^2-ri^2).*(ro^2./rCenter-rCenter);
    ui=abs(omega*ri);
    valid=massBin>0 & rCenter>(ri+1.5*h) & rCenter<(ro-1.5*h);
    err=uTheta(valid)-theory(valid);
    rmse=sqrt(mean(err.^2));
    relRmse=rmse/max(ui,eps);
    denom=sum((theory(valid)-mean(theory(valid))).^2);
    profileR2=1-sum(err.^2)/max(denom,eps);
    cc=corrcoef(uTheta(valid),theory(valid));
    if numel(cc)>=4, shapeR2=cc(1,2)^2; else, shapeR2=NaN; end
    meanAbsRadial=mean(abs(uRadial(valid)));
    radialOverUi=meanAbsRadial/max(ui,eps);
    rhoMean=mean(rhoDump,'omitnan');

    kineticPath=fullfile(outDir,'chi_kinetic_boundary_0493x16j.csv');
    K=readtable(kineticPath);
    need={'step','x19bInnerCollisions','x19bOuterCollisions','x19bInnerTorqueImpulse','x19bOuterTorqueImpulse'};
    if ~all(ismember(need,K.Properties.VariableNames))
        error('0493x19b:missingTorqueColumns','x19b torque columns missing in %s',kineticPath);
    end
    kmask=K.step>=steps(1) & K.step<=steps(end);
    if ~any(kmask)
        error('0493x19b:noLateTorque','No x19b torque rows in the late dump window');
    end
    Tin=mean(K.x19bInnerTorqueImpulse(kmask),'omitnan')/dt;
    Tout=mean(K.x19bOuterTorqueImpulse(kmask),'omitnan')/dt;
    innerCollisionMean=mean(K.x19bInnerCollisions(kmask),'omitnan');
    outerCollisionMean=mean(K.x19bOuterCollisions(kmask),'omitnan');
    torqueClosure=abs(Tin+Tout)/max([abs(Tin),abs(Tout),eps]);
    geomCoeff=4*pi*ri^2*ro^2/(ro^2-ri^2);
    muInner=-Tin/(geomCoeff*omega);
    muOuter= Tout/(geomCoeff*omega);
    nuInner=muInner/rhoMean;
    nuOuter=muOuter/rhoMean;
    if isfinite(referenceNu) && referenceNu>0
        TrefInner=-geomCoeff*rhoMean*referenceNu*omega;
        TrefOuter=-TrefInner;
        TinnerRelErr=abs(Tin-TrefInner)/max(abs(TrefInner),eps);
        TouterRelErr=abs(Tout-TrefOuter)/max(abs(TrefOuter),eps);
    else
        TrefInner=NaN; TrefOuter=NaN; TinnerRelErr=NaN; TouterRelErr=NaN;
    end

    R=struct('steps',steps,'r',rCenter,'uTheta',uTheta,'uRadial',uRadial, ...
        'theory',theory,'massBin',massBin,'riEffective',ri,'roEffective',ro, ...
        'riStd',riStd,'roStd',roStd,'rmse',rmse,'relativeRmse',relRmse, ...
        'profileR2',profileR2,'shapeR2',shapeR2,'radialOverUi',radialOverUi, ...
        'density2D',rhoMean,'innerTorque',Tin,'outerTorque',Tout, ...
        'torqueClosure',torqueClosure,'muTorqueInner',muInner,'muTorqueOuter',muOuter, ...
        'nuTorqueInner',nuInner,'nuTorqueOuter',nuOuter, ...
        'innerCollisionMean',innerCollisionMean,'outerCollisionMean',outerCollisionMean, ...
        'referenceNu',referenceNu,'referenceInnerTorque',TrefInner, ...
        'referenceOuterTorque',TrefOuter,'innerTorqueRelativeError',TinnerRelErr, ...
        'outerTorqueRelativeError',TouterRelErr);
    results.(name)=R;

    plot(rCenter(valid),uTheta(valid),'.-','DisplayName',[name ' measured']);
    if strcmp(name,'bounceback')
        plot(rCenter(valid),theory(valid),'--','LineWidth',1.2,'DisplayName','cylindrical Couette analytic');
    end

    Tprof=table(rCenter,uTheta,uRadial,theory,massBin, ...
        'VariableNames',{'r','uThetaMean','uRadialMean','uThetaTheory','sampleMass'});
    writetable(Tprof,fullfile(outDir,['profile_0493x19b_' name '.csv']));
    fid=fopen(fullfile(outDir,['summary_0493x19b_' name '.txt']),'w');
    fprintf(fid,'case=%s\n',name);
    fprintf(fid,'analysisWindowStartStep=%d\nanalysisWindowEndStep=%d\nanalysisDumpCount=%d\n',steps(1),steps(end),numel(steps));
    fprintf(fid,'lateDumpSteps=%s\n',mat2str(steps'));
    fprintf(fid,'riEffective=%.17g\nroEffective=%.17g\nriStd=%.17g\nroStd=%.17g\n',ri,ro,riStd,roStd);
    fprintf(fid,'relativeRmse=%.17g\nprofileR2=%.17g\nshapeR2=%.17g\nradialOverUi=%.17g\n',relRmse,profileR2,shapeR2,radialOverUi);
    fprintf(fid,'density2D=%.17g\ninnerTorque=%.17g\nouterTorque=%.17g\ntorqueClosure=%.17g\n',rhoMean,Tin,Tout,torqueClosure);
    fprintf(fid,'innerCollisionMean=%.17g\nouterCollisionMean=%.17g\n',innerCollisionMean,outerCollisionMean);
    fprintf(fid,'muTorqueInner=%.17g\nmuTorqueOuter=%.17g\nnuTorqueInner=%.17g\nnuTorqueOuter=%.17g\n',muInner,muOuter,nuInner,nuOuter);
    fprintf(fid,'referenceNu=%.17g\nreferenceInnerTorque=%.17g\nreferenceOuterTorque=%.17g\n',referenceNu,TrefInner,TrefOuter);
    fprintf(fid,'innerTorqueRelativeError=%.17g\nouterTorqueRelativeError=%.17g\n',TinnerRelErr,TouterRelErr);
    fprintf(fid,'torqueInterpretation=profile is an exact kinematic Couette test; torque closure/inferred viscosity also audit bulk SRC angular-momentum behavior\n');
    fclose(fid);
end

xlabel('r'); ylabel('<u_\theta>'); grid on; legend('Location','best');
title('0493x19b prescribed rotating annulus');
exportgraphics(fig,fullfile(baseRoot,'cylindrical_couette_profiles_0493x19b.png'),'Resolution',160);

fprintf('\n[0493x19b] analysis window: step >= %d\n',lateStartStep);
fprintf('[0493x19b] specular dumps = %d (%d..%d)\n',numel(results.specular.steps),results.specular.steps(1),results.specular.steps(end));
fprintf('[0493x19b] bounceback dumps = %d (%d..%d)\n',numel(results.bounceback.steps),results.bounceback.steps(1),results.bounceback.steps(end));
fprintf('[0493x19b] bounceback profile relative RMSE = %.6g\n',results.bounceback.relativeRmse);
fprintf('[0493x19b] bounceback profile R2 = %.6g ; shape R2 = %.6g\n',results.bounceback.profileR2,results.bounceback.shapeR2);
fprintf('[0493x19b] mean radial / inner-wall speed = %.6g\n',results.bounceback.radialOverUi);
fprintf('[0493x19b] wall torques: inner=% .9g outer=% .9g closure=%.6g\n', ...
    results.bounceback.innerTorque,results.bounceback.outerTorque,results.bounceback.torqueClosure);
fprintf('[0493x19b] torque-inferred nu: inner=%.9g outer=%.9g\n', ...
    results.bounceback.nuTorqueInner,results.bounceback.nuTorqueOuter);
if isfinite(referenceNu) && referenceNu>0
    fprintf('[0493x19b] reference nu=%.9g ; torque rel.errors inner=%.6g outer=%.6g\n', ...
        referenceNu,results.bounceback.innerTorqueRelativeError,results.bounceback.outerTorqueRelativeError);
else
    fprintf('[0493x19b] no reference nu supplied: torque is reported as an inferred viscosity, not graded against a historical calibration.\n');
end
fprintf('[0493x19b] NOTE: inner+outer torque closure is an explicit audit of the present SRC angular-momentum behavior; it is not assumed a priori.\n');
end

function [ri,ro,riStd,roStd]=effective_mesh_radii(path,cx,cy,riNom,roNom)
M=readtable(path);
req={'ax','ay','bx','by'};
if ~all(ismember(req,M.Properties.VariableNames)), error('Bad x17 mesh CSV: %s',path); end
mx=0.5*(M.ax+M.bx); my=0.5*(M.ay+M.by);
r=hypot(mx-cx,my-cy); len=hypot(M.bx-M.ax,M.by-M.ay);
split=0.5*(riNom+roNom);
in=r<split; out=r>split;
if nnz(in)<8 || nnz(out)<8, error('0493x19b mesh does not contain two radius branches'); end
ri=sum(r(in).*len(in))/sum(len(in)); ro=sum(r(out).*len(out))/sum(len(out));
riStd=sqrt(sum(len(in).*(r(in)-ri).^2)/sum(len(in)));
roStd=sqrt(sum(len(out).*(r(out)-ro).^2)/sum(len(out)));
if max(r(in))>=min(r(out)), error('0493x19b inner/outer mesh radii overlap'); end
end

function kv=read_kv_file(path)
fid=fopen(path,'r'); if fid<0, error('Cannot open %s',path); end
c=onCleanup(@() fclose(fid)); kv=struct();
while true
    line=fgetl(fid); if ~ischar(line), break; end
    q=strfind(line,'='); if isempty(q), continue; end
    key=strtrim(line(1:q(1)-1)); val=strtrim(line(q(1)+1:end));
    key=matlab.lang.makeValidName(key); kv.(key)=val;
end
end

function S=read_smpcd_state(path)
fid=fopen(path,'r','ieee-le'); if fid<0, error('Cannot open %s',path); end
c=onCleanup(@() fclose(fid));
magic=char(fread(fid,16,'*uint8')');
if ~startsWith(magic,'SRCMPCD_STATE'), error('Bad smpcd magic: %s',path); end
version=fread(fid,1,'uint32=>double'); endian=fread(fid,1,'uint32=>uint32');
dim=fread(fid,1,'uint32=>double'); layout=fread(fid,1,'uint32=>double');
n=fread(fid,1,'uint64=>double'); hasType=fread(fid,1,'uint32=>double');
hasMass=fread(fid,1,'uint32=>double'); realSize=fread(fid,1,'uint32=>double'); typeSize=fread(fid,1,'uint32=>double');
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
