function out = analyze_0493x8d_q6gf_poiseuille_qualification(rootDir, varargin)
%ANALYZE_0493X8D_Q6GF_POISEUILLE_QUALIFICATION
% Independent physical qualification of Q6-g-f against analytical channel
% solutions.  No SRC/Q6 comparison is used.
%
%   out = analyze_0493x8d_q6gf_poiseuille_qualification( ...
%       'runs/0493x8d_q6gf_poiseuille_qualification');
%
% Requirements: existing repository helpers
%   analyze_poiseuille_profile, list_smpcd_dumps,
%   read_smpcd_state, bin_smpcd_state.
%
% Solid case:
%   - periodic x, physical no-slip wall model in y;
%   - standard Poiseuille profile fit + independent free-intercept fit
%     U(y)=A*y*(H-y)+B, where B is extrapolated wall slip.
%
% Chi case:
%   - periodic x/y;
%   - planar binary chi=0 Brinkman slab;
%   - no physical wall, no chi collision VP;
%   - steady profile fitted to the exact piecewise Brinkman solution.
%
% The historical 0493w1 ensemble reference is a comparison target only:
% nu=5.9751e-4, cs=.35459, Dself=1.6588e-4.  Both x8d runners preserve
% a=1/256, gamma=20, dt=.002, kBT=.125, m=1 and 90-degree SRD rotation.

p = inputParser;
addRequired(p,'rootDir',@(s)ischar(s)||isstring(s));
addParameter(p,'referenceNu',5.9751e-4,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'referenceCs',0.35459,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'referenceDself',1.6588e-4,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'referenceUchar',0.1064,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'referenceL',0.24,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'solidFitStartFraction',0.60,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<1);
addParameter(p,'chiFitStartFraction',0.60,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<1);
addParameter(p,'makePlots',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'savePlots',true,@(x)islogical(x)||isnumeric(x));
addParameter(p,'writeCsv',true,@(x)islogical(x)||isnumeric(x));
parse(p,rootDir,varargin{:});
opt=p.Results;
rootDir=char(rootDir);

solidOut=fullfile(rootDir,'solid','src-q6-g-f','output');
chiOut=fullfile(rootDir,'chi','src-q6-g-f','output');
if ~isfolder(solidOut), error('x8d:missingSolid','Missing %s',solidOut); end
if ~isfolder(chiOut), error('x8d:missingChi','Missing %s',chiOut); end

%% Solid-wall Poiseuille
solid = analyze_poiseuille_profile(solidOut, ...
    'flowComponent','Ux','profileDirection','y', ...
    'fitStartFraction',opt.solidFitStartFraction, ...
    'excludeWallCells',2, ...
    'makePlots',false,'plotConvergence',false, ...
    'saveTables',false,'saveMat',false);

ps = local_load_params(solidOut);
Hs = local_num(ps,'Ly');
axs = local_num(ps,'bodyAccelerationX');
ys = double(solid.coord(:));
us = double(solid.avgProfile(:));
valid=isfinite(ys)&isfinite(us);
q=ys(valid).*(Hs-ys(valid));
X=[q,ones(size(q))];
coef=X\us(valid);
A=coef(1); B=coef(2);
ufree=X*coef;
r2free=local_r2(us(valid),ufree);
nuSolidFree=axs/(2*A);
uCenterFree=A*Hs^2/4+B;
slipOverCenter=abs(B)/max(abs(uCenterFree),eps);

solidSummary=table( ...
    solid.fit.nuEff, solid.fit.r2, nuSolidFree, r2free, B, slipOverCenter, ...
    solid.meanVelocity, solid.uCenter, solid.wallVelocityLow, solid.wallVelocityHigh, ...
    (solid.fit.nuEff-opt.referenceNu)/opt.referenceNu, ...
    (nuSolidFree-opt.referenceNu)/opt.referenceNu, ...
    solid.uCenter*opt.referenceL/solid.fit.nuEff, ...
    solid.uCenter/opt.referenceCs, ...
    'VariableNames',{'nuConstrained','r2Constrained','nuFreeIntercept','r2FreeIntercept', ...
    'extrapolatedSlip','absSlipOverCenter','meanU','centerU','firstCellLowU','firstCellHighU', ...
    'nuConstrainedRelVsRef','nuFreeRelVsRef','ReFromMeasuredCenter','MaFromMeasuredCenter'});

%% Periodic planar Brinkman/chi
pc=local_load_params(chiOut);
Lx=local_num(pc,'Lx'); Ly=local_num(pc,'Ly');
Nx=round(local_num(pc,'Nx')); Ny=round(local_num(pc,'Ny'));
ax=local_num(pc,'bodyAccelerationX');
alpha=local_num(pc,'darcyAlphaMax');
alphaMin=local_num(pc,'darcyAlphaMin');
if abs(alphaMin)>1e-15
    error('x8d:alphaMin','x8d analytic chi qualification requires alphaMin=0');
end

chiPath=local_string(pc,'darcyChiFile');
chiPath=['../' chiPath];
if ~isfile(chiPath)
    alt=fullfile(fileparts(fileparts(chiOut)),chiPath);
    if isfile(alt), chiPath=alt; end
end
chiField=local_read_chi(chiPath,Nx,Ny);
rowChi=mean(chiField,2);
penRows=find(rowChi<0.5);
if isempty(penRows), error('x8d:noChiWall','No penalized chi rows found'); end
if any(diff(penRows)~=1) || penRows(1)~=1
    error('x8d:chiLayout','Expected one chi=0 slab starting at y=0');
end

dy=Ly/Ny;
S=numel(penRows)*dy;
H=Ly-S;
frames=list_smpcd_dumps(chiOut);
if height(frames)<2, error('x8d:noChiDumps','Need at least two chi dumps'); end
n=height(frames);
start=max(1,floor(opt.chiFitStartFraction*n)+1);
profiles=nan(Ny,n-start+1);
times=nan(n-start+1,1);
jj=0;
for k=start:n
    jj=jj+1;
    state=read_smpcd_state(char(frames.fullPath(k)));
    fields=bin_smpcd_state(state,'Lx',Lx,'Ly',Ly,'Nx',Nx,'Ny',Ny, ...
        'periodicX',true,'periodicY',true);
    Ux=double(fields.Ux);
    Ux(~isfinite(Ux))=NaN;
    profiles(:,jj)=mean(Ux,2,'omitnan');
    times(jj)=frames.time(k);
end
uChi=mean(profiles,2,'omitnan');
yc=((0:Ny-1)'+0.5)*dy;

% Fit viscosity against the entire exact piecewise steady Brinkman profile.
obj=@(nu)local_mse(uChi,local_brinkman_profile(yc,Ly,S,H,ax,alpha,nu));
lo=0.25*opt.referenceNu; hi=4.0*opt.referenceNu;
nuChiFull=fminbnd(obj,lo,hi);
uFitFull=local_brinkman_profile(yc,Ly,S,H,ax,alpha,nuChiFull);
r2ChiFull=local_r2(uChi,uFitFull);

% Independent fluid-only fit: U=A*z*(H-z)+B.
fluid=(yc>S);
z=yc(fluid)-S;
uf=uChi(fluid);
Xf=[z.*(H-z),ones(size(z))];
cf=Xf\uf;
Af=cf(1); Bf=cf(2);
nuChiFluid=ax/(2*Af);
uFitFluid=Xf*cf;
r2ChiFluid=local_r2(uf,uFitFluid);

[kRef,uIRef,uMeanRef,uCenterRef,ellRef]=local_brinkman_scalars(H,S,ax,alpha,opt.referenceNu);
[kFit,uIFit,uMeanFit,uCenterFit,ellFit]=local_brinkman_scalars(H,S,ax,alpha,nuChiFull);

l2Ref=sqrt(mean((uChi-local_brinkman_profile(yc,Ly,S,H,ax,alpha,opt.referenceNu)).^2,'omitnan')) / ...
    max(sqrt(mean(uChi.^2,'omitnan')),eps);
l2Fit=sqrt(mean((uChi-uFitFull).^2,'omitnan')) / max(sqrt(mean(uChi.^2,'omitnan')),eps);
linfFit=max(abs(uChi-uFitFull),[],'omitnan')/max(max(abs(uChi),[],'omitnan'),eps);

chiSummary=table( ...
    nuChiFull,r2ChiFull,nuChiFluid,r2ChiFluid,Bf,uIRef,uIFit, ...
    mean(uf,'omitnan'),uMeanRef,uMeanFit,max(uf,[],'omitnan'),uCenterRef,uCenterFit, ...
    ellRef/dy,ellFit/dy,alpha*local_num(pc,'dt'), ...
    (nuChiFull-opt.referenceNu)/opt.referenceNu, ...
    (nuChiFluid-opt.referenceNu)/opt.referenceNu, ...
    l2Ref,l2Fit,linfFit, ...
    max(uf,[],'omitnan')*opt.referenceL/nuChiFull, ...
    max(uf,[],'omitnan')/opt.referenceCs, ...
    'VariableNames',{'nuFullBrinkman','r2FullBrinkman','nuFluidParabola','r2FluidParabola', ...
    'measuredInterfaceSlipExtrap','referenceInterfaceSlip','fittedInterfaceSlip', ...
    'measuredFluidMeanU','referenceFluidMeanU','fittedFluidMeanU', ...
    'measuredFluidMaxU','referenceCenterU','fittedCenterU', ...
    'referenceEllBCells','fittedEllBCells','alphaDt', ...
    'nuFullRelVsRef','nuFluidRelVsRef','profileL2VsReferenceNu','profileL2VsFittedNu', ...
    'profileLinfVsFittedNu','ReFromMeasuredMax','MaFromMeasuredMax'});

%% Cross-qualification: same effective viscosity?
nuSolid=solid.fit.nuEff;
nuChi=nuChiFull;
cross=table(opt.referenceNu,opt.referenceCs,opt.referenceDself, ...
    opt.referenceUchar,opt.referenceL, ...
    opt.referenceUchar*opt.referenceL/opt.referenceNu, ...
    opt.referenceUchar/opt.referenceCs, ...
    nuSolid,nuChi,(nuChi-nuSolid)/nuSolid, ...
    'VariableNames',{'referenceNu','referenceCs','referenceDself','referenceUchar','referenceL', ...
    'referenceRe','referenceMa','solidNu','chiNu','chiMinusSolidNuRelative'});

out=struct();
out.solid=solid;
out.solidSummary=solidSummary;
out.chiSummary=chiSummary;
out.cross=cross;
out.chi=struct('yc',yc,'measured',uChi,'fitFull',uFitFull, ...
    'referenceProfile',local_brinkman_profile(yc,Ly,S,H,ax,alpha,opt.referenceNu), ...
    'chiRowMean',rowChi,'lateTimes',times,'S',S,'H',H);

analysisDir=fullfile(rootDir,'analysis_x8d');
if ~isfolder(analysisDir), mkdir(analysisDir); end
if logical(opt.writeCsv)
    writetable(solidSummary,fullfile(analysisDir,'0493x8d_solid_summary.csv'));
    writetable(chiSummary,fullfile(analysisDir,'0493x8d_chi_summary.csv'));
    writetable(cross,fullfile(analysisDir,'0493x8d_cross_summary.csv'));
    writetable(table(yc,uChi,uFitFull,out.chi.referenceProfile,rowChi, ...
        'VariableNames',{'y','Umeasured','Ufitted','UreferenceNu','chi'}), ...
        fullfile(analysisDir,'0493x8d_chi_profile.csv'));
    writetable(table(ys,us,solid.fit.fitProfile(:), ...
        'VariableNames',{'y','Umeasured','UnoSlipFit'}), ...
        fullfile(analysisDir,'0493x8d_solid_profile.csv'));
end

if logical(opt.makePlots)
    f1=figure('Name','0493x8d Q6-g-f physical-wall Poiseuille');
    plot(ys,us,'o','DisplayName','Q6-g-f measured'); hold on; grid on;
    plot(ys,solid.fit.fitProfile(:),'-','DisplayName','no-slip Poiseuille fit');
    plot(ys,A*ys.*(Hs-ys)+B,'--','DisplayName','free-intercept fit');
    xlabel('y'); ylabel('U_x');
    title('Q6-g-f physical-wall Poiseuille');
    legend('Location','best');
    if logical(opt.savePlots), saveas(f1,fullfile(analysisDir,'0493x8d_solid_profile.png')); end

    f2=figure('Name','0493x8d Q6-g-f planar Brinkman');
    plot(yc,uChi,'o','DisplayName','Q6-g-f measured'); hold on; grid on;
    plot(yc,uFitFull,'-','DisplayName','Brinkman fit');
    plot(yc,out.chi.referenceProfile,'--','DisplayName','Brinkman at 0493w1 \nu');
    xline(S,':','chi interface');
    xlabel('y'); ylabel('U_x');
    title('Q6-g-f periodic planar \chi/Brinkman Poiseuille');
    legend('Location','best');
    if logical(opt.savePlots), saveas(f2,fullfile(analysisDir,'0493x8d_chi_profile.png')); end
end

fprintf('\n===== 0493x8d Q6-G-F INDEPENDENT POISEUILLE QUALIFICATION =====\n');
fprintf('Reference a256_dt002_k125: nu=%.8g cs=%.8g Uchar=%.8g Lref=%.8g Re=%.5f Ma=%.5f\n', ...
    opt.referenceNu,opt.referenceCs,opt.referenceUchar,opt.referenceL, ...
    opt.referenceUchar*opt.referenceL/opt.referenceNu,opt.referenceUchar/opt.referenceCs);
fprintf('\n--- PHYSICAL SOLID WALL ---\n');
disp(solidSummary);
fprintf('\n--- PERIODIC PLANAR CHI / BRINKMAN WALL ---\n');
disp(chiSummary);
fprintf('\n--- CROSS CHECK ---\n');
disp(cross);
fprintf('Interpretation:\n');
fprintf('  1) solid nu should reproduce the calibrated transport scale and R2 should remain high;\n');
fprintf('  2) extrapolated solid-wall slip should be small relative to center speed;\n');
fprintf('  3) chi profile should follow the analytical Brinkman profile with ell_B resolved;\n');
fprintf('  4) chi-fitted nu should agree with solid-wall Q6-g-f nu, not merely with SRC by construction.\n');
fprintf('status=COMPLETE\n');

end

function u=local_brinkman_profile(y,Ly,S,H,ax,alpha,nu)
k=sqrt(alpha/nu);
sh=sinh(k*S/2);
if ~(isfinite(sh)&&abs(sh)>eps)
    error('x8d:badBrinkman','Invalid k*S/2');
end
A=ax*H/(2*nu*k*sh);
uI=ax/alpha + ax*H/(2*nu*k)*(cosh(k*S/2)/sh);
u=nan(size(y));
wall=(y<S);
u(wall)=ax/alpha + A*cosh(k*(y(wall)-S/2));
z=y(~wall)-S;
u(~wall)=ax/(2*nu).*z.*(H-z)+uI;
end

function [k,uI,uMean,uCenter,ell]=local_brinkman_scalars(H,S,ax,alpha,nu)
k=sqrt(alpha/nu); ell=1/k;
cothv=cosh(k*S/2)/sinh(k*S/2);
uI=ax/alpha + ax*H/(2*nu*k)*cothv;
uMean=ax*H^2/(12*nu)+uI;
uCenter=ax*H^2/(8*nu)+uI;
end

function v=local_mse(a,b)
d=a-b; d=d(isfinite(d));
if isempty(d), v=Inf; else, v=mean(d.^2); end
end

function r2=local_r2(y,yhat)
m=isfinite(y)&isfinite(yhat); y=y(m); yhat=yhat(m);
ssr=sum((y-yhat).^2); sst=sum((y-mean(y)).^2);
r2=1-ssr/max(sst,eps);
end

function chi=local_read_chi(pathe,Nx,Ny)
fid=fopen(pathe,'rb');
if fid<0, error('x8d:chiOpen','Cannot open %s',pathe); end
c=onCleanup(@()fclose(fid));
raw=fread(fid,Nx*Ny,'single=>double');
if numel(raw)~=Nx*Ny, error('x8d:chiSize','Bad chi size'); end
chi=reshape(raw,[Nx,Ny])';
end

function p=local_load_params(outDir)
pathe=fullfile(outDir,'params_used.kv');
if ~isfile(pathe)
    runDir=fileparts(outDir);
    d=dir(fullfile(runDir,'params','*.kv'));
    if numel(d)~=1, error('x8d:params','Cannot resolve params for %s',outDir); end
    pathe=fullfile(d(1).folder,d(1).name);
end
txt=splitlines(string(fileread(pathe)));
p=struct();
for i=1:numel(txt)
    s=strtrim(extractBefore(txt(i)+"#","#"));
    if strlength(s)==0 || ~contains(s,"="), continue; end
    parts=split(s,"=",2);
    key=matlab.lang.makeValidName(strtrim(parts(1)));
    p.(key)=strtrim(parts(2));
end
p.path=string(pathe);
end

function x=local_num(p,key)
f=matlab.lang.makeValidName(key);
if ~isfield(p,f), error('x8d:paramMissing','Missing %s in %s',key,p.path); end
x=str2double(p.(f));
if ~isfinite(x), error('x8d:paramBad','Bad numeric %s',key); end
end

function s=local_string(p,key)
f=matlab.lang.makeValidName(key);
if ~isfield(p,f), error('x8d:paramMissing','Missing %s in %s',key,p.path); end
s=char(p.(f));
end
