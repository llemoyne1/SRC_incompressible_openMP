%RUN_0493X7X_VK_B1OFF_X7U_X7V Controlled B1-off VK post-processing.
%
% Run FROM repository matlab/.
%
% Comparison:
%   reference SRC        : existing 1200x480 VK
%   reference legacy Q6  : existing 1200x480 VK
%   experimental Q6-g-f : 0493x7x, B1=0
%
% x7u is first run on exactly these three direct run directories.
% Then their x7u rows are assigned one common parent configuration before x7v,
% so x7v constructs the common two-mode POD basis from the existing SRC run.
%
% In THIS x7v output only, the canonical label "src-q6-g-f" means B1=0.
% A manifest is written to make that impossible to confuse with production B1=1.

clear baselineRoot ablationRoot refSrc refQ6 ablQ6gf
clear x7uOutput x7vInput x7vOutput suiteU suiteV

baselineRoot = '../runs/0434_vk_darcy_chi_periodic_1200x480_g6_u0.9_kBT5.0';
ablationRoot = '../runs/0493x7x_vk_b1off_1200x480_g6_u0.9_kBT5.0';

refSrc  = fullfile(baselineRoot,'src');
refQ6   = fullfile(baselineRoot,'src-q6');
ablQ6gf = fullfile(ablationRoot,'src-q6-g-f');

assert(isfolder(refSrc),  'Missing reference SRC directory: %s', refSrc);
assert(isfolder(refQ6),   'Missing reference Q6 directory: %s', refQ6);
assert(isfolder(ablQ6gf), 'Missing Q6GF B1-off directory: %s', ablQ6gf);

x7uOutput = '../runs/vk_vorticity_transport_0493x7x_b1off_analysis';
x7vInput  = fullfile(x7uOutput,'vk_vorticity_timeseries_for_x7v_b1off_0493x7x.csv');
x7vOutput = '../runs/vk_symmetry_breaking_0493x7x_b1off_analysis';

fprintf('\n[0493x7x-analysis] x7u: SRC reference + Q6 reference + Q6GF B1=0\n');

suiteU = analyze_vk_vorticity_transport_0493x7u( ...
    'RunPatterns', {refSrc, refQ6, ablQ6gf}, ...
    'OutputDir', x7uOutput, ...
    'AnalysisCellsPerDiameter', 20, ...
    'SensitivityCheck', true, ...
    'SensitivityCellsPerDiameter', 16, ...
    'DumpStride', 1, ...
    'FirstPassStartDiameters', 4.0, ...
    'WrapLimitDomainTransits', 0.80, ...
    ... % No x7t calibration exists yet for B1=0. Do not borrow B1=1 viscosity.
    'AutoUseX7TViscosities', false, ...
    'MakePlots', true, ...
    'ShowFigures', true, ...
    'WriteFieldCsv', true);

T = suiteU.timeseries;
T.mode = string(T.mode);
expectedModes = ["src","src-q6","src-q6-g-f"];
for k = 1:numel(expectedModes)
    n = nnz(T.mode == expectedModes(k));
    assert(n > 0, 'x7u produced no rows for mode=%s', expectedModes(k));
end

% Direct-directory discovery gives each run its own parentRun.
% x7v must instead see one physical comparison configuration.
[~,baseName] = fileparts(baselineRoot);
T.parentRun(:) = string(baselineRoot);
T.caseLabel = repmat(string(baseName),height(T),1) + "/" + T.mode;
writetable(T,x7vInput);

if ~exist(x7vOutput,'dir')
    mkdir(x7vOutput);
end

manifest = table( ...
    ["src";"src-q6";"src-q6-g-f"], ...
    [string(refSrc);string(refQ6);string(ablQ6gf)], ...
    ["reference SRC";"reference legacy Q6";"Q6-g-f 0493x7x ablation, B1=0"], ...
    [NaN;NaN;0], ...
    'VariableNames',{'modeSeenByX7v','runDir','interpretation','B1'});
writetable(manifest,fullfile(x7vOutput,'vk_b1off_manifest_0493x7x.csv'));

fprintf('\n[0493x7x-analysis] x7v: common SRC POD + Q6 reference + Q6GF B1=0\n');

suiteV = analyze_vk_symmetry_breaking_0493x7v( ...
    'X7UTimeseries', x7vInput, ...
    'OutputDir', x7vOutput, ...
    'AnalysisCellsPerDiameter', 20, ...
    'WakeXRangeD', [0.75 7.0], ...
    'WakeHalfHeightD', 1.5, ...
    'ReadTauDRange', [4 15], ...
    'WrapLimitDomainTransits', 0.80, ...
    'PrimaryFitTauDRange', [4 12], ...
    'FitTauDRanges', [4 8; 8 12; 12 15; 4 12], ...
    'SymmetryAxes', {'cylinder','channel'}, ...
    'PODModes', 2, ...
    'MinFitPoints', 6, ...
    'MinFitR2', 0.70, ...
    'MakePlots', true, ...
    'ShowFigures', true, ...
    'WriteMat', true);

Snew = suiteV.summary;
Snew.mode = string(Snew.mode);
Snew.axis = string(Snew.axis);
C = Snew(Snew.axis=="cylinder",:);

fprintf('\n===== 0493x7x VK B1-OFF DECISION TABLE =====\n');
for k = 1:height(C)
    label = char(C.mode(k));
    if C.mode(k) == "src-q6-g-f"
        label = 'src-q6-g-f [B1=0]';
    end
    fprintf('%-23s sigmaD(srcPOD,4-12)=%s R2=%s sigmaD(selfPOD)=%s capture(src/self)=%.4f/%.4f status=%s\n', ...
        label, local_num_0493x7x(C.sigmaD_common_primary(k)), ...
        local_num_0493x7x(C.r2D_common_primary(k)), ...
        local_num_0493x7x(C.sigmaD_self_primary(k)), ...
        C.commonPodCapture(k), C.selfPodCapture(k), char(C.fitStatusCommon(k)));
end

% If the previous B1=1 x7v summary is present, print a direct ablation comparison.
oldSummary = '../runs/vk_symmetry_breaking_0493x7v_analysis/vk_symmetry_breaking_summary_0493x7v.csv';
if isfile(oldSummary)
    Sold = readtable(oldSummary);
    Sold.mode = string(Sold.mode);
    Sold.axis = string(Sold.axis);

    if ismember('configuration',Sold.Properties.VariableNames)
        Sold.configuration = string(Sold.configuration);
        old = Sold(Sold.axis=="cylinder" & contains(Sold.configuration,string(baseName)),:);
    else
        old = Sold(Sold.axis=="cylinder",:);
    end

    oldProd = old(old.mode=="src-q6-g-f",:);
    oldQ6   = old(old.mode=="src-q6",:);
    oldSrc  = old(old.mode=="src",:);
    newOff  = C(C.mode=="src-q6-g-f",:);

    if ~isempty(oldProd) && ~isempty(newOff)
        fprintf('\n[0493x7x-analysis] direct B1 comparison:\n');
        fprintf('  Q6GF production B1=1 sigmaD = %s\n', local_num_0493x7x(oldProd.sigmaD_common_primary(1)));
        fprintf('  Q6GF ablation   B1=0 sigmaD = %s\n', local_num_0493x7x(newOff.sigmaD_common_primary(1)));
        if ~isempty(oldQ6)
            fprintf('  legacy Q6 reference    sigmaD = %s\n', local_num_0493x7x(oldQ6.sigmaD_common_primary(1)));
        end
        if ~isempty(oldSrc)
            fprintf('  SRC reference          sigmaD = %s\n', local_num_0493x7x(oldSrc.sigmaD_common_primary(1)));
        end
    else
        fprintf('[0493x7x-analysis] previous B1=1 row not uniquely found for this configuration.\n');
    end
else
    fprintf('[0493x7x-analysis] previous production x7v summary absent; direct B1=1 comparison not printed.\n');
end

fprintf('x7uOutput=%s\n',x7uOutput);
fprintf('x7vInput=%s\n',x7vInput);
fprintf('x7vOutput=%s\n',x7vOutput);
fprintf('status=COMPLETE\n');

function s = local_num_0493x7x(x)
if isempty(x) || ~isfinite(x)
    s='NA';
else
    s=sprintf('%.6g',x);
end
end
