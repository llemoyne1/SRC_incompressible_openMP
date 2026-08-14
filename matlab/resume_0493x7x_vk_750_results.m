%RESUME_0493X7X_VK_750_RESULTS
% Resume-only aggregation after x7u/x7v have already completed.
% No x7u rerun, no x7v rerun, no solver run.
% Run from repository matlab/.

clearvars;

x7uSummary = '../runs/vk_vorticity_transport_0493x7x_750_div0_ablation/vk_vorticity_summary_0493x7u.csv';

x7vProd = '../runs/vk_symmetry_breaking_0493x7x_750_production/vk_symmetry_breaking_summary_0493x7v.csv';
x7vOn   = '../runs/vk_symmetry_breaking_0493x7x_750_div0_b1on/vk_symmetry_breaking_summary_0493x7v.csv';
x7vOff  = '../runs/vk_symmetry_breaking_0493x7x_750_div0_b1off/vk_symmetry_breaking_summary_0493x7v.csv';

assert(isfile(x7uSummary),'Missing x7u summary: %s',x7uSummary);
assert(isfile(x7vProd),'Missing production x7v summary: %s',x7vProd);
assert(isfile(x7vOn),'Missing div0 B1-on x7v summary: %s',x7vOn);
assert(isfile(x7vOff),'Missing div0 B1-off x7v summary: %s',x7vOff);

%% x7v: read already-computed results
P   = readtable(x7vProd,'VariableNamingRule','preserve');
Von = readtable(x7vOn,'VariableNamingRule','preserve');
Voff= readtable(x7vOff,'VariableNamingRule','preserve');

P.mode=string(P.mode);       P.axis=string(P.axis);
Von.mode=string(Von.mode);   Von.axis=string(Von.axis);
Voff.mode=string(Voff.mode); Voff.axis=string(Voff.axis);

src  = local_one(P,   "src","cylinder");
prod = local_one(P,   "src-q6-g-f","cylinder");
gfOn = local_one(Von, "src-q6-g-f","cylinder");
gfOff= local_one(Voff,"src-q6-g-f","cylinder");

labels=["SRC";"Q6GF production densityON B1on";"Q6GF div0 B1on";"Q6GF div0 B1off"];
rows={src;prod;gfOn;gfOff};

D=local_decision(labels,rows);

fprintf('\n===== 0493x7x VK 750x200 X7V DECISION TABLE =====\n');
disp(D);

decisionCsv='../runs/vk_symmetry_breaking_0493x7x_750_div0_decision.csv';
writetable(D,decisionCsv);

fprintf('\n===== 0493x7x VK 750x200 CAUSAL DELTAS =====\n');
fprintf('production densityON B1on sigmaD = %s\n',local_num(prod.sigmaD_common_primary));
fprintf('div0 B1on                 sigmaD = %s\n',local_num(gfOn.sigmaD_common_primary));
fprintf('div0 B1off                sigmaD = %s\n',local_num(gfOff.sigmaD_common_primary));
fprintf('density effect: div0-on - production = %s\n', ...
    local_num(gfOn.sigmaD_common_primary-prod.sigmaD_common_primary));
fprintf('B1 effect at div0: off - on          = %s\n', ...
    local_num(gfOff.sigmaD_common_primary-gfOn.sigmaD_common_primary));
fprintf('SRC                                  = %s\n',local_num(src.sigmaD_common_primary));

%% x7u: use runDir, never caseLabel, to identify physical runs
S=readtable(x7uSummary,'VariableNamingRule','preserve');
S.mode=string(S.mode);
S.runDir=string(S.runDir);

rp=replace(S.runDir,"\","/");

srcMask = S.mode=="src" & ...
    contains(rp,'0434_vk_darcy_chi_periodic_750x200_g6_u0.9_kBT5.0');

prodMask = S.mode=="src-q6-g-f" & ...
    contains(rp,'0434_vk_darcy_chi_periodic_750x200_g6_u0.9_kBT5.0');

onMask = S.mode=="src-q6-g-f" & ...
    contains(rp,'0493x7x_vk_cal750_div0_b1on');

offMask = S.mode=="src-q6-g-f" & ...
    contains(rp,'0493x7x_vk_cal750_div0_b1off');

fprintf('\n[0493x7x-resume] x7u row selection:\n');
fprintf('  SRC             : %d\n',nnz(srcMask));
fprintf('  production Q6GF : %d\n',nnz(prodMask));
fprintf('  div0 B1-on      : %d\n',nnz(onMask));
fprintf('  div0 B1-off     : %d\n',nnz(offMask));

if nnz(srcMask)~=1 || nnz(prodMask)~=1 || nnz(onMask)~=1 || nnz(offMask)~=1
    fprintf('\n[0493x7x-resume] available x7u summary identities:\n');
    disp(S(:,intersect({'caseLabel','parentRun','runDir','mode'},S.Properties.VariableNames,'stable')));
    error('0493x7x:selection', ...
        'Expected exactly one x7u row per physical case; see identities printed above.');
end

sSrc=S(srcMask,:);
sProd=S(prodMask,:);
sOn=S(onMask,:);
sOff=S(offMask,:);

X=table( ...
    labels, ...
    [sSrc.UinfMeanFirstPass;sProd.UinfMeanFirstPass;sOn.UinfMeanFirstPass;sOff.UinfMeanFirstPass], ...
    [sSrc.omegaGeneratorStarMeanFirstPass;sProd.omegaGeneratorStarMeanFirstPass;sOn.omegaGeneratorStarMeanFirstPass;sOff.omegaGeneratorStarMeanFirstPass], ...
    [sSrc.omegaNearStarMeanFirstPass;sProd.omegaNearStarMeanFirstPass;sOn.omegaNearStarMeanFirstPass;sOff.omegaNearStarMeanFirstPass], ...
    [sSrc.vorticitySurvivalGeneratorToNear;sProd.vorticitySurvivalGeneratorToNear;sOn.vorticitySurvivalGeneratorToNear;sOff.vorticitySurvivalGeneratorToNear], ...
    [sSrc.spectralPeakFraction;sProd.spectralPeakFraction;sOn.spectralPeakFraction;sOff.spectralPeakFraction], ...
    [sSrc.probe2D4DCorrelation;sProd.probe2D4DCorrelation;sOn.probe2D4DCorrelation;sOff.probe2D4DCorrelation], ...
    'VariableNames',{'caseName','UinfMeanFirstPass','omegaGeneratorStar','omegaNearStar', ...
    'generatorToNearSurvival','spectralPeakFraction','probe2D4DCorrelation'});

fprintf('\n===== 0493x7x VK 750x200 X7U TRANSPORT TABLE =====\n');
disp(X);

transportCsv='../runs/vk_vorticity_transport_0493x7x_750_div0_ablation/vk_750_div0_transport_decision_0493x7x.csv';
writetable(X,transportCsv);

fprintf('\n===== 0493x7x 750 RESUME OUTPUTS =====\n');
fprintf('decision=%s\n',decisionCsv);
fprintf('transport=%s\n',transportCsv);
fprintf('status=COMPLETE\n');

function r=local_one(T,mode,axisName)
m=T.mode==string(mode) & T.axis==string(axisName);
assert(nnz(m)==1,'Expected one %s/%s row; got %d.',mode,axisName,nnz(m));
r=T(m,:);
end

function D=local_decision(labels,rows)
n=numel(rows);
sigma=nan(n,1);r2=nan(n,1);sigmaSelf=nan(n,1);r2Self=nan(n,1);
cap=nan(n,1);capSelf=nan(n,1);A48=nan(n,1);A812=nan(n,1);A1215=nan(n,1);
status=strings(n,1);
for i=1:n
    r=rows{i};
    sigma(i)=r.sigmaD_common_primary;
    r2(i)=r.r2D_common_primary;
    sigmaSelf(i)=r.sigmaD_self_primary;
    r2Self(i)=r.r2D_self_primary;
    cap(i)=r.commonPodCapture;
    capSelf(i)=r.selfPodCapture;
    A48(i)=r.AcommonRmsTau4to8;
    A812(i)=r.AcommonRmsTau8to12;
    A1215(i)=r.AcommonRmsTau12to15;
    status(i)=string(r.fitStatusCommon);
end
D=table(labels,sigma,r2,sigmaSelf,r2Self,cap,capSelf,A48,A812,A1215,status, ...
    'VariableNames',{'caseName','sigmaD_srcPOD_4to12','R2_srcPOD', ...
    'sigmaD_selfPOD_4to12','R2_selfPOD','commonPodCapture','selfPodCapture', ...
    'AcommonRms_4to8','AcommonRms_8to12','AcommonRms_12to15','fitStatus'});
end

function s=local_num(x)
if isempty(x)||~isfinite(x),s='NA';else,s=sprintf('%.7g',x);end
end
