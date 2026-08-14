%RESUME_0493X7X_VK_1200_RESULTS
% Resume-only aggregation after x7u/x7v have already completed.
% No x7u rerun, no x7v rerun, no solver run.
% Run from repository matlab/.

clearvars;

x7uSummary='../runs/vk_vorticity_transport_0493x7x_1200_div0_ablation/vk_vorticity_summary_0493x7u.csv';
x7vOn='../runs/vk_symmetry_breaking_0493x7x_1200_div0_b1on/vk_symmetry_breaking_summary_0493x7v.csv';
x7vOff='../runs/vk_symmetry_breaking_0493x7x_1200_div0_b1off/vk_symmetry_breaking_summary_0493x7v.csv';
oldProd='../runs/vk_symmetry_breaking_0493x7v_analysis/vk_symmetry_breaking_summary_0493x7v.csv';

assert(isfile(x7uSummary),'Missing x7u summary: %s',x7uSummary);
assert(isfile(x7vOn),'Missing B1-on x7v summary: %s',x7vOn);
assert(isfile(x7vOff),'Missing B1-off x7v summary: %s',x7vOff);

A=readtable(x7vOn,'VariableNamingRule','preserve');
B=readtable(x7vOff,'VariableNamingRule','preserve');
A.mode=string(A.mode); A.axis=string(A.axis);
B.mode=string(B.mode); B.axis=string(B.axis);

src=local_one(A,"src","cylinder");
q6=local_one(A,"src-q6","cylinder");
gfOn=local_one(A,"src-q6-g-f","cylinder");
gfOff=local_one(B,"src-q6-g-f","cylinder");

prod=table();
if isfile(oldProd)
    P=readtable(oldProd,'VariableNamingRule','preserve');
    P.mode=string(P.mode); P.axis=string(P.axis);
    if ismember('configuration',P.Properties.VariableNames)
        P.configuration=string(P.configuration);
        m=P.mode=="src-q6-g-f" & P.axis=="cylinder" & ...
            contains(replace(P.configuration,"\","/"),'1200x480');
    else
        m=P.mode=="src-q6-g-f" & P.axis=="cylinder";
    end
    if nnz(m)==1, prod=P(m,:); end
end

labels=["SRC";"legacy Q6"];
rows={src;q6};
if ~isempty(prod)
    labels(end+1,1)="Q6GF production densityON B1on";
    rows{end+1,1}=prod;
end
labels(end+1,1)="Q6GF div0 B1on"; rows{end+1,1}=gfOn;
labels(end+1,1)="Q6GF div0 B1off"; rows{end+1,1}=gfOff;

D=local_decision(labels,rows);
fprintf('\n===== 0493x7x VK 1200x480 X7V DECISION TABLE =====\n');
disp(D);

decisionCsv='../runs/vk_symmetry_breaking_0493x7x_1200_div0_decision.csv';
writetable(D,decisionCsv);

fprintf('\n===== 0493x7x VK 1200x480 CAUSAL DELTAS =====\n');
if ~isempty(prod)
    fprintf('production densityON B1on sigmaD = %s\n',local_num(prod.sigmaD_common_primary));
    fprintf('density effect: div0-on - production = %s\n', ...
        local_num(gfOn.sigmaD_common_primary-prod.sigmaD_common_primary));
end
fprintf('div0 B1on                 sigmaD = %s\n',local_num(gfOn.sigmaD_common_primary));
fprintf('div0 B1off                sigmaD = %s\n',local_num(gfOff.sigmaD_common_primary));
fprintf('B1 effect at div0: off - on = %s\n',local_num(gfOff.sigmaD_common_primary-gfOn.sigmaD_common_primary));
fprintf('legacy Q6                    = %s\n',local_num(q6.sigmaD_common_primary));
fprintf('SRC                          = %s\n',local_num(src.sigmaD_common_primary));

S=readtable(x7uSummary,'VariableNamingRule','preserve');
S.mode=string(S.mode); S.runDir=string(S.runDir);
rp=replace(S.runDir,"\","/");

mSrc=S.mode=="src" & contains(rp,'0434_vk_darcy_chi_periodic_1200x480_g6_u0.9_kBT5.0');
mQ6=S.mode=="src-q6" & contains(rp,'0434_vk_darcy_chi_periodic_1200x480_g6_u0.9_kBT5.0');
mOn=S.mode=="src-q6-g-f" & contains(rp,'0493x7x_vk_div0_b1on_1200x480');
mOff=S.mode=="src-q6-g-f" & contains(rp,'0493x7x_vk_div0_b1off_1200x480');

fprintf('\n[0493x7x-resume] x7u row selection SRC/Q6/on/off = %d/%d/%d/%d\n', ...
    nnz(mSrc),nnz(mQ6),nnz(mOn),nnz(mOff));

assert(nnz(mSrc)==1 && nnz(mQ6)==1 && nnz(mOn)==1 && nnz(mOff)==1, ...
    'Expected exactly one x7u row per 1200 physical case.');

sSrc=S(mSrc,:); sQ6=S(mQ6,:); sOn=S(mOn,:); sOff=S(mOff,:);

X=table( ...
    ["SRC";"legacy Q6";"Q6GF div0 B1on";"Q6GF div0 B1off"], ...
    [sSrc.UinfMeanFirstPass;sQ6.UinfMeanFirstPass;sOn.UinfMeanFirstPass;sOff.UinfMeanFirstPass], ...
    [sSrc.omegaGeneratorStarMeanFirstPass;sQ6.omegaGeneratorStarMeanFirstPass;sOn.omegaGeneratorStarMeanFirstPass;sOff.omegaGeneratorStarMeanFirstPass], ...
    [sSrc.omegaNearStarMeanFirstPass;sQ6.omegaNearStarMeanFirstPass;sOn.omegaNearStarMeanFirstPass;sOff.omegaNearStarMeanFirstPass], ...
    [sSrc.vorticitySurvivalGeneratorToNear;sQ6.vorticitySurvivalGeneratorToNear;sOn.vorticitySurvivalGeneratorToNear;sOff.vorticitySurvivalGeneratorToNear], ...
    [sSrc.spectralPeakFraction;sQ6.spectralPeakFraction;sOn.spectralPeakFraction;sOff.spectralPeakFraction], ...
    [sSrc.probe2D4DCorrelation;sQ6.probe2D4DCorrelation;sOn.probe2D4DCorrelation;sOff.probe2D4DCorrelation], ...
    'VariableNames',{'caseName','UinfMeanFirstPass','omegaGeneratorStar','omegaNearStar', ...
    'generatorToNearSurvival','spectralPeakFraction','probe2D4DCorrelation'});

fprintf('\n===== 0493x7x VK 1200x480 X7U TRANSPORT TABLE =====\n');
disp(X);

transportCsv='../runs/vk_vorticity_transport_0493x7x_1200_div0_ablation/vk_div0_transport_decision_0493x7x.csv';
writetable(X,transportCsv);

fprintf('\ndecision=%s\ntransport=%s\nstatus=COMPLETE\n',decisionCsv,transportCsv);

function r=local_one(T,mode,axisName)
m=T.mode==string(mode) & T.axis==string(axisName);
assert(nnz(m)==1,'Expected one %s/%s row; got %d.',mode,axisName,nnz(m));
r=T(m,:);
end

function D=local_decision(labels,rows)
n=numel(rows);
sigma=nan(n,1);r2=nan(n,1);sigmaSelf=nan(n,1);r2Self=nan(n,1);
cap=nan(n,1);capSelf=nan(n,1);A48=nan(n,1);A812=nan(n,1);A1215=nan(n,1);status=strings(n,1);
for i=1:n
 r=rows{i}; sigma(i)=r.sigmaD_common_primary; r2(i)=r.r2D_common_primary;
 sigmaSelf(i)=r.sigmaD_self_primary; r2Self(i)=r.r2D_self_primary;
 cap(i)=r.commonPodCapture; capSelf(i)=r.selfPodCapture;
 A48(i)=r.AcommonRmsTau4to8; A812(i)=r.AcommonRmsTau8to12; A1215(i)=r.AcommonRmsTau12to15;
 status(i)=string(r.fitStatusCommon);
end
D=table(labels,sigma,r2,sigmaSelf,r2Self,cap,capSelf,A48,A812,A1215,status, ...
 'VariableNames',{'caseName','sigmaD_srcPOD_4to12','R2_srcPOD','sigmaD_selfPOD_4to12','R2_selfPOD', ...
 'commonPodCapture','selfPodCapture','AcommonRms_4to8','AcommonRms_8to12','AcommonRms_12to15','fitStatus'});
end

function s=local_num(x)
if isempty(x)||~isfinite(x),s='NA';else,s=sprintf('%.7g',x);end
end
