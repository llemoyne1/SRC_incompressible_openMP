function R = analyze_0493x16j_chi_kinetic_specular_compare(pairRoot)
% 0493x16j chi kinetic specular comparison.
% Compares rigid/deformable rest vs common Galilean boost. This first
% qualification feeds the exact cell-resolved kinetic wall reaction through
% the existing x16b solid-load projection path.

if nargin < 1 || isempty(pairRoot)
    pairRoot = '../runs/0493x16j_chi_kinetic_specular_compare';
end

kinds = {'rigid','deformable'};
R = struct();
for ik = 1:numel(kinds)
    k = kinds{ik};
    A = loadCase(fullfile(pairRoot,k,'rest','fresh'));
    B = loadCase(fullfile(pairRoot,k,'boost','fresh'));
    R.(k) = comparePair(A,B,k);
end

analysisDir = fullfile(pairRoot,'analysis');
if ~exist(analysisDir,'dir'), mkdir(analysisDir); end
summaryPath = fullfile(analysisDir,'summary_0493x16j.txt');
fid = fopen(summaryPath,'w');
assert(fid>=0,'Cannot open %s',summaryPath);
cleanup = onCleanup(@() fclose(fid));

fprintf(fid,'0493x16j chi kinetic specular boundary comparison\n');
fprintf(fid,'status=COMPARE_OK\n');
fprintf(fid,'scope=impermeability_and_Galilean_response_only\n');
fprintf(fid,'wallImpulseFeedback=APPLIED_exact_cell_reaction_x16b\n');
fprintf(fid,'historicalDarcyCompatibility=default_off_path_unchanged_by_construction\n');
fprintf(fid,'filteredRecorderChi=NOT_USED_0432_UNSUPPORTED\n');
for ik = 1:numel(kinds)
    k = kinds{ik}; Q = R.(k);
    fprintf(fid,'\n[%s]\n',k);
    fprintf(fid,'stepsCompared=%d\n',Q.stepsCompared);
    fprintf(fid,'restMeanCollisions=%.17g\n',Q.restMeanCollisions);
    fprintf(fid,'boostMeanCollisions=%.17g\n',Q.boostMeanCollisions);
    fprintf(fid,'collisionRateRelativeDifference=%.17g\n',Q.collisionRateRelativeDifference);
    fprintf(fid,'restImpulseRmsX=%.17g\n',Q.restImpulseRmsX);
    fprintf(fid,'boostImpulseRmsX=%.17g\n',Q.boostImpulseRmsX);
    fprintf(fid,'impulseHistoryRmsDifference=%.17g\n',Q.impulseHistoryRmsDifference);
    fprintf(fid,'impulseHistoryRmsDifferenceOverRms=%.17g\n',Q.impulseHistoryRmsDifferenceOverRms);
    fprintf(fid,'restMeanImpulseX=%.17g\n',Q.restMeanImpulseX);
    fprintf(fid,'boostMeanImpulseX=%.17g\n',Q.boostMeanImpulseX);
    fprintf(fid,'meanImpulseRelativeDifference=%.17g\n',Q.meanImpulseRelativeDifference);
    fprintf(fid,'restMeanFictitiousMass=%.17g\n',Q.restMeanFictitiousMass);
    fprintf(fid,'boostMeanFictitiousMass=%.17g\n',Q.boostMeanFictitiousMass);
    fprintf(fid,'fictitiousMassRelativeDifference=%.17g\n',Q.fictitiousMassRelativeDifference);
    fprintf(fid,'restMaxFictitiousMass=%.17g\n',Q.restMaxFictitiousMass);
    fprintf(fid,'boostMaxFictitiousMass=%.17g\n',Q.boostMaxFictitiousMass);
    fprintf(fid,'maxOrphanNoSegment=%g\n',Q.maxOrphanNoSegment);
    fprintf(fid,'maxSolidVolumeRelativeError=%.17g\n',Q.maxSolidVolumeRelativeError);
    fprintf(fid,'maxHostGeometryUploadBytes=%g\n',Q.maxHostGeometryUploadBytes);
    fprintf(fid,'maxHostLoadDownloadBytes=%g\n',Q.maxHostLoadDownloadBytes);
    fprintf(fid,'restKineticFluidImpulseRmsX=%.17g\n',Q.restKineticFluidImpulseRmsX);
    fprintf(fid,'boostKineticFluidImpulseRmsX=%.17g\n',Q.boostKineticFluidImpulseRmsX);
    fprintf(fid,'maxRelativeCellLoadClosure=%.17g\n',Q.maxRelativeCellLoadClosure);
    fprintf(fid,'maxRelativeActionReaction=%.17g\n',Q.maxRelativeActionReaction);
end

fprintf('0493x16j analysis: %s\n',summaryPath);
disp(fileread(summaryPath));
end

function C = loadCase(root)
kp = fullfile(root,'output','chi_kinetic_boundary_0493x16j.csv');
dp = fullfile(root,'output','chi_solid_dynamics_0493x16a.csv');
assert(isfile(kp),'Missing %s',kp);
assert(isfile(dp),'Missing %s',dp);
K = readtable(kp,'VariableNamingRule','preserve');
D = readtable(dp,'VariableNamingRule','preserve');
requiredK = {'step','collisions','orphanNoSegment','wallImpulseX','wallImpulseY','wallImpulseAbsSum'};
requiredD = {'step','fictitiousFluidMass0493x16c','sampledSolidVolumeRelativeError0493x16e', ...
             'hostGeometryFieldUploadBytes0493x16e','hostLoadFieldDownloadBytes0493x16e', ...
             'chiKineticFluidImpulseX0493x16j','chiKineticFluidImpulseY0493x16j', ...
             'totalFluidImpulseX','totalFluidImpulseY','cellReactionSumX0493x16b','cellReactionSumY0493x16b', ...
             'actionReactionResidualX','actionReactionResidualY'};
for i=1:numel(requiredK), assert(any(strcmp(K.Properties.VariableNames,requiredK{i})),'Missing %s',requiredK{i}); end
for i=1:numel(requiredD), assert(any(strcmp(D.Properties.VariableNames,requiredD{i})),'Missing %s',requiredD{i}); end
[steps,ia,ib] = intersect(round(K.step),round(D.step),'stable');
assert(~isempty(steps),'No common diagnostic steps in %s',root);
C.step = steps;
C.collisions = K.collisions(ia);
C.impulseX = K.wallImpulseX(ia);
C.impulseY = K.wallImpulseY(ia);
C.impulseAbs = K.wallImpulseAbsSum(ia);
C.orphan = K.orphanNoSegment(ia);
C.fictMass = D.fictitiousFluidMass0493x16c(ib);
C.volErr = D.sampledSolidVolumeRelativeError0493x16e(ib);
C.hostUp = D.hostGeometryFieldUploadBytes0493x16e(ib);
C.hostDown = D.hostLoadFieldDownloadBytes0493x16e(ib);
C.kineticFluidX = D.chiKineticFluidImpulseX0493x16j(ib);
C.kineticFluidY = D.chiKineticFluidImpulseY0493x16j(ib);
C.totalFluidX = D.totalFluidImpulseX(ib);
C.totalFluidY = D.totalFluidImpulseY(ib);
C.cellReactionX = D.cellReactionSumX0493x16b(ib);
C.cellReactionY = D.cellReactionSumY0493x16b(ib);
C.actionResidualX = D.actionReactionResidualX(ib);
C.actionResidualY = D.actionReactionResidualY(ib);
end

function Q = comparePair(A,B,label)
[steps,ia,ib] = intersect(A.step,B.step,'stable');
assert(numel(steps)>=10,'Too few paired steps for %s',label);
% Ignore first half to exclude initialization/overlap cleanup.
keep = steps >= steps(1) + 0.5*(steps(end)-steps(1));
ia=ia(keep); ib=ib(keep); steps=steps(keep);
ax=A.impulseX(ia); bx=B.impulseX(ib);
arms=sqrt(mean(ax.^2)); brms=sqrt(mean(bx.^2));
den=max([arms brms 1e-30]);
Q.stepsCompared=numel(steps);
Q.restMeanCollisions=mean(A.collisions(ia));
Q.boostMeanCollisions=mean(B.collisions(ib));
Q.collisionRateRelativeDifference=abs(Q.boostMeanCollisions-Q.restMeanCollisions)/max([Q.restMeanCollisions Q.boostMeanCollisions 1]);
Q.restImpulseRmsX=arms; Q.boostImpulseRmsX=brms;
Q.impulseHistoryRmsDifference=sqrt(mean((bx-ax).^2));
Q.impulseHistoryRmsDifferenceOverRms=Q.impulseHistoryRmsDifference/den;
Q.restMeanImpulseX=mean(ax); Q.boostMeanImpulseX=mean(bx);
Q.meanImpulseRelativeDifference=abs(Q.boostMeanImpulseX-Q.restMeanImpulseX)/max([abs(Q.restMeanImpulseX) abs(Q.boostMeanImpulseX) den 1e-30]);
Q.restMeanFictitiousMass=mean(A.fictMass(ia));
Q.boostMeanFictitiousMass=mean(B.fictMass(ib));
Q.fictitiousMassRelativeDifference=abs(Q.boostMeanFictitiousMass-Q.restMeanFictitiousMass)/max([Q.restMeanFictitiousMass Q.boostMeanFictitiousMass 1]);
Q.restMaxFictitiousMass=max(A.fictMass(ia)); Q.boostMaxFictitiousMass=max(B.fictMass(ib));
Q.maxOrphanNoSegment=max([A.orphan(ia); B.orphan(ib)]);
Q.maxSolidVolumeRelativeError=max([A.volErr(ia); B.volErr(ib)]);
Q.maxHostGeometryUploadBytes=max([A.hostUp(ia); B.hostUp(ib)]);
Q.maxHostLoadDownloadBytes=max([A.hostDown(ia); B.hostDown(ib)]);
Q.maxRelativeCellLoadClosure=max([relativeResidual(A.cellReactionX(ia)+A.totalFluidX(ia), A.cellReactionX(ia), A.totalFluidX(ia)); ...
                                  relativeResidual(B.cellReactionX(ib)+B.totalFluidX(ib), B.cellReactionX(ib), B.totalFluidX(ib)); ...
                                  relativeResidual(A.cellReactionY(ia)+A.totalFluidY(ia), A.cellReactionY(ia), A.totalFluidY(ia)); ...
                                  relativeResidual(B.cellReactionY(ib)+B.totalFluidY(ib), B.cellReactionY(ib), B.totalFluidY(ib))]);
Q.maxRelativeActionReaction=max([relativeResidual(A.actionResidualX(ia), A.cellReactionX(ia), A.totalFluidX(ia)); ...
                                 relativeResidual(B.actionResidualX(ib), B.cellReactionX(ib), B.totalFluidX(ib)); ...
                                 relativeResidual(A.actionResidualY(ia), A.cellReactionY(ia), A.totalFluidY(ia)); ...
                                 relativeResidual(B.actionResidualY(ib), B.cellReactionY(ib), B.totalFluidY(ib))]);
Q.restKineticFluidImpulseRmsX=sqrt(mean(A.kineticFluidX(ia).^2));
Q.boostKineticFluidImpulseRmsX=sqrt(mean(B.kineticFluidX(ib).^2));
end

function r = relativeResidual(residual,a,b)
scale = max([ones(size(residual(:))) abs(a(:)) abs(b(:))],[],2);
r = max(abs(residual(:))./scale);
end
