%RUN_0493X7X_VK_750_DIV0_ABLATION_X7U_X7V
% Offline analysis for the completed calibrated 750x200 VK ablation runs.
% Run from repository matlab/. No solver is launched.
%
% Comparison:
%   SRC 750x200 reference
%   production Q6GF 750x200 (density ON, B1 ON)
%   Q6GF div0 B1-on
%   Q6GF div0 B1-off
%
% x7u is run once for all four physical runs.
% x7v is run three times because it intentionally selects only one canonical
% src-q6-g-f run per parent configuration.  The same SRC rows and therefore the
% same SRC-POD construction are used in all three x7v comparisons.

clearvars;

baselineRoot = '../runs/0434_vk_darcy_chi_periodic_750x200_g6_u0.9_kBT5.0';
onRoot       = '../runs/0493x7x_vk_cal750_div0_b1on';
offRoot      = '../runs/0493x7x_vk_cal750_div0_b1off';

refSrc  = fullfile(baselineRoot,'src');
prodGF  = fullfile(baselineRoot,'src-q6-g-f');
expOn   = fullfile(onRoot,'src-q6-g-f');
expOff  = fullfile(offRoot,'src-q6-g-f');

local_assert_run(refSrc,'SRC 750 reference');
local_assert_run(prodGF,'Q6GF production 750');
local_assert_run(expOn,'Q6GF div0 B1-on 750');
local_assert_run(expOff,'Q6GF div0 B1-off 750');

fprintf('\n===== 0493x7x VK CALIBRATED 750x200 ABLATION =====\n');
fprintf('SRC       : %s\n',refSrc);
fprintf('production: %s\n',prodGF);
fprintf('div0 B1on : %s\n',expOn);
fprintf('div0 B1off: %s\n',expOff);

%% 1) x7u once
x7uOutput='../runs/vk_vorticity_transport_0493x7x_750_div0_ablation';

suiteU=analyze_vk_vorticity_transport_0493x7u( ...
    'RunPatterns',{refSrc,prodGF,expOn,expOff}, ...
    'OutputDir',x7uOutput, ...
    'AnalysisCellsPerDiameter',20, ...
    'SensitivityCheck',true, ...
    'SensitivityCellsPerDiameter',16, ...
    'DumpStride',1, ...
    'FirstPassStartDiameters',4.0, ...
    'WrapLimitDomainTransits',0.80, ...
    ... % Div0/B1 variants do not have their own x7t viscosity calibration.
    'AutoUseX7TViscosities',false, ...
    'MakePlots',true, ...
    'ShowFigures',true, ...
    'WriteFieldCsv',true);

T=suiteU.timeseries;
S=suiteU.summary;
T.mode=string(T.mode);
T.runDir=string(T.runDir);
S.mode=string(S.mode);
S.caseLabel=string(S.caseLabel);

p=replace(T.runDir,"\","/");
prodMask=contains(p,'0434_vk_darcy_chi_periodic_750x200_g6_u0.9_kBT5.0/src-q6-g-f');
onMask=contains(p,'0493x7x_vk_cal750_div0_b1on/src-q6-g-f');
offMask=contains(p,'0493x7x_vk_cal750_div0_b1off/src-q6-g-f');
srcMask=T.mode=="src";

assert(any(srcMask),'No SRC 750 rows in x7u output.');
assert(any(prodMask),'No production Q6GF 750 rows in x7u output.');
assert(any(onMask),'No div0 B1-on 750 rows in x7u output.');
assert(any(offMask),'No div0 B1-off 750 rows in x7u output.');

%% 2) Build three explicit x7v inputs sharing the same SRC rows
Tp=T(srcMask | prodMask,:);
Ton=T(srcMask | onMask,:);
Toff=T(srcMask | offMask,:);

Tp.parentRun(:)=string(baselineRoot);
Ton.parentRun(:)=string(baselineRoot);
Toff.parentRun(:)=string(baselineRoot);

inProd=fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_prod_0493x7x.csv');
inOn=fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_div0_b1on_0493x7x.csv');
inOff=fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_div0_b1off_0493x7x.csv');

writetable(Tp,inProd);
writetable(Ton,inOn);
writetable(Toff,inOff);

outProd='../runs/vk_symmetry_breaking_0493x7x_750_production';
outOn='../runs/vk_symmetry_breaking_0493x7x_750_div0_b1on';
outOff='../runs/vk_symmetry_breaking_0493x7x_750_div0_b1off';

local_manifest(outProd,refSrc,prodGF,1,'production density ON, B1=1');
local_manifest(outOn,refSrc,expOn,1,'div0, B1=1');
local_manifest(outOff,refSrc,expOff,0,'div0, B1=0');

%% 3) x7v three times, same SRC reference
fprintf('\n[0493x7x-analysis] x7v production 750\n');
Vp=local_run_x7v(inProd,outProd);

fprintf('\n[0493x7x-analysis] x7v div0 B1-on 750\n');
Von=local_run_x7v(inOn,outOn);

fprintf('\n[0493x7x-analysis] x7v div0 B1-off 750\n');
Voff=local_run_x7v(inOff,outOff);

Cp=local_cylinder(Vp.summary);
Con=local_cylinder(Von.summary);
Coff=local_cylinder(Voff.summary);

srcP=local_one(Cp,"src");
srcOn=local_one(Con,"src");
srcOff=local_one(Coff,"src");
prod=local_one(Cp,"src-q6-g-f");
gfOn=local_one(Con,"src-q6-g-f");
gfOff=local_one(Coff,"src-q6-g-f");

local_same_ref(srcP,srcOn,'SRC prod/on');
local_same_ref(srcP,srcOff,'SRC prod/off');

%% 4) x7v decision table
labels=["SRC";"Q6GF production densityON B1on";"Q6GF div0 B1on";"Q6GF div0 B1off"];
rows={srcP;prod;gfOn;gfOff};
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
fprintf('SRC                               = %s\n',local_num(srcP.sigmaD_common_primary));

%% 5) x7u transport table
q=replace(S.caseLabel,"\","/");
sSrc=S(S.mode=="src",:);
sProd=S(contains(q,'0434_vk_darcy_chi_periodic_750x200_g6_u0.9_kBT5.0/src-q6-g-f'),:);
sOn=S(contains(q,'0493x7x_vk_cal750_div0_b1on'),:);
sOff=S(contains(q,'0493x7x_vk_cal750_div0_b1off'),:);

assert(height(sSrc)==1,'Expected one SRC x7u summary row.');
assert(height(sProd)==1,'Expected one production Q6GF x7u summary row.');
assert(height(sOn)==1,'Expected one div0 B1-on x7u summary row.');
assert(height(sOff)==1,'Expected one div0 B1-off x7u summary row.');

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

transportCsv=fullfile(x7uOutput,'vk_750_div0_transport_decision_0493x7x.csv');
writetable(X,transportCsv);

fprintf('\n===== 0493x7x 750 OUTPUTS =====\n');
fprintf('x7u=%s\n',x7uOutput);
fprintf('x7v production=%s\n',outProd);
fprintf('x7v B1on=%s\n',outOn);
fprintf('x7v B1off=%s\n',outOff);
fprintf('decision=%s\n',decisionCsv);
fprintf('transport=%s\n',transportCsv);
fprintf('status=COMPLETE\n');

function local_assert_run(runDir,label)
assert(isfolder(runDir),'Missing %s directory: %s',label,runDir);
d=dir(fullfile(runDir,'output','state_step_*.smpcd'));
assert(~isempty(d),'No dumps for %s: %s',label,runDir);
p=dir(fullfile(runDir,'params','*.kv'));
assert(~isempty(p),'No params/*.kv for %s: %s',label,runDir);
steps=nan(numel(d),1);
for k=1:numel(d)
    tok=regexp(d(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok), steps(k)=str2double(tok{1}); end
end
fprintf('[0493x7x-analysis] %-24s dumps=%d finalStep=%g\n',label,numel(d),max(steps));
end

function local_manifest(outDir,src,gf,b1,desc)
if ~exist(outDir,'dir'),mkdir(outDir);end
M=table(["src";"src-q6-g-f"],[string(src);string(gf)], ...
    ["reference SRC";string(desc)],[NaN;b1], ...
    'VariableNames',{'modeSeenByX7v','runDir','interpretation','B1'});
writetable(M,fullfile(outDir,'vk_ablation_manifest_0493x7x.csv'));
end

function suite=local_run_x7v(inputCsv,outDir)
suite=analyze_vk_symmetry_breaking_0493x7v( ...
    'X7UTimeseries',inputCsv, ...
    'OutputDir',outDir, ...
    'AnalysisCellsPerDiameter',20, ...
    'WakeXRangeD',[0.75 7.0], ...
    'WakeHalfHeightD',1.5, ...
    'ReadTauDRange',[4 15], ...
    'WrapLimitDomainTransits',0.80, ...
    'PrimaryFitTauDRange',[4 12], ...
    'FitTauDRanges',[4 8;8 12;12 15;4 12], ...
    'SymmetryAxes',{'cylinder','channel'}, ...
    'PODModes',2, ...
    'MinFitPoints',6, ...
    'MinFitR2',0.70, ...
    'MakePlots',true, ...
    'ShowFigures',true, ...
    'WriteMat',true);
end

function C=local_cylinder(S)
S.mode=string(S.mode);
S.axis=string(S.axis);
C=S(S.axis=="cylinder",:);
end

function r=local_one(C,mode)
m=C.mode==string(mode);
assert(nnz(m)==1,'Expected one cylinder row for %s; got %d.',mode,nnz(m));
r=C(m,:);
end

function local_same_ref(a,b,label)
fields={'sigmaD_common_primary','r2D_common_primary','commonPodCapture','selfPodCapture'};
for k=1:numel(fields)
    f=fields{k}; x=a.(f); y=b.(f);
    if isfinite(x)&&isfinite(y)
        tol=1e-10*max([1,abs(x),abs(y)]);
        assert(abs(x-y)<=tol,'Reference mismatch %s for %s.',label,f);
    end
end
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
