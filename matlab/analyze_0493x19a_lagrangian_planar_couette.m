function results = analyze_0493x19a_lagrangian_planar_couette(baseRoot, lateStartStep)
% 0493x19a: compare the x17 specular ablation and deterministic moving-wall
% bounce-back against the exact planar Couette profile. Reads only .smpcd dumps.
% Default path is relative to matlab/, as required by the SRC workflow.
if nargin < 1 || isempty(baseRoot)
    baseRoot = '../runs/0493x19a_lagrangian_planar_couette_pair';
end
if nargin < 2 || isempty(lateStartStep)
    lateStartStep = 5000;
end
cases = {'specular','bounceback'};
results = struct();
figure('Name','0493x19a planar Couette'); hold on;
for ic = 1:numel(cases)
    name = cases{ic};
    runRoot = fullfile(baseRoot,name,'fresh');
    meta = read_kv_file(fullfile(runRoot,'run_meta_0493x19a.txt'));
    outDir = fullfile(runRoot,'output');
    files = dir(fullfile(outDir,'state_step_*.smpcd'));
    if isempty(files)
        error('0493x19a:noDumps','No state dumps found under %s',outDir);
    end
    steps = zeros(numel(files),1);
    for k=1:numel(files)
        tok = regexp(files(k).name,'state_step_(\d+)\.smpcd','tokens','once');
        steps(k)=str2double(tok{1});
    end
    [steps,ord]=sort(steps); files=files(ord);
    lateMask = steps >= lateStartStep;
    if ~any(lateMask)
        error('0493x19a:noLateDumps', ...
              'No dumps at or after step %d under %s (last available step=%d)', ...
              lateStartStep,outDir,steps(end));
    end
    files=files(lateMask); steps=steps(lateMask);

    ny = str2double(meta.Ny); ly=str2double(meta.Ly);
    ymin=str2double(meta.slabYMin); ymax=str2double(meta.slabYMax);
    uw=str2double(meta.wallSpeedX);
    sumUx=zeros(ny,1); count=zeros(ny,1);
    for k=1:numel(files)
        S=read_smpcd_state(fullfile(files(k).folder,files(k).name));
        fluid=(S.role==1);
        y=S.y(fluid); ux=S.vx(fluid);
        iy=floor(y/ly*ny)+1; iy=max(1,min(ny,iy));
        for p=1:numel(iy)
            c=iy(p); sumUx(c)=sumUx(c)+ux(p); count(c)=count(c)+1;
        end
    end
    yc=((0:ny-1)'+0.5)*ly/ny;
    uxMean=sumUx./max(count,1);
    valid=count>0 & (yc<ymin | yc>ymax);
    uth=nan(ny,1);
    bottom=yc<ymin; top=yc>ymax;
    uth(bottom)=uw*yc(bottom)/ymin;
    uth(top)=uw*(ly-yc(top))/(ly-ymax);
    err=uxMean(valid)-uth(valid);
    rmse=sqrt(mean(err.^2)); relRmse=rmse/max(abs(uw),eps);
    corrNum=sum((uxMean(valid)-mean(uxMean(valid))).*(uth(valid)-mean(uth(valid))));
    corrDen=sqrt(sum((uxMean(valid)-mean(uxMean(valid))).^2)*sum((uth(valid)-mean(uth(valid))).^2));
    r2corr=(corrNum/max(corrDen,eps))^2;
    lateMeanUx=mean(uxMean(valid));

    R=struct('steps',steps,'y',yc,'ux',uxMean,'theory',uth,'count',count,...
             'rmse',rmse,'relativeRmse',relRmse,'shapeR2',r2corr,'lateMeanUx',lateMeanUx);
    results.(name)=R;
    plot(yc(valid),uxMean(valid),'.-','DisplayName',[name ' measured']);
    if strcmp(name,'bounceback')
        plot(yc(valid),uth(valid),'--','DisplayName','Couette analytic');
    end

    T=table(yc,uxMean,uth,count,'VariableNames',{'y','uxMean','uxTheory','samples'});
    writetable(T,fullfile(outDir,['profile_0493x19a_' name '.csv']));
    fid=fopen(fullfile(outDir,['summary_0493x19a_' name '.txt']),'w');
    fprintf(fid,'case=%s\n',name);
    fprintf(fid,'analysisWindowStartStep=%d\n',steps(1));
    fprintf(fid,'analysisWindowEndStep=%d\n',steps(end));
    fprintf(fid,'analysisDumpCount=%d\n',numel(steps));
    fprintf(fid,'lateDumpSteps=%s\n',mat2str(steps'));
    fprintf(fid,'rmse=%.17g\nrelativeRmse=%.17g\nshapeR2=%.17g\nlateMeanUx=%.17g\n',rmse,relRmse,r2corr,lateMeanUx);
    fclose(fid);
end
xlabel('y'); ylabel('<u_x>'); grid on; legend('Location','best');
title('0493x19a Lagrangian moving-wall planar Couette');
exportgraphics(gcf,fullfile(baseRoot,'couette_profiles_0493x19a.png'),'Resolution',160);

fprintf('\n[0493x19a] analysis window: step >= %d\n',lateStartStep);
fprintf('[0493x19a] specular dumps used = %d (%d..%d)\n', ...
        numel(results.specular.steps),results.specular.steps(1),results.specular.steps(end));
fprintf('[0493x19a] bounceback dumps used = %d (%d..%d)\n', ...
        numel(results.bounceback.steps),results.bounceback.steps(1),results.bounceback.steps(end));
fprintf('[0493x19a] specular relative RMSE = %.6g\n',results.specular.relativeRmse);
fprintf('[0493x19a] bounceback relative RMSE = %.6g\n',results.bounceback.relativeRmse);
fprintf('[0493x19a] bounceback shape R2 = %.6g\n',results.bounceback.shapeR2);
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
