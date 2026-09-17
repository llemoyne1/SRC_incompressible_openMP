function results = analyze_0493x19b_fix2_angular_balance(runRoot, startStep)
%ANALYZE_0493X19B_FIX2_ANGULAR_BALANCE
% Short restart diagnostic for the x19b prescribed rotating annulus.
%
% x19b-fix2 changes no physics.  It samples the Lagrangian-wall reaction on
% every solver step and measures the exact change of REAL-FLUID angular
% momentum caused by the bulk SRC rotation kernel itself:
%
%   deltaLSrc = L_after_SRC - L_before_SRC .
%
% Wall columns are reactions ON THE SOLID.  Therefore the fluid receives the
% opposite angular impulse.  If wall exchange and non-angular-momentum-
% conserving SRC were the only angular-momentum sources, a stationary mean
% would satisfy
%
%   - <T_wall,reaction> + <deltaLSrc/dt> = 0 .
%
% Q6 and the thermostat occur after SRC and are NOT instrumented by this
% patch.  Consequently a nonzero residual is an explicitly unresolved
% downstream-operator contribution, not automatically an SRC error.

if nargin < 1 || isempty(runRoot)
    here = fileparts(mfilename('fullpath'));
    runRoot = fullfile(here,'..','runs','0493x19b_fix2_angular_balance','bounceback','fresh');
end
if nargin < 2 || isempty(startStep), startStep = 100; end

paramsPath = local_first_file(fullfile(runRoot,'params','*.kv'));
P = local_read_kv(paramsPath);
dt = str2double(P.dt);
if ~(isfinite(dt) && dt > 0), error('0493x19bFix2:badDt','Invalid dt in %s',paramsPath); end

wallPath = fullfile(runRoot,'output','chi_kinetic_boundary_0493x16j.csv');
srcPath  = fullfile(runRoot,'output','src_angular_momentum_0493x19b_fix2.csv');
if ~isfile(wallPath), error('0493x19bFix2:noWallCSV','Missing %s',wallPath); end
if ~isfile(srcPath),  error('0493x19bFix2:noSrcCSV','Missing %s',srcPath); end

K = readtable(wallPath,'VariableNamingRule','preserve');
S = readtable(srcPath,'VariableNamingRule','preserve');
needK = {'step','x19bInnerTorqueImpulse','x19bOuterTorqueImpulse', ...
    'x19bInnerTorqueNormalImpulse','x19bInnerTorqueTangentialImpulse', ...
    'x19bOuterTorqueNormalImpulse','x19bOuterTorqueTangentialImpulse'};
needS = {'step','LbeforeSrc','LafterSrc','deltaLSrc'};
local_require_columns(K,needK,'wall');
local_require_columns(S,needS,'SRC');

[step,ik,is] = intersect(double(K.step),double(S.step),'stable');
keep = step >= startStep;
step=step(keep); ik=ik(keep); is=is(keep);
if numel(step) < 100
    error('0493x19bFix2:shortWindow','Need >=100 matched every-step rows at step >= %d; found %d',startStep,numel(step));
end
K=K(ik,:); S=S(is,:);

% Reaction torques ON THE SOLID (wall impulses / dt).
Ti  = double(K.x19bInnerTorqueImpulse)/dt;
To  = double(K.x19bOuterTorqueImpulse)/dt;
Tin = double(K.x19bInnerTorqueNormalImpulse)/dt;
Tit = double(K.x19bInnerTorqueTangentialImpulse)/dt;
Ton = double(K.x19bOuterTorqueNormalImpulse)/dt;
Tot = double(K.x19bOuterTorqueTangentialImpulse)/dt;

wallReactionTotal = Ti + To;
wallReactionTangential = Tit + Tot;
fluidWallTotal = -wallReactionTotal;
fluidWallTangential = -wallReactionTangential;
srcTorque = double(S.deltaLSrc)/dt;

% Two-channel residuals.  The TOTAL form is the exact one for the measured
% wall exchange; the tangential form is useful for interpreting cylindrical
% Couette but deliberately omits the faceting-normal contribution.
residualTotal = fluidWallTotal + srcTorque;
residualTangential = fluidWallTangential + srcTorque;

mTi=mean(Ti,'omitnan'); mTo=mean(To,'omitnan');
mTin=mean(Tin,'omitnan'); mTit=mean(Tit,'omitnan');
mTon=mean(Ton,'omitnan'); mTot=mean(Tot,'omitnan');
mWallR=mean(wallReactionTotal,'omitnan');
mWallRT=mean(wallReactionTangential,'omitnan');
mFluidWall=mean(fluidWallTotal,'omitnan');
mSrc=mean(srcTorque,'omitnan');
mResidual=mean(residualTotal,'omitnan');
mResidualT=mean(residualTangential,'omitnan');

closureWallSrc = abs(mResidual)/max([abs(mFluidWall),abs(mSrc),eps]);
closureWallSrcTangential = abs(mResidualT)/max([abs(mean(fluidWallTangential,'omitnan')),abs(mSrc),eps]);
wallReactionVsSrc = abs(mWallR-mSrc)/max([abs(mWallR),abs(mSrc),eps]);
normalToTangInner = abs(mTin)/max(abs(mTit),eps);
normalToTangOuter = abs(mTon)/max(abs(mTot),eps);
reconInner = local_rel_rms(Ti,Tin+Tit);
reconOuter = local_rel_rms(To,Ton+Tot);

nBlocks=min(10,max(4,floor(numel(step)/100)));
[bWall,bSrc,bRes,bInnerT,bOuterT]=local_blocks(wallReactionTotal,srcTorque,residualTotal,Tit,Tot,nBlocks);
semWall=std(bWall,0,'omitnan')/sqrt(numel(bWall));
semSrc=std(bSrc,0,'omitnan')/sqrt(numel(bSrc));
semRes=std(bRes,0,'omitnan')/sqrt(numel(bRes));

half = step <= median(step);
closureFirst = local_balance_closure(fluidWallTotal(half),srcTorque(half));
closureLast  = local_balance_closure(fluidWallTotal(~half),srcTorque(~half));

results=struct();
results.runRoot=runRoot; results.startStep=startStep;
results.stepMin=min(step); results.stepMax=max(step); results.samples=numel(step);
results.innerTotal=mTi; results.outerTotal=mTo;
results.innerNormal=mTin; results.innerTangential=mTit;
results.outerNormal=mTon; results.outerTangential=mTot;
results.wallReactionTotal=mWallR;
results.wallReactionTangential=mWallRT;
results.fluidWallTorque=mFluidWall;
results.srcAngularMomentumTorque=mSrc;
results.wallPlusSrcResidual=mResidual;
results.wallSrcNormalizedResidual=closureWallSrc;
results.tangentialWallSrcNormalizedResidual=closureWallSrcTangential;
results.wallReactionVsSrcRelativeDifference=wallReactionVsSrc;
results.normalToTangentialInner=normalToTangInner;
results.normalToTangentialOuter=normalToTangOuter;
results.reconstructionRelativeRmsInner=reconInner;
results.reconstructionRelativeRmsOuter=reconOuter;
results.wallReactionBlockSem=semWall;
results.srcTorqueBlockSem=semSrc;
results.residualBlockSem=semRes;
results.balanceClosureFirstHalf=closureFirst;
results.balanceClosureLastHalf=closureLast;
results.blockWallReaction=bWall;
results.blockSrcTorque=bSrc;
results.blockResidual=bRes;
results.blockInnerTangential=bInnerT;
results.blockOuterTangential=bOuterT;

fprintf('\n[0493x19b-fix2] matched every-step window %d..%d ; rows=%d\n', ...
    results.stepMin,results.stepMax,results.samples);
fprintf('[0493x19b-fix2] WALL reaction total      = % .9g\n',mWallR);
fprintf('[0493x19b-fix2] WALL reaction tangential = % .9g (inner=% .9g outer=% .9g)\n',mWallRT,mTit,mTot);
fprintf('[0493x19b-fix2] WALL normal              = % .9g (inner=% .9g outer=% .9g)\n',mTin+mTon,mTin,mTon);
fprintf('[0493x19b-fix2] SRC delta-L / dt         = % .9g\n',mSrc);
fprintf('[0493x19b-fix2] fluid-wall + SRC residual = % .9g ; normalized=%.6g\n',mResidual,closureWallSrc);
fprintf('[0493x19b-fix2] tangential-only residual  = % .9g ; normalized=%.6g\n',mResidualT,closureWallSrcTangential);
fprintf('[0493x19b-fix2] wallReaction-vs-SRC relative difference = %.6g\n',wallReactionVsSrc);
fprintf('[0493x19b-fix2] block SEM wallReaction=%.6g SRC=%.6g residual=%.6g\n',semWall,semSrc,semRes);
fprintf('[0493x19b-fix2] balance closure firstHalf=%.6g lastHalf=%.6g\n',closureFirst,closureLast);
fprintf('[0493x19b-fix2] NOTE: residual is not a full-step closure; Q6/thermostat are downstream and uninstrumented.\n');

smoothN=min(51,max(5,2*floor(numel(step)/100)+1));
fig=figure('Color','w','Name','0493x19b-fix2 angular balance');
tiledlayout(2,1,'Padding','compact','TileSpacing','compact');
nexttile;
plot(step,movmean(wallReactionTotal,smoothN),'DisplayName','wall reaction total'); hold on;
plot(step,movmean(srcTorque,smoothN),'DisplayName','SRC \DeltaL/dt');
yline(0,'k:'); grid on; legend('Location','best');
ylabel('torque'); title(sprintf('x19b-fix2 wall/SRC balance, movmean %d steps',smoothN));
nexttile;
plot(step,movmean(Tit,smoothN),'DisplayName','inner tangential reaction'); hold on;
plot(step,movmean(Tot,smoothN),'DisplayName','outer tangential reaction');
plot(step,movmean(residualTotal,smoothN),'DisplayName','fluid-wall + SRC residual');
yline(0,'k:'); grid on; legend('Location','best');
xlabel('additional restart step'); ylabel('torque');
try
    exportgraphics(fig,fullfile(runRoot,'output','angular_balance_0493x19b_fix2.png'),'Resolution',160);
catch
end

Tout=table(mTi,mTo,mTin,mTit,mTon,mTot,mWallR,mWallRT,mFluidWall,mSrc,mResidual, ...
    closureWallSrc,closureWallSrcTangential,wallReactionVsSrc, ...
    normalToTangInner,normalToTangOuter,reconInner,reconOuter, ...
    semWall,semSrc,semRes,closureFirst,closureLast, ...
    'VariableNames',{'innerTotal','outerTotal','innerNormal','innerTangential', ...
    'outerNormal','outerTangential','wallReactionTotal','wallReactionTangential', ...
    'fluidWallTorque','srcAngularMomentumTorque','wallPlusSrcResidual', ...
    'wallSrcNormalizedResidual','tangentialWallSrcNormalizedResidual', ...
    'wallReactionVsSrcRelativeDifference','normalToTangentialInner', ...
    'normalToTangentialOuter','reconstructionRelativeRmsInner', ...
    'reconstructionRelativeRmsOuter','wallReactionBlockSem','srcTorqueBlockSem', ...
    'residualBlockSem','balanceClosureFirstHalf','balanceClosureLastHalf'});
writetable(Tout,fullfile(runRoot,'output','summary_0493x19b_fix2_angular_balance.csv'));
end

function path=local_first_file(pattern)
d=dir(pattern); if isempty(d), error('0493x19bFix2:noFile','No file matching %s',pattern); end
path=fullfile(d(1).folder,d(1).name);
end

function local_require_columns(T,names,kind)
missing=names(~ismember(names,T.Properties.VariableNames));
if ~isempty(missing), error('0493x19bFix2:missingColumns','Missing %s columns: %s',kind,strjoin(missing,', ')); end
end

function r=local_rel_rms(a,b)
d=a-b; r=sqrt(mean(d.^2,'omitnan'))/max(sqrt(mean(a.^2,'omitnan')),eps);
end

function c=local_balance_closure(fluidWall,src)
a=mean(fluidWall,'omitnan'); b=mean(src,'omitnan');
c=abs(a+b)/max([abs(a),abs(b),eps]);
end

function [a,b,c,d,e]=local_blocks(A,B,C,D,E,nBlocks)
n=numel(A); edges=round(linspace(1,n+1,nBlocks+1));
a=nan(nBlocks,1); b=a; c=a; d=a; e=a;
for k=1:nBlocks
    ii=edges(k):edges(k+1)-1;
    a(k)=mean(A(ii),'omitnan'); b(k)=mean(B(ii),'omitnan');
    c(k)=mean(C(ii),'omitnan'); d(k)=mean(D(ii),'omitnan'); e(k)=mean(E(ii),'omitnan');
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
