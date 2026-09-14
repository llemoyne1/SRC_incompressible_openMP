function R = analyze_0493x16k_mobile_solid_qualification(pairRoot)
% 0493x16k — full statistical qualification after the short geometry smoke.
% Uses the same x16j four-case output layout. Pointwise impulse histories are
% deliberately NOT used as a Galilean criterion because the randomly shifted
% MPCD collision grid need not produce trajectorywise-identical realizations.

if nargin < 1 || isempty(pairRoot)
    pairRoot = '../runs/0493x16j_chi_kinetic_specular_compare';
end
kinds = {'rigid','deformable'};
R = struct(); allPass = true;
for ik=1:numel(kinds)
    k=kinds{ik};
    A=loadCase(fullfile(pairRoot,k,'rest','fresh'));
    B=loadCase(fullfile(pairRoot,k,'boost','fresh'));
    Q=compareStatistical(A,B,k);
    R.(k)=Q; allPass=allPass && Q.pass;
end
analysisDir=fullfile(pairRoot,'analysis');
if ~exist(analysisDir,'dir'), mkdir(analysisDir); end
summaryPath=fullfile(analysisDir,'summary_0493x16k.txt');
fid=fopen(summaryPath,'w'); assert(fid>=0,'Cannot open %s',summaryPath);
cleanup=onCleanup(@() fclose(fid));
fprintf(fid,'0493x16k mobile-solid Galilean qualification\n');
fprintf(fid,'status=%s\n', ternary(allPass,'PASS','REVIEW'));
fprintf(fid,'criteria=statistical_not_trajectorywise\n');
fprintf(fid,'impulseRmsRelGate=0.15\n');
fprintf(fid,'collisionRateRelGate=0.02\n');
fprintf(fid,'fictitiousMassRelGate=0.15\n');
fprintf(fid,'actionReactionGate=1e-10\n');
for ik=1:numel(kinds)
    k=kinds{ik}; Q=R.(k);
    fprintf(fid,'\n[%s]\n',k);
    fprintf(fid,'stepsCompared=%d\n',Q.stepsCompared);
    fprintf(fid,'collisionRateRelativeDifference=%.17g\n',Q.collisionRateRelativeDifference);
    fprintf(fid,'impulseRmsRelativeDifference=%.17g\n',Q.impulseRmsRelativeDifference);
    fprintf(fid,'fictitiousMassRelativeDifference=%.17g\n',Q.fictitiousMassRelativeDifference);
    fprintf(fid,'maxOrphanNoSegment=%g\n',Q.maxOrphanNoSegment);
    fprintf(fid,'maxRelativeCellLoadClosure=%.17g\n',Q.maxRelativeCellLoadClosure);
    fprintf(fid,'maxRelativeActionReaction=%.17g\n',Q.maxRelativeActionReaction);
    fprintf(fid,'qualification=%s\n',ternary(Q.pass,'PASS','REVIEW'));
end
fprintf('0493x16k analysis: %s\n',summaryPath);
disp(fileread(summaryPath));
end

function C=loadCase(root)
K=readtable(fullfile(root,'output','chi_kinetic_boundary_0493x16j.csv'),'VariableNamingRule','preserve');
D=readtable(fullfile(root,'output','chi_solid_dynamics_0493x16a.csv'),'VariableNamingRule','preserve');
[steps,ia,ib]=intersect(round(K.step),round(D.step),'stable'); assert(~isempty(steps),'No common steps in %s',root);
C.step=steps; C.collisions=K.collisions(ia); C.impulseX=K.wallImpulseX(ia); C.orphan=K.orphanNoSegment(ia);
C.fictMass=D.fictitiousFluidMass0493x16c(ib); C.totalX=D.totalFluidImpulseX(ib); C.totalY=D.totalFluidImpulseY(ib);
C.reactX=D.cellReactionSumX0493x16b(ib); C.reactY=D.cellReactionSumY0493x16b(ib);
C.arX=D.actionReactionResidualX(ib); C.arY=D.actionReactionResidualY(ib);
end

function Q=compareStatistical(A,B,label)
[steps,ia,ib]=intersect(A.step,B.step,'stable'); assert(numel(steps)>=20,'Too few paired steps for %s',label);
keep=steps>=steps(1)+0.5*(steps(end)-steps(1)); ia=ia(keep); ib=ib(keep); steps=steps(keep);
ra=sqrt(mean(A.impulseX(ia).^2)); rb=sqrt(mean(B.impulseX(ib).^2));
Q.stepsCompared=numel(steps);
Q.collisionRateRelativeDifference=reldiff(mean(A.collisions(ia)),mean(B.collisions(ib)),1);
Q.impulseRmsRelativeDifference=reldiff(ra,rb,1e-30);
Q.fictitiousMassRelativeDifference=reldiff(mean(A.fictMass(ia)),mean(B.fictMass(ib)),1);
Q.maxOrphanNoSegment=max([A.orphan(ia);B.orphan(ib)]);
Q.maxRelativeCellLoadClosure=max([rr(A.reactX(ia)+A.totalX(ia),A.reactX(ia),A.totalX(ia)); rr(B.reactX(ib)+B.totalX(ib),B.reactX(ib),B.totalX(ib)); rr(A.reactY(ia)+A.totalY(ia),A.reactY(ia),A.totalY(ia)); rr(B.reactY(ib)+B.totalY(ib),B.reactY(ib),B.totalY(ib))]);
Q.maxRelativeActionReaction=max([rr(A.arX(ia),A.reactX(ia),A.totalX(ia));rr(B.arX(ib),B.reactX(ib),B.totalX(ib));rr(A.arY(ia),A.reactY(ia),A.totalY(ia));rr(B.arY(ib),B.reactY(ib),B.totalY(ib))]);
Q.pass=Q.collisionRateRelativeDifference<=0.02 && Q.impulseRmsRelativeDifference<=0.15 && Q.fictitiousMassRelativeDifference<=0.15 && Q.maxRelativeCellLoadClosure<=1e-12 && Q.maxRelativeActionReaction<=1e-10 && Q.maxOrphanNoSegment<=2;
end
function y=reldiff(a,b,floorv), y=abs(a-b)/max([abs(a) abs(b) floorv]); end
function y=rr(r,a,b), scale=max([ones(numel(r),1) abs(a(:)) abs(b(:))],[],2); y=max(abs(r(:))./scale); end
function s=ternary(c,a,b), if c, s=a; else, s=b; end, end
