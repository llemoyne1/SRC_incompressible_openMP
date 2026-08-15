function out=analyze_0493x8e_q6gf_darcy_alpha_sweep(rootDir,varargin)
% 0493x8e fix1
% Robust path handling when MATLAB is launched from <repo>/matlab.
% Repo root is inferred from this file location; repo-relative paths stored
% in params_used.kv are resolved against that root.

p=inputParser;
addRequired(p,'rootDir',@(s)ischar(s)||isstring(s));
addParameter(p,'nuReference',7.0604e-4,@(x)isnumeric(x)&&isscalar(x)&&x>0);
addParameter(p,'fitStartFraction',0.60,@(x)isnumeric(x)&&isscalar(x)&&x>=0&&x<1);
parse(p,rootDir,varargin{:});
o=p.Results;

thisFile=mfilename('fullpath');
repoRoot=fileparts(fileparts(thisFile));
rootDir=char(rootDir);

% Resolve the requested run root robustly.
rootDir=resolvepath(rootDir,repoRoot,pwd);
manifestPath=fullfile(rootDir,'sweep_manifest_0493x8e.csv');
if ~isfile(manifestPath)
    error('x8e:manifestMissing', ...
        'Missing sweep manifest: %s\nrepoRoot=%s\npwd=%s', ...
        manifestPath,repoRoot,pwd);
end

M=readtable(manifestPath,'TextType','string');
n=height(M);

caseName=M.caseName;
targetEllBOverA=M.targetEllBOverA;
alpha=M.alpha;
alphaDt=M.alphaDt;

nuFull=nan(n,1);
r2Full=nan(n,1);
nuFluid=nan(n,1);
r2Fluid=nan(n,1);
fittedEllBOverA=nan(n,1);
slipRelErr=nan(n,1);
meanRelErr=nan(n,1);
maxRelErr=nan(n,1);
L2ref=nan(n,1);
L2fit=nan(n,1);
Linffit=nan(n,1);

for ic=1:n
    od=fullfile(rootDir,char(caseName(ic)),'src-q6-g-f','output');
    if ~isfolder(od)
        error('x8e:missingOutput','Missing output directory: %s',od);
    end

    P=loadparams(od);
    Lx=num(P,'Lx');
    Ly=num(P,'Ly');
    Nx=round(num(P,'Nx'));
    Ny=round(num(P,'Ny'));
    ax=num(P,'bodyAccelerationX');
    a=Ly/Ny;

    cpRaw=str(P,'darcyChiFile');
    cp=resolvepath(cpRaw,repoRoot,fileparts(P.path));
    fprintf('[0493x8e-mat] case=%s chi=%s\n',char(caseName(ic)),cp);

    chi=readchi(cp,Nx,Ny);
    pen=find(mean(chi,2)<.5);
    if isempty(pen) || pen(1)~=1 || any(diff(pen)~=1)
        error('x8e:chiLayout', ...
            'Expected one contiguous chi=0 slab starting at row 1 in %s',cp);
    end

    S=numel(pen)*a;
    H=Ly-S;
    y=((0:Ny-1)'+.5)*a;

    F=list_smpcd_dumps(od);
    if height(F)<2
        error('x8e:noDumps','Need at least two dumps in %s',od);
    end

    st=max(1,floor(o.fitStartFraction*height(F))+1);
    U=nan(Ny,height(F)-st+1);
    jj=0;
    for k=st:height(F)
        jj=jj+1;
        s=read_smpcd_state(char(F.fullPath(k)));
        f=bin_smpcd_state(s, ...
            'Lx',Lx,'Ly',Ly,'Nx',Nx,'Ny',Ny, ...
            'periodicX',true,'periodicY',true);
        ux=double(f.Ux);
        ux(~isfinite(ux))=NaN;
        U(:,jj)=mean(ux,2,'omitnan');
    end
    u=mean(U,2,'omitnan');

    obj=@(nu0)mse(u,profile(y,S,H,ax,alpha(ic),nu0));
    nuFull(ic)=fminbnd(obj,.2*o.nuReference,5*o.nuReference);

    fit=profile(y,S,H,ax,alpha(ic),nuFull(ic));
    ref=profile(y,S,H,ax,alpha(ic),o.nuReference);
    r2Full(ic)=r2(u,fit);

    fl=y>S;
    z=y(fl)-S;
    uf=u(fl);
    X=[z.*(H-z),ones(size(z))];
    c=X\uf;

    nuFluid(ic)=ax/(2*c(1));
    r2Fluid(ic)=r2(uf,X*c);

    [uI,uMean]=scalars(H,S,ax,alpha(ic),o.nuReference);
    slipRelErr(ic)=(c(2)-uI)/max(abs(uI),eps);
    meanRelErr(ic)=(mean(uf,'omitnan')-uMean)/max(abs(uMean),eps);
    maxRelErr(ic)=(max(uf,[],'omitnan')-M.targetUc(ic))/M.targetUc(ic);

    fittedEllBOverA(ic)=sqrt(nuFull(ic)/alpha(ic))/a;

    L2ref(ic)=sqrt(mean((u-ref).^2,'omitnan')) / ...
        max(sqrt(mean(u.^2,'omitnan')),eps);
    L2fit(ic)=sqrt(mean((u-fit).^2,'omitnan')) / ...
        max(sqrt(mean(u.^2,'omitnan')),eps);
    Linffit(ic)=max(abs(u-fit),[],'omitnan') / ...
        max(max(abs(u),[],'omitnan'),eps);
end

T=table(caseName,targetEllBOverA,alpha,alphaDt, ...
    nuFull,r2Full,nuFluid,r2Fluid,fittedEllBOverA, ...
    slipRelErr,meanRelErr,maxRelErr,L2ref,L2fit,Linffit);

ad=fullfile(rootDir,'analysis_x8e');
if ~isfolder(ad), mkdir(ad); end
writetable(T,fullfile(ad,'0493x8e_darcy_alpha_sweep_summary.csv'));

fprintf('\n===== 0493x8e Q6-G-F DARCY STIFFNESS SWEEP =====\n');
fprintf('nuReference = %.10g\n',o.nuReference);
disp(T);
fprintf('Reading: ellB/a >= O(1) tests resolved Brinkman; ellB/a<1 documents the under-resolved wall limit.\n');
fprintf('alpha=4000 is the calibrated stiff endpoint (alpha*dt=8), not a resolved penetration layer.\n');
fprintf('status=COMPLETE\n');

out=struct('summary',T);
end

function u=profile(y,S,H,ax,alpha,nu)
k=sqrt(alpha/nu);
x=k*S/2;
if x<30
    cothv=cosh(x)/sinh(x);
else
    cothv=1+2*exp(-2*x);
end

uI=ax/alpha+ax*H/(2*nu*k)*cothv;
u=nan(size(y));
w=y<S;

if x<30
    A=ax*H/(2*nu*k*sinh(x));
    u(w)=ax/alpha+A*cosh(k*(y(w)-S/2));
else
    yy=y(w);
    rr=(exp(-k*yy)+exp(-k*(S-yy)))./(1-exp(-k*S));
    u(w)=ax/alpha+ax*H/(2*nu*k).*rr;
end

z=y(~w)-S;
u(~w)=ax/(2*nu).*z.*(H-z)+uI;
end

function [uI,uM]=scalars(H,S,ax,alpha,nu)
k=sqrt(alpha/nu);
x=k*S/2;
if x<30
    c=cosh(x)/sinh(x);
else
    c=1+2*exp(-2*x);
end
uI=ax/alpha+ax*H/(2*nu*k)*c;
uM=ax*H^2/(12*nu)+uI;
end

function v=mse(a,b)
d=a-b;
d=d(isfinite(d));
if isempty(d)
    v=Inf;
else
    v=mean(d.^2);
end
end

function v=r2(a,b)
m=isfinite(a)&isfinite(b);
a=a(m);
b=b(m);
v=1-sum((a-b).^2)/max(sum((a-mean(a)).^2),eps);
end

function c=readchi(path,Nx,Ny)
f=fopen(path,'rb');
if f<0
    error('x8e:chiOpen','Cannot open chi file: %s',path);
end
q=onCleanup(@()fclose(f)); %#ok<NASGU>
r=fread(f,Nx*Ny,'single=>double');
if numel(r)~=Nx*Ny
    error('x8e:chiSize', ...
        'Bad chi size in %s: got %d floats, expected %d', ...
        path,numel(r),Nx*Ny);
end
c=reshape(r,[Nx,Ny])';
end

function P=loadparams(od)
p=fullfile(od,'params_used.kv');
if ~isfile(p)
    d=dir(fullfile(fileparts(od),'params','*.kv'));
    if numel(d)~=1
        error('x8e:params', ...
            'Cannot resolve unique params file for %s (found %d)',od,numel(d));
    end
    p=fullfile(d(1).folder,d(1).name);
end

P=struct();
L=splitlines(string(fileread(p)));
for i=1:numel(L)
    s=strtrim(extractBefore(L(i)+"#","#"));
    if strlength(s)>0 && contains(s,"=")
        z=split(s,"=",2);
        P.(matlab.lang.makeValidName(strtrim(z(1))))=strtrim(z(2));
    end
end
P.path=char(p);
end

function x=num(P,k)
f=matlab.lang.makeValidName(k);
if ~isfield(P,f)
    error('x8e:paramMissing','Missing parameter %s in %s',k,P.path);
end
x=str2double(P.(f));
if ~isfinite(x)
    error('x8e:paramBad','Invalid numeric parameter %s in %s',k,P.path);
end
end

function x=str(P,k)
f=matlab.lang.makeValidName(k);
if ~isfield(P,f)
    error('x8e:paramMissing','Missing parameter %s in %s',k,P.path);
end
x=char(P.(f));
x=strtrim(x);
if numel(x)>=2
    if (x(1)=='"' && x(end)=='"') || (x(1)=='"' && x(end)=='"')
        x=x(2:end-1);
    end
end
end

function p=resolvepath(raw,repoRoot,secondaryRoot)
raw=char(raw);
raw=strtrim(raw);

% Already accessible exactly as stored.
if isfile(raw) || isfolder(raw)
    p=raw;
    return;
end

% Try relative to the repository root. This is the normal case because
% params_used.kv stores paths such as runs/... while MATLAB is often launched
% from <repo>/matlab.
cand=fullfile(repoRoot,raw);
if isfile(cand) || isfolder(cand)
    p=cand;
    return;
end

% Last useful relative base: directory containing the params file.
cand2=fullfile(secondaryRoot,raw);
if isfile(cand2) || isfolder(cand2)
    p=cand2;
    return;
end

error('x8e:pathResolve', ...
    ['Cannot resolve path:  pwd=%s'], ...
    raw,cand,cand2,pwd);
end
