%RUN_0493X7X_VK_1200_DIV0_ABLATION_X7U_X7V
% Offline x7u/x7v analysis for completed 1200x480 VK div0 B1-on/B1-off runs.
% Run from repository matlab/. No solver is launched.

clearvars;

baselineRoot = '../runs/0434_vk_darcy_chi_periodic_1200x480_g6_u0.9_kBT5.0';
onRoot       = '../runs/0493x7x_vk_div0_b1on_1200x480_g6_u0.9_kBT5.0';
offRoot      = '../runs/0493x7x_vk_div0_b1off_1200x480_g6_u0.9_kBT5.0';

refSrc = fullfile(baselineRoot,'src');
refQ6  = fullfile(baselineRoot,'src-q6');
expOn  = fullfile(onRoot,'src-q6-g-f');
expOff = fullfile(offRoot,'src-q6-g-f');

local_assert_run(refSrc,'reference SRC');
local_assert_run(refQ6,'reference Q6');
local_assert_run(expOn,'Q6GF div0 B1-on');
local_assert_run(expOff,'Q6GF div0 B1-off');

fprintf('\n===== 0493x7x VK 1200x480 DIV0 ABLATION =====\n');
fprintf('SRC       : %s\n',refSrc);
fprintf('Q6        : %s\n',refQ6);
fprintf('div0 B1on : %s\n',expOn);
fprintf('div0 B1off: %s\n',expOff);

%% 1) x7u once for all four runs
x7uOutput = '../runs/vk_vorticity_transport_0493x7x_1200_div0_ablation';

suiteU = analyze_vk_vorticity_transport_0493x7u( ...
    'RunPatterns',{refSrc,refQ6,expOn,expOff}, ...
    'OutputDir',x7uOutput, ...
    'AnalysisCellsPerDiameter',20, ...
    'SensitivityCheck',true, ...
    'SensitivityCellsPerDiameter',16, ...
    'DumpStride',1, ...
    'FirstPassStartDiameters',4.0, ...
    'WrapLimitDomainTransits',0.80, ...
    'AutoUseX7TViscosities',false, ...
    'MakePlots',true, ...
    'ShowFigures',true, ...
    'WriteFieldCsv',true);

T = suiteU.timeseries;
S = suiteU.summary;
T.mode = string(T.mode);
T.runDir = string(T.runDir);
S.mode = string(S.mode);
S.caseLabel = string(S.caseLabel);

normRun = replace(T.runDir,"\","/");
onMaskT = contains(normRun,'0493x7x_vk_div0_b1on_1200x480_g6_u0.9_kBT5.0');
offMaskT = contains(normRun,'0493x7x_vk_div0_b1off_1200x480_g6_u0.9_kBT5.0');
refMaskT = T.mode=="src" | T.mode=="src-q6";

assert(any(onMaskT),'x7u returned no div0 B1-on rows.');
assert(any(offMaskT),'x7u returned no div0 B1-off rows.');
assert(any(T.mode=="src"),'x7u returned no SRC rows.');
assert(any(T.mode=="src-q6"),'x7u returned no Q6 rows.');

%% 2) Explicit x7v inputs: same SRC/Q6, one Q6GF ablation at a time
Ton = T(refMaskT | onMaskT,:);
Toff = T(refMaskT | offMaskT,:);
Ton.parentRun(:) = string(baselineRoot);
Toff.parentRun(:) = string(baselineRoot);

x7vInputOn  = fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_div0_b1on_0493x7x.csv');
x7vInputOff = fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_div0_b1off_0493x7x.csv');
writetable(Ton,x7vInputOn);
writetable(Toff,x7vInputOff);

x7vOutputOn  = '../runs/vk_symmetry_breaking_0493x7x_1200_div0_b1on';
x7vOutputOff = '../runs/vk_symmetry_breaking_0493x7x_1200_div0_b1off';

local_manifest(x7vOutputOn,refSrc,refQ6,expOn,1,'Q6GF div0 B1=1');
local_manifest(x7vOutputOff,refSrc,refQ6,expOff,0,'Q6GF div0 B1=0');

%% 3) x7v B1-on and B1-off
fprintf('\n[0493x7x-analysis] x7v A: div0 B1-on\n');
suiteVOn = local_run_x7v(x7vInputOn,x7vOutputOn);

fprintf('\n[0493x7x-analysis] x7v B: div0 B1-off\n');
suiteVOff = local_run_x7v(x7vInputOff,x7vOutputOff);

Con = suiteVOn.summary;
Coff = suiteVOff.summary;
Con.mode=string(Con.mode); Con.axis=string(Con.axis);
Coff.mode=string(Coff.mode); Coff.axis=string(Coff.axis);
Con=Con(Con.axis=="cylinder",:);
Coff=Coff(Coff.axis=="cylinder",:);

srcOn=local_one(Con,"src");
q6On=local_one(Con,"src-q6");
gfOn=local_one(Con,"src-q6-g-f");
srcOff=local_one(Coff,"src");
q6Off=local_one(Coff,"src-q6");
gfOff=local_one(Coff,"src-q6-g-f");

local_same_ref(srcOn,srcOff,'SRC');
local_same_ref(q6On,q6Off,'Q6');

%% 4) Existing production Q6GF result if present
oldSummary='../runs/vk_symmetry_breaking_0493x7v_analysis/vk_symmetry_breaking_summary_0493x7v.csv';
prod=table();
if isfile(oldSummary)
    P=readtable(oldSummary,'VariableNamingRule','preserve');
    P.mode=string(P.mode);
    P.axis=string(P.axis);
    if ismember('configuration',P.Properties.VariableNames)
        P.configuration=string(P.configuration);
        m=P.axis=="cylinder" & P.mode=="src-q6-g-f" & contains(replace(P.configuration,"\","/"),'1200x480');
    else
        m=P.axis=="cylinder" & P.mode=="src-q6-g-f";
    end
    if nnz(m)==1
        prod=P(m,:);
    else
        warning('0493x7x:productionRow','Could not identify one unique production 1200x480 Q6GF row.');
    end
end

%% 5) x7v decision table
labels=["SRC";"legacy Q6"];
rows={srcOn;q6On};
if ~isempty(prod)
    labels(end+1,1)="Q6GF production densityON B1on";
    rows{end+1,1}=prod;
end
labels(end+1,1)="Q6GF div0 B1on";
rows{end+1,1}=gfOn;
labels(end+1,1)="Q6GF div0 B1off";
rows{end+1,1}=gfOff;

D=local_decision(labels,rows);

fprintf('\n===== 0493x7x VK 1200x480 X7V DECISION TABLE =====\n');
disp(D);

decisionCsv='../runs/vk_symmetry_breaking_0493x7x_1200_div0_decision.csv';
writetable(D,decisionCsv);

fprintf('\n===== 0493x7x CAUSAL DELTAS =====\n');
fprintf('Q6GF div0 B1on  sigmaD = %s\n',local_num(gfOn.sigmaD_common_primary));
fprintf('Q6GF div0 B1off sigmaD = %s\n',local_num(gfOff.sigmaD_common_primary));
fprintf('B1-off minus B1-on      = %s\n',local_num(gfOff.sigmaD_common_primary-gfOn.sigmaD_common_primary));
fprintf('Q6 reference            = %s\n',local_num(q6On.sigmaD_common_primary));
fprintf('SRC reference           = %s\n',local_num(srcOn.sigmaD_common_primary));
if ~isempty(prod)
    fprintf('Q6GF production          = %s\n',local_num(prod.sigmaD_common_primary));
    fprintf('div0 B1on - production  = %s\n',local_num(gfOn.sigmaD_common_primary-prod.sigmaD_common_primary));
end

%% 6) x7u transport table
normLabel=replace(S.caseLabel,"\","/");
onMaskS=contains(normLabel,'0493x7x_vk_div0_b1on');
offMaskS=contains(normLabel,'0493x7x_vk_div0_b1off');

Ssrc=S(S.mode=="src",:);
Sq6=S(S.mode=="src-q6",:);
Son=S(onMaskS,:);
Soff=S(offMaskS,:);

assert(height(Ssrc)==1,'Expected one SRC x7u summary row.');
assert(height(Sq6)==1,'Expected one Q6 x7u summary row.');
assert(height(Son)==1,'Expected one div0 B1-on x7u summary row.');
assert(height(Soff)==1,'Expected one div0 B1-off x7u summary row.');

X=table( ...
    ["SRC";"legacy Q6";"Q6GF div0 B1on";"Q6GF div0 B1off"], ...
    [Ssrc.UinfMeanFirstPass;Sq6.UinfMeanFirstPass;Son.UinfMeanFirstPass;Soff.UinfMeanFirstPass], ...
    [Ssrc.omegaGeneratorStarMeanFirstPass;Sq6.omegaGeneratorStarMeanFirstPass;Son.omegaGeneratorStarMeanFirstPass;Soff.omegaGeneratorStarMeanFirstPass], ...
    [Ssrc.omegaNearStarMeanFirstPass;Sq6.omegaNearStarMeanFirstPass;Son.omegaNearStarMeanFirstPass;Soff.omegaNearStarMeanFirstPass], ...
    [Ssrc.vorticitySurvivalGeneratorToNear;Sq6.vorticitySurvivalGeneratorToNear;Son.vorticitySurvivalGeneratorToNear;Soff.vorticitySurvivalGeneratorToNear], ...
    [Ssrc.spectralPeakFraction;Sq6.spectralPeakFraction;Son.spectralPeakFraction;Soff.spectralPeakFraction], ...
    [Ssrc.probe2D4DCorrelation;Sq6.probe2D4DCorrelation;Son.probe2D4DCorrelation;Soff.probe2D4DCorrelation], ...
    'VariableNames',{'caseName','UinfMeanFirstPass','omegaGeneratorStar','omegaNearStar', ...
    'generatorToNearSurvival','spectralPeakFraction','probe2D4DCorrelation'});

fprintf('\n===== 0493x7x VK 1200x480 X7U TRANSPORT TABLE =====\n');
disp(X);

transportCsv=fullfile(x7uOutput,'vk_div0_transport_decision_0493x7x.csv');
writetable(X,transportCsv);

fprintf('\n===== 0493x7x OUTPUTS =====\n');
fprintf('x7u=%s\n',x7uOutput);
fprintf('x7v B1on=%s\n',x7vOutputOn);
fprintf('x7v B1off=%s\n',x7vOutputOff);
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
fprintf('[0493x7x-analysis] %-20s dumps=%d finalStep=%g\n',label,numel(d),max(steps));
end

function local_manifest(outDir,refSrc,refQ6,exp,b1,desc)
if ~exist(outDir,'dir'), mkdir(outDir); end
M=table(["src";"src-q6";"src-q6-g-f"], ...
    [string(refSrc);string(refQ6);string(exp)], ...
    ["reference SRC";"reference legacy Q6";string(desc)], ...
    [NaN;NaN;b1], ...
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

function r=local_one(C,mode)
m=C.mode==string(mode);
assert(nnz(m)==1,'Expected one cylinder row for %s; got %d.',mode,nnz(m));
r=C(m,:);
end

function local_same_ref(a,b,label)
fields={'sigmaD_common_primary','r2D_common_primary','commonPodCapture','selfPodCapture'};
for k=1:numel(fields)
    f=fields{k};
    x=a.(f); y=b.(f);
    if isfinite(x) && isfinite(y)
        tol=1e-10*max([1,abs(x),abs(y)]);
        assert(abs(x-y)<=tol,'Reference %s differs for %s.',label,f);
    end
end
end

function D=local_decision(labels,rows)
n=numel(rows);
sigma=nan(n,1); r2=nan(n,1); sigmaSelf=nan(n,1); r2Self=nan(n,1);
cap=nan(n,1); capSelf=nan(n,1); A48=nan(n,1); A812=nan(n,1); A1215=nan(n,1);
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
if isempty(x) || ~isfinite(x), s='NA'; else, s=sprintf('%.7g',x); end
end
