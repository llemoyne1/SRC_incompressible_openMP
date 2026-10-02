function out = analyze_0493x23g_phase_resolved_dumps(runRoot,varargin)
%ANALYZE_0493X23G_PHASE_RESOLVED_DUMPS
% Reconstructs liquid- and gas-resolved tangential velocities directly from
% particle .smpcd dumps, independently of the LiveVis barycentric ux field.
%
% Example:
% out = analyze_0493x23g_phase_resolved_dumps( ...
%   '../runs/0493x23g_interface_quasi_isoviscous_restart_8000_to_40000_seed593172', ...
%   'StepRange',[10000 15000]);
%
% Primary outputs:
%   uL(y), uG(y), uMix(y), direct uG-uL where both phases occupy the same
%   Eulerian y-bin, and one-sided phase-resolved fit sensitivity.
%
% IMPORTANT: the bins below are physical Eulerian bins. They are not the
% randomly shifted SRC collision cells.

p=inputParser;
addRequired(p,'runRoot',@(s)ischar(s)||isstring(s));
addParameter(p,'StepRange',[NaN NaN],@(x)isnumeric(x)&&numel(x)==2);
addParameter(p,'Lx',0.5,@isscalar);
addParameter(p,'Ly',0.5,@isscalar);
addParameter(p,'Nx',128,@isscalar);
addParameter(p,'Ny',128,@isscalar);
addParameter(p,'LiquidType',1,@isscalar);
addParameter(p,'GasType',2,@isscalar);
addParameter(p,'DeltaUw',0.08,@isscalar);
addParameter(p,'BinWidthH',0.25,@isscalar);
addParameter(p,'HalfWidthH',28,@isscalar);
addParameter(p,'MinPooledCount',30,@isscalar);
parse(p,runRoot,varargin{:});
o=p.Results;
runRoot=char(runRoot);
Lx=double(o.Lx); Ly=double(o.Ly); Nx=double(o.Nx); Ny=double(o.Ny);
h=Ly/Ny; dUw=double(o.DeltaUw);
liq=uint32(o.LiquidType); gas=uint32(o.GasType);

% Locate particle dumps.
dumpDir=fullfile(runRoot,'output');
if ~isfolder(dumpDir) || isempty(dir(fullfile(dumpDir,'state_step_*.smpcd')))
    dumpDir=runRoot;
end
D=dir(fullfile(dumpDir,'state_step_*.smpcd'));
if isempty(D), error('No state_step_*.smpcd found under %s',runRoot); end
steps=nan(numel(D),1);
for k=1:numel(D)
    t=regexp(D(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(t), steps(k)=str2double(t{1}); end
end
q=isfinite(steps); D=D(q); steps=steps(q);
[steps,ord]=sort(steps); D=D(ord);
r=double(o.StepRange(:).');
keep=true(size(steps));
if isfinite(r(1)), keep=keep & steps>=r(1); end
if isfinite(r(2)), keep=keep & steps<=r(2); end
D=D(keep); steps=steps(keep);
if isempty(D), error('No dumps in requested StepRange.'); end

bw=double(o.BinWidthH); W=double(o.HalfWidthH);
edges=(-W:bw:W).'; centers=0.5*(edges(1:end-1)+edges(2:end)); nb=numel(centers);
SML=zeros(nb,1); SMG=zeros(nb,1); SPxL=zeros(nb,1); SPxG=zeros(nb,1);
SNL=zeros(nb,1); SNG=zeros(nb,1);
yGammaH=nan(numel(D),1); directSlip=nan(numel(D),1); nOverlap=zeros(numel(D),1);

fprintf('[x23g-phase] %d dumps, local steps %d..%d\n',numel(D),steps(1),steps(end));

for kd=1:numel(D)
    f=fullfile(D(kd).folder,D(kd).name);
    s=local_read_state(f);
    typ=uint32(s.type(:)); y=double(s.y(:)); vx=double(s.vx(:)); m=double(s.mass(:));
    fluid=true(s.Np,1);
    if isfield(s,'role') && ~isempty(s.role) && any(double(s.role(:))==1)
        fluid=double(s.role(:))==1;
    end
    isL=fluid & typ==liq; isG=fluid & typ==gas;
    if ~any(isL)||~any(isG), error('%s does not contain both phases.',D(kd).name); end

    % Interface from native-grid mass fraction.
    iy=floor(y/h)+1; iy=min(max(iy,1),Ny);
    MLr=accumarray(iy(isL),m(isL),[Ny 1],@sum,0);
    MGr=accumarray(iy(isG),m(isG),[Ny 1],@sum,0);
    den=MLr+MGr; YL=nan(Ny,1); qq=den>0; YL(qq)=MLr(qq)./den(qq);
    yc=((0:Ny-1)'+0.5)*h;
    yg=local_crossing(yc,YL); yGammaH(kd)=yg/h;

    % Fine phase-resolved profile after recentering this dump.
    sh=(y-yg)/h; ib=discretize(sh,edges);
    qL=isL & isfinite(ib); qG=isG & isfinite(ib);
    ML=accumarray(ib(qL),m(qL),[nb 1],@sum,0);
    MG=accumarray(ib(qG),m(qG),[nb 1],@sum,0);
    PxL=accumarray(ib(qL),m(qL).*vx(qL),[nb 1],@sum,0);
    PxG=accumarray(ib(qG),m(qG).*vx(qG),[nb 1],@sum,0);
    NL=accumarray(ib(qL),1,[nb 1],@sum,0);
    NG=accumarray(ib(qG),1,[nb 1],@sum,0);
    SML=SML+ML; SMG=SMG+MG; SPxL=SPxL+PxL; SPxG=SPxG+PxG; SNL=SNL+NL; SNG=SNG+NG;

    % Direct same-physical-bin phase difference near Gamma.
    uLd=nan(nb,1); uGd=nan(nb,1);
    uLd(ML>0)=PxL(ML>0)./ML(ML>0); uGd(MG>0)=PxG(MG>0)./MG(MG>0);
    mix=abs(centers)<=2.5 & NL>=2 & NG>=2 & ML>0 & MG>0;
    if any(mix)
        w=ML(mix).*MG(mix)./(ML(mix)+MG(mix));
        directSlip(kd)=sum(w.*(uGd(mix)-uLd(mix)))/sum(w);
        nOverlap(kd)=sum(mix);
    end
    fprintf('  step=%6d  yG/h=%8.4f  overlapBins=%2d  dU_mix/DU=% .4g\n', ...
        steps(kd),yGammaH(kd),nOverlap(kd),directSlip(kd)/dUw);
end

minN=double(o.MinPooledCount);
uL=nan(nb,1); uG=nan(nb,1); uMix=nan(nb,1);
okL=SNL>=minN & SML>0; okG=SNG>=minN & SMG>0; okT=(SNL+SNG)>=minN & (SML+SMG)>0;
uL(okL)=SPxL(okL)./SML(okL); uG(okG)=SPxG(okG)./SMG(okG);
uMix(okT)=(SPxL(okT)+SPxG(okT))./(SML(okT)+SMG(okT));
YL=nan(nb,1); dd=SML+SMG; YL(dd>0)=SML(dd>0)./dd(dd>0);
du=uG-uL;

% One-sided phase-resolved fit sensitivity.
bands=[2 6;3 8;4 10;4 12;5 12;6 16;8 20;10 24];
F=nan(size(bands,1),9);
for j=1:size(bands,1)
    d1=bands(j,1); d2=bands(j,2);
    [aL,bL,rL]=local_fit(centers,uL,-d2,-d1);
    [aG,bG,rG]=local_fit(centers,uG, d1, d2);
    F(j,:)=[d1 d2 aL aG rL rG bL bG (bG-bL)/dUw];
end

outDir=fullfile(runRoot,'analysis_phase_resolved_0493x23g');
if ~isfolder(outDir), mkdir(outDir); end
T=table(centers,SNL,SNG,SML,SMG,YL,uL,uG,uMix,du, ...
 'VariableNames',{'sOverH','countL','countG','massL','massG','YL','uL','uG','uMix','uGminusUL'});
writetable(T,fullfile(outDir,'phase_resolved_profile_0493x23g.csv'));
Tf=array2table(F,'VariableNames',{'dMinH','dMaxH','aL','aG','R2L','R2G','uGammaL','uGammaG','slipOverDeltaUw'});
writetable(Tf,fullfile(outDir,'phase_resolved_fit_bands_0493x23g.csv'));
Td=table(steps,yGammaH,nOverlap,directSlip/dUw,'VariableNames', ...
 {'step','yGammaOverH','overlapBinCount','directOverlapSlipOverDeltaUw'});
writetable(Td,fullfile(outDir,'phase_resolved_dump_diagnostics_0493x23g.csv'));

% Figure 1: key verdict -- mixture vs phase-resolved velocities.
f1=figure('Name','0493x23g phase-resolved interface','Color','w');
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
nexttile;
plot(centers,uMix/dUw,'-','DisplayName','mixture'); hold on;
plot(centers,uL/dUw,'o-','MarkerSize',3,'DisplayName','liquid');
plot(centers,uG/dUw,'s-','MarkerSize',3,'DisplayName','gas');
xline(0,':','Gamma'); xlim([-W W]); grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('u_x/\Delta U_w'); title('Phase-resolved particle profile'); legend('Location','best');
nexttile;
plot(centers,uMix/dUw,'-','DisplayName','mixture'); hold on;
plot(centers,uL/dUw,'o-','MarkerSize',4,'DisplayName','liquid');
plot(centers,uG/dUw,'s-','MarkerSize',4,'DisplayName','gas');
xline(0,':','Gamma'); xlim([-6 6]); grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('u_x/\Delta U_w'); title('Zoom: kinetic interface layer'); legend('Location','best');
nexttile;
plot(centers,YL,'-','DisplayName','Y_L'); hold on; plot(centers,1-YL,'--','DisplayName','Y_G');
xline(0,':','Gamma'); yline(0.5,':'); xlim([-6 6]); ylim([-0.05 1.05]); grid on;
xlabel('(y-y_\Gamma)/h'); ylabel('mass fraction'); title('Particle composition'); legend('Location','best');
nexttile;
both=isfinite(du);
plot(centers(both),du(both)/dUw,'o-'); hold on; yline(0,':'); xline(0,':','Gamma');
xlim([-6 6]); grid on; xlabel('(y-y_\Gamma)/h'); ylabel('(u_G-u_L)/\Delta U_w');
title('Direct phase difference where both are resolved');
sgtitle(sprintf('0493x23g particle dumps, local steps %d--%d, bin %.2fh',steps(1),steps(end),bw));
exportgraphics(f1,fullfile(outDir,'phase_resolved_profile_0493x23g.png'),'Resolution',180);

% Figure 2: fit sensitivity and direct per-dump overlap signal.
f2=figure('Name','0493x23g phase-resolved diagnostics','Color','w');
tiledlayout(2,2,'Padding','compact','TileSpacing','compact');
nexttile; plot(steps,yGammaH,'o-'); grid on; xlabel('local restart step'); ylabel('y_\Gamma/h'); title('Particle interface position');
nexttile; plot(steps,directSlip/dUw,'o-'); hold on; yline(0,':'); grid on;
xlabel('local restart step'); ylabel('\Delta u_{G-L}^{same bin}/\Delta U_w'); title('Direct same-Eulerian-bin phase difference');
nexttile; plot(1:size(F,1),F(:,3),'o-','DisplayName','a_L'); hold on; plot(1:size(F,1),F(:,4),'s-','DisplayName','a_G');
xticks(1:size(F,1)); xticklabels(compose('%g-%g',bands(:,1),bands(:,2))); xtickangle(35); grid on;
xlabel('[d_{min},d_{max}]/h'); ylabel('slope'); title('Phase-resolved fit sensitivity'); legend('Location','best');
nexttile; plot(1:size(F,1),F(:,9),'o-'); hold on; yline(0,':');
xticks(1:size(F,1)); xticklabels(compose('%g-%g',bands(:,1),bands(:,2))); xtickangle(35); grid on;
xlabel('[d_{min},d_{max}]/h'); ylabel('(u_G^\Gamma-u_L^\Gamma)/\Delta U_w'); title('Phase-resolved extrapolated offset');
exportgraphics(f2,fullfile(outDir,'phase_resolved_diagnostics_0493x23g.png'),'Resolution',180);

% Text summary.
fid=fopen(fullfile(outDir,'phase_resolved_summary_0493x23g.txt'),'w');
fprintf(fid,'===== 0493x23g PHASE-RESOLVED PARTICLE DUMPS =====\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'dumps = %d ; local steps = [%d,%d]\n',numel(D),steps(1),steps(end));
fprintf(fid,'binWidth = %.6g h ; liquidType=%d gasType=%d\n',bw,double(liq),double(gas));
fprintf(fid,'yGamma/h mean +/- std = %.12g +/- %.12g\n',mean(yGammaH,'omitnan'),std(yGammaH,'omitnan'));
qo=isfinite(directSlip);
if any(qo)
 fprintf(fid,'direct same-Eulerian-bin slip/DeltaUw mean +/- std = %.12g +/- %.12g (%d/%d dumps)\n', ...
   mean(directSlip(qo)/dUw),std(directSlip(qo)/dUw),sum(qo),numel(D));
else
 fprintf(fid,'direct same-Eulerian-bin slip unavailable: no sufficiently populated bins containing both phases.\n');
end
fprintf(fid,'\nPHASE-RESOLVED FIT SENSITIVITY\n');
fprintf(fid,'band[h]       aL           aG       R2L      R2G      uGammaL      uGammaG     slip/DU\n');
for j=1:size(F,1)
 fprintf(fid,'[%4.1f,%4.1f] %12.6g %12.6g %8.4f %8.4f %12.6g %12.6g %12.6g\n',F(j,:));
end
fprintf(fid,'\nInterpretation:\n');
fprintf(fid,'If the sharp interface dip remains only in uMix while uL/uG are smooth, it is mainly a barycentric-mixture observable.\n');
fprintf(fid,'If uL and/or uG themselves bend near Gamma, the kinetic layer is phase-resolved and is not merely a LiveVis mixture artifact.\n');
fprintf(fid,'Same-bin differences refer to fixed physical Eulerian bins, not randomly shifted SRC collision cells.\n');
fclose(fid);

out=struct('runRoot',runRoot,'outDir',outDir,'steps',steps,'sOverH',centers, ...
 'uL',uL,'uG',uG,'uMix',uMix,'YL',YL,'uGminusUL',du, ...
 'fitBands',Tf,'dumpDiagnostics',Td);

fprintf('[x23g-phase] DONE -> %s\n',outDir);
end

function yg=local_crossing(yc,YL)
q=isfinite(YL);
i=find(q(1:end-1)&q(2:end)&YL(1:end-1)>=0.5&YL(2:end)<0.5,1,'first');
if isempty(i)
    iq=find(q); [~,j]=min(abs(YL(iq)-0.5)); yg=yc(iq(j)); return;
end
f0=YL(i)-0.5; f1=YL(i+1)-0.5;
if abs(f1-f0)<eps, yg=0.5*(yc(i)+yc(i+1));
else, yg=yc(i)-f0*(yc(i+1)-yc(i))/(f1-f0); end
end

function [a,b,r2]=local_fit(x,u,xmin,xmax)
q=isfinite(x)&isfinite(u)&x>=xmin&x<=xmax;
if sum(q)<3, a=NaN;b=NaN;r2=NaN;return; end
pp=polyfit(x(q),u(q),1); a=pp(1); b=pp(2); yh=polyval(pp,x(q)); yy=u(q);
sst=sum((yy-mean(yy)).^2); ssr=sum((yy-yh).^2);
if sst>0, r2=1-ssr/sst; else, r2=NaN; end
end

function s=local_read_state(filename)
if exist('read_smpcd_state','file')==2, s=read_smpcd_state(filename); return; end
fid=fopen(filename,'r','ieee-le'); if fid<0,error('Cannot open %s',filename);end
c=onCleanup(@()fclose(fid)); %#ok<NASGU>
magic=fread(fid,16,'uint8=>uint8'); ex=uint8(zeros(16,1)); tag=uint8('SRCMPCD_STATE'); ex(1:numel(tag))=tag;
if numel(magic)~=16||any(magic~=ex),error('Bad smpcd magic');end
ver=fread(fid,1,'uint32=>uint32'); endian=fread(fid,1,'uint32=>uint32'); dim=fread(fid,1,'uint32=>uint32'); layout=fread(fid,1,'uint32=>uint32');
Np=fread(fid,1,'uint64=>uint64'); hasType=fread(fid,1,'uint32=>uint32'); hasMass=fread(fid,1,'uint32=>uint32'); realSize=fread(fid,1,'uint32=>uint32'); typeSize=fread(fid,1,'uint32=>uint32'); res=fread(fid,8,'uint64=>uint64');
if ~(ver==1||ver==2)||endian~=hex2dec('01020304')||dim~=2||layout~=1||hasType~=1||hasMass~=1||realSize~=8||typeSize~=4,error('Unsupported smpcd format');end
n=double(Np); s=struct(); s.Np=n; s.x=fread(fid,n,'double=>double'); s.y=fread(fid,n,'double=>double'); s.vx=fread(fid,n,'double=>double'); s.vy=fread(fid,n,'double=>double'); s.type=fread(fid,n,'uint32=>uint32'); s.mass=fread(fid,n,'double=>double');
if ver>=2 && numel(res)>=2 && res(2)~=0, s.role=fread(fid,n,'uint8=>uint8'); else, s.role=ones(n,1,'uint8'); end
end
