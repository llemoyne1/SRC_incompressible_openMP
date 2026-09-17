function results = analyze_0493x19b_fix1_torque_split(runRoot, startStep)
%ANALYZE_0493X19B_FIX1_TORQUE_SPLIT
% Short restart diagnostic for the x19b prescribed rotating annulus.
% Separates the wall-reaction torque into local facet-normal and local
% tangential components. No profile reconstruction is needed for this test.
%
% Default input:
%   ../runs/0493x19b_fix1_torque_split/bounceback/fresh
%
% The diagnostic run restarts an already established Couette state, so the
% first few hundred additional steps are discarded by default.

if nargin < 1 || isempty(runRoot)
    here = fileparts(mfilename('fullpath'));
    runRoot = fullfile(here,'..','runs','0493x19b_fix1_torque_split','bounceback','fresh');
end
if nargin < 2 || isempty(startStep), startStep = 200; end

paramsPath = fullfile(runRoot,'params','0493x19b_fix1_bounceback_torque_split.kv');
if ~isfile(paramsPath)
    dd = dir(fullfile(runRoot,'params','*.kv'));
    if isempty(dd), error('0493x19bFix1:noParams','No params .kv in %s',runRoot); end
    paramsPath = fullfile(dd(1).folder,dd(1).name);
end
P = local_read_kv(paramsPath);
dt = str2double(P.dt);
if ~(isfinite(dt) && dt > 0), error('0493x19bFix1:badDt','Invalid dt in %s',paramsPath); end

csvPath = fullfile(runRoot,'output','chi_kinetic_boundary_0493x16j.csv');
if ~isfile(csvPath), error('0493x19bFix1:noCSV','Missing %s',csvPath); end
K = readtable(csvPath,'VariableNamingRule','preserve');
need = {'step','x19bInnerTorqueImpulse','x19bOuterTorqueImpulse', ...
    'x19bInnerTorqueNormalImpulse','x19bInnerTorqueTangentialImpulse', ...
    'x19bOuterTorqueNormalImpulse','x19bOuterTorqueTangentialImpulse'};
if ~all(ismember(need,K.Properties.VariableNames))
    missing = need(~ismember(need,K.Properties.VariableNames));
    error('0493x19bFix1:missingColumns','Missing columns: %s',strjoin(missing,', '));
end

mask = K.step >= startStep;
if nnz(mask) < 20
    error('0493x19bFix1:shortWindow','Need >=20 diagnostic rows at step >= %d; found %d',startStep,nnz(mask));
end
K = K(mask,:);

% Impulse per solver step -> mean torque by division by dt.
Ti  = K.x19bInnerTorqueImpulse / dt;
To  = K.x19bOuterTorqueImpulse / dt;
Tin = K.x19bInnerTorqueNormalImpulse / dt;
Tit = K.x19bInnerTorqueTangentialImpulse / dt;
Ton = K.x19bOuterTorqueNormalImpulse / dt;
Tot = K.x19bOuterTorqueTangentialImpulse / dt;

mTi=mean(Ti,'omitnan');   mTo=mean(To,'omitnan');
mTin=mean(Tin,'omitnan'); mTit=mean(Tit,'omitnan');
mTon=mean(Ton,'omitnan'); mTot=mean(Tot,'omitnan');

reconInner = local_rel_rms(Ti, Tin+Tit);
reconOuter = local_rel_rms(To, Ton+Tot);
closureTotal = abs(mTi+mTo)/max([abs(mTi),abs(mTo),eps]);
closureTangential = abs(mTit+mTot)/max([abs(mTit),abs(mTot),eps]);
normalToTangInner = abs(mTin)/max(abs(mTit),eps);
normalToTangOuter = abs(mTon)/max(abs(mTot),eps);

% Block means are used only as a noise/convergence diagnostic, not as an
% independence proof. Six blocks gives useful drift information at low cost.
nBlocks = min(6,max(2,floor(height(K)/20)));
[biTi,biTo,biTin,biTit,biTon,biTot] = local_blocks(Ti,To,Tin,Tit,Ton,Tot,nBlocks);
semTit = std(biTit,0,'omitnan')/sqrt(numel(biTit));
semTot = std(biTot,0,'omitnan')/sqrt(numel(biTot));
firstHalf = K.step <= median(K.step);
lastHalf = ~firstHalf;
firstClosureT = local_closure(mean(Tit(firstHalf),'omitnan'),mean(Tot(firstHalf),'omitnan'));
lastClosureT  = local_closure(mean(Tit(lastHalf),'omitnan'), mean(Tot(lastHalf),'omitnan'));

results = struct();
results.runRoot=runRoot; results.startStep=startStep;
results.stepMin=min(K.step); results.stepMax=max(K.step); results.samples=height(K);
results.innerTotal=mTi; results.outerTotal=mTo;
results.innerNormal=mTin; results.innerTangential=mTit;
results.outerNormal=mTon; results.outerTangential=mTot;
results.totalClosure=closureTotal; results.tangentialClosure=closureTangential;
results.normalToTangentialInner=normalToTangInner;
results.normalToTangentialOuter=normalToTangOuter;
results.reconstructionRelativeRmsInner=reconInner;
results.reconstructionRelativeRmsOuter=reconOuter;
results.innerTangentialBlockSem=semTit;
results.outerTangentialBlockSem=semTot;
results.tangentialClosureFirstHalf=firstClosureT;
results.tangentialClosureLastHalf=lastClosureT;
results.blockInnerTangential=biTit;
results.blockOuterTangential=biTot;

fprintf('\n[0493x19b-fix1] window additional steps %d..%d ; diagnostic rows=%d\n', ...
    results.stepMin,results.stepMax,results.samples);
fprintf('[0493x19b-fix1] TOTAL      inner=% .9g outer=% .9g closure=%.6g\n',mTi,mTo,closureTotal);
fprintf('[0493x19b-fix1] NORMAL     inner=% .9g outer=% .9g\n',mTin,mTon);
fprintf('[0493x19b-fix1] TANGENTIAL inner=% .9g outer=% .9g closure=%.6g\n',mTit,mTot,closureTangential);
fprintf('[0493x19b-fix1] |normal/tangential| inner=%.6g outer=%.6g\n',normalToTangInner,normalToTangOuter);
fprintf('[0493x19b-fix1] total-(normal+tangent) relRMS inner=%.3g outer=%.3g\n',reconInner,reconOuter);
fprintf('[0493x19b-fix1] tangential block SEM inner=%.6g outer=%.6g\n',semTit,semTot);
fprintf('[0493x19b-fix1] tangential closure firstHalf=%.6g lastHalf=%.6g\n',firstClosureT,lastClosureT);

fig=figure('Color','w','Name','0493x19b-fix1 torque split');
plot(K.step,Tin,'-','DisplayName','inner normal'); hold on;
plot(K.step,Tit,'-','DisplayName','inner tangential');
plot(K.step,Ton,'-','DisplayName','outer normal');
plot(K.step,Tot,'-','DisplayName','outer tangential');
xlabel('additional restart step'); ylabel('wall-reaction torque'); grid on;
legend('Location','best'); title('0493x19b-fix1 torque decomposition');
try
    exportgraphics(fig,fullfile(runRoot,'output','torque_split_0493x19b_fix1.png'),'Resolution',160);
catch
end

Tout=table(mTi,mTo,mTin,mTit,mTon,mTot,closureTotal,closureTangential, ...
    normalToTangInner,normalToTangOuter,reconInner,reconOuter,semTit,semTot, ...
    firstClosureT,lastClosureT, ...
    'VariableNames',{'innerTotal','outerTotal','innerNormal','innerTangential', ...
    'outerNormal','outerTangential','totalClosure','tangentialClosure', ...
    'normalToTangentialInner','normalToTangentialOuter', ...
    'reconstructionRelativeRmsInner','reconstructionRelativeRmsOuter', ...
    'innerTangentialBlockSem','outerTangentialBlockSem', ...
    'tangentialClosureFirstHalf','tangentialClosureLastHalf'});
writetable(Tout,fullfile(runRoot,'output','summary_0493x19b_fix1_torque_split.csv'));
end

function r=local_rel_rms(a,b)
d=a-b; r=sqrt(mean(d.^2,'omitnan'))/max(sqrt(mean(a.^2,'omitnan')),eps);
end

function c=local_closure(a,b)
c=abs(a+b)/max([abs(a),abs(b),eps]);
end

function [a,b,c,d,e,f]=local_blocks(A,B,C,D,E,F,nBlocks)
n=numel(A); edges=round(linspace(1,n+1,nBlocks+1));
a=nan(nBlocks,1); b=a; c=a; d=a; e=a; f=a;
for k=1:nBlocks
    ii=edges(k):edges(k+1)-1;
    a(k)=mean(A(ii),'omitnan'); b(k)=mean(B(ii),'omitnan');
    c(k)=mean(C(ii),'omitnan'); d(k)=mean(D(ii),'omitnan');
    e(k)=mean(E(ii),'omitnan'); f(k)=mean(F(ii),'omitnan');
end
end

function kv=local_read_kv(path)
fid=fopen(path,'r'); if fid<0, error('Cannot open %s',path); end
cc=onCleanup(@() fclose(fid)); kv=struct();
while true
    line=fgetl(fid); if ~ischar(line), break; end
    q=strfind(line,'='); if isempty(q), continue; end
    key=matlab.lang.makeValidName(strtrim(line(1:q(1)-1)));
    kv.(key)=strtrim(line(q(1)+1:end));
end
end
