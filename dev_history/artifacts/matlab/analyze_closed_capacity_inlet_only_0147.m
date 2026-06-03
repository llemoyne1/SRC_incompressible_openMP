function R = analyze_closed_capacity_inlet_only_0147(runRoot, varargin)
%ANALYZE_CLOSED_CAPACITY_INLET_ONLY_0147 Post-process closed-capacity inlet-only runs.
%
%   R = analyze_closed_capacity_inlet_only_0147(runRoot)
%
%   This analyzer is intended for the OpenMP script
%   scripts/run_closed_capacity_inlet_only_0147.sh.  It reads one or more
%   summary_runtime.csv files under runRoot, builds a compact per-case
%   summary, and generates diagnostic figures for the closed-domain capacity
%   response:
%       - total mass and overfill ratio,
%       - effective Q6 weakening,
%       - virial pressure/stiffness response,
%       - wall-load pressure/force diagnostics for solid boundary portions,
%       - resampling/remap/mass-guard activity,
%       - inlet flux and energy diagnostics;
%       - momentum time series and partial momentum-budget diagnostics when
%         the corresponding runtime columns are available.
%
%   The function is deliberately tolerant to missing columns so it can be
%   used across nearby 0147 variants.
%
%   Examples from the repository root:
%       cd matlab
%       R = analyze_closed_capacity_inlet_only_0147( ...
%           '../runs/closed_capacity_inlet_only_0147');
%
%       R = analyze_closed_capacity_inlet_only_0147( ...
%           '../runs/closed_capacity_inlet_only_0147', ...
%           'showFigures', true, 'saveFigures', true);
%
%   Name/value options:
%       'outputDir'    : directory for figures and CSV summary.  Default:
%                        <runRoot>/matlab_closed_capacity_0147
%       'showFigures'  : true/false. Default true.
%       'saveFigures'  : true/false. Default true.
%       'makeFigures'  : true/false. Default true.
%       'casePattern'  : substring filter applied to case directory names.
%                        Default ''.
%
%   Returned struct fields:
%       R.cases        : struct array containing per-case time series.
%       R.summaryTable : one-row-per-case table with final/key metrics.
%       R.outputDir    : analysis output directory.

opts = local_parse_options(varargin{:});

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','closed_capacity_inlet_only_0147');
end
runRoot = char(runRoot);

if ~exist(runRoot, 'dir')
    error('Run root does not exist: %s', runRoot);
end

if isempty(opts.outputDir)
    opts.outputDir = fullfile(runRoot, 'matlab_closed_capacity_0147');
end
if ~exist(opts.outputDir, 'dir')
    mkdir(opts.outputDir);
end

summaryFiles = local_find_summary_files(runRoot);
if isempty(summaryFiles)
    error('No summary_runtime.csv found under: %s', runRoot);
end

cases = struct([]);
for k = 1:numel(summaryFiles)
    caseDir = fileparts(summaryFiles{k});
    [~, caseName] = fileparts(caseDir);
    if isempty(caseName)
        caseName = sprintf('case_%03d', k);
    end
    if ~isempty(opts.casePattern) && isempty(strfind(caseName, opts.casePattern)) %#ok<STREMP>
        continue;
    end
    T = readtable(summaryFiles{k}, 'FileType', 'text');
    C = local_build_case(T, caseName, caseDir, summaryFiles{k});
    cases = [cases; C]; %#ok<AGROW>
end

if isempty(cases)
    error('No cases matched casePattern=''%s'' under %s.', opts.casePattern, runRoot);
end

summaryTable = local_build_summary_table(cases);
writetable(summaryTable, fullfile(opts.outputDir, 'closed_capacity_0147_summary.csv'));

R = struct();
R.runRoot = runRoot;
R.outputDir = opts.outputDir;
R.cases = cases;
R.summaryTable = summaryTable;

if opts.makeFigures
    for k = 1:numel(cases)
        local_make_case_figures(cases(k), opts);
    end
    local_make_comparison_figures(cases, opts);
end

save(fullfile(opts.outputDir, 'closed_capacity_0147_analysis.mat'), 'R');

fprintf('[0147] Analyzed %d case(s).\n', numel(cases));
fprintf('[0147] Summary: %s\n', fullfile(opts.outputDir, 'closed_capacity_0147_summary.csv'));
fprintf('[0147] MAT file: %s\n', fullfile(opts.outputDir, 'closed_capacity_0147_analysis.mat'));
end

% -------------------------------------------------------------------------
function opts = local_parse_options(varargin)
opts = struct();
opts.outputDir = '';
opts.showFigures = true;
opts.saveFigures = true;
opts.makeFigures = true;
opts.casePattern = '';

if mod(numel(varargin), 2) ~= 0
    error('Options must be name/value pairs.');
end
for i = 1:2:numel(varargin)
    name = lower(string(varargin{i}));
    value = varargin{i+1};
    switch name
        case "outputdir"
            opts.outputDir = char(value);
        case "showfigures"
            opts.showFigures = logical(value);
        case "savefigures"
            opts.saveFigures = logical(value);
        case "makefigures"
            opts.makeFigures = logical(value);
        case "casepattern"
            opts.casePattern = char(value);
        otherwise
            error('Unknown option: %s', name);
    end
end
end

% -------------------------------------------------------------------------
function files = local_find_summary_files(rootDir)
files = {};
listing = dir(rootDir);
for i = 1:numel(listing)
    name = listing(i).name;
    if strcmp(name, '.') || strcmp(name, '..')
        continue;
    end
    p = fullfile(rootDir, name);
    if listing(i).isdir
        files = [files; local_find_summary_files(p)]; %#ok<AGROW>
    else
        if strcmp(name, 'summary_runtime.csv')
            files{end+1,1} = p; %#ok<AGROW>
        end
    end
end
end

% -------------------------------------------------------------------------
function C = local_build_case(T, caseName, caseDir, summaryFile)
C = struct();
C.name = matlab.lang.makeValidName(caseName);
C.label = caseName;
C.caseDir = caseDir;
C.summaryFile = summaryFile;
C.table = T;

n = height(T);
C.step = local_col(T, {'step','Step'}, (0:n-1)');
C.time = local_col(T, {'time','t','Time'}, NaN(n,1));
if all(isnan(C.time))
    dt = local_col(T, {'dt'}, NaN(n,1));
    if ~all(isnan(dt))
        C.time = C.step .* dt;
    else
        C.time = C.step;
    end
end

C.totalMass = local_col(T, {'totalMass','massTotal','Mtotal'}, NaN(n,1));
C.nFluid = local_col(T, {'nFluid','numFluid','nFluidParticles'}, NaN(n,1));
C.nInactive = local_col(T, {'nInactive','numInactive','nInactiveParticles'}, NaN(n,1));

C.capacityReferenceMass = local_col(T, {'capacityReferenceMass','closedCapacityReferenceMass','capacityMassReference'}, NaN(n,1));
C.capacityOverfillRatio = local_col(T, {'capacityOverfillRatio','closedCapacityOverfillRatio','capacityEta','closedCapacityEta'}, NaN(n,1));
if all(isnan(C.capacityReferenceMass)) && ~all(isnan(C.totalMass)) && ~all(isnan(C.capacityOverfillRatio))
    denom = 1.0 + C.capacityOverfillRatio;
    C.capacityReferenceMass = C.totalMass ./ max(denom, eps);
end
if all(isnan(C.capacityOverfillRatio)) && ~all(isnan(C.totalMass)) && ~all(isnan(C.capacityReferenceMass))
    C.capacityOverfillRatio = max(0, (C.totalMass - C.capacityReferenceMass) ./ max(C.capacityReferenceMass, eps));
end

C.q6ProjectionStrengthNominal = local_col(T, {'q6ProjectionStrengthNominal','q6ProjectionStrength'}, NaN(n,1));
C.capacityQ6ProjectionFactor = local_col(T, {'capacityQ6ProjectionFactor','closedCapacityQ6Factor'}, NaN(n,1));
C.q6ProjectionStrengthEffective = local_col(T, {'q6ProjectionStrengthEffective','capacityQ6ProjectionStrengthEffective'}, NaN(n,1));
if all(isnan(C.q6ProjectionStrengthEffective)) && ~all(isnan(C.q6ProjectionStrengthNominal)) && ~all(isnan(C.capacityQ6ProjectionFactor))
    C.q6ProjectionStrengthEffective = C.q6ProjectionStrengthNominal .* C.capacityQ6ProjectionFactor;
end

C.q6DivBeforeRms = local_col(T, {'q6DivBeforeRms','q6DivergenceBeforeRms'}, NaN(n,1));
C.q6DivAfterProjectedFluxRms = local_col(T, {'q6DivAfterProjectedFluxRms','q6DivAfterRms'}, NaN(n,1));
C.q6OpenBoundaryFluxBalance = local_col(T, {'q6OpenBoundaryFluxBalance','openBoundaryFluxBalance'}, NaN(n,1));
C.q6OpenBoundaryMeanDivergence = local_col(T, {'q6OpenBoundaryMeanDivergence','openBoundaryMeanDivergence'}, NaN(n,1));
C.q6OpenBoundaryFluxXLow = local_col(T, {'q6OpenBoundaryFluxXLow'}, NaN(n,1));
C.q6OpenBoundaryFluxXHigh = local_col(T, {'q6OpenBoundaryFluxXHigh'}, NaN(n,1));
C.q6OpenBoundaryFluxYLow = local_col(T, {'q6OpenBoundaryFluxYLow'}, NaN(n,1));
C.q6OpenBoundaryFluxYHigh = local_col(T, {'q6OpenBoundaryFluxYHigh'}, NaN(n,1));

C.capacityVirialKEffective = local_col(T, {'capacityVirialKEffective','closedCapacityVirialKEffective'}, NaN(n,1));
C.capacityVirialPressureMean = local_col(T, {'capacityVirialPressureMean','closedCapacityVirialPressureMean'}, NaN(n,1));
C.capacityVirialPressureRms = local_col(T, {'capacityVirialPressureRms','closedCapacityVirialPressureRms'}, NaN(n,1));
C.capacityVirialPressureMax = local_col(T, {'capacityVirialPressureMax','closedCapacityVirialPressureMax'}, NaN(n,1));
C.capacityVirialKickVelocityRms = local_col(T, {'capacityVirialKickVelocityRms','closedCapacityVirialKickVelocityRms'}, NaN(n,1));
C.capacityVirialKickVelocityMax = local_col(T, {'capacityVirialKickVelocityMax','closedCapacityVirialKickVelocityMax'}, NaN(n,1));

% Wall-load diagnostics: pressure means are length-weighted over solid wall
% portions only. Segmented inlet/outlet apertures are excluded by the runtime.
C.capacityWallLoadComputed = local_col(T, {'capacityWallLoadComputed'}, NaN(n,1));
C.capacityWallSolidLengthTotal = local_col(T, {'capacityWallSolidLengthTotal'}, NaN(n,1));
C.capacityWallPressureKineticMeanAll = local_col(T, {'capacityWallPressureKineticMeanAll'}, NaN(n,1));
C.capacityWallPressureVirialMeanAll = local_col(T, {'capacityWallPressureVirialMeanAll'}, NaN(n,1));
C.capacityWallPressureTotalMeanAll = local_col(T, {'capacityWallPressureTotalMeanAll'}, NaN(n,1));
C.capacityWallPressureTotalMeanLeft = local_col(T, {'capacityWallPressureTotalMeanLeft'}, NaN(n,1));
C.capacityWallPressureTotalMeanRight = local_col(T, {'capacityWallPressureTotalMeanRight'}, NaN(n,1));
C.capacityWallPressureTotalMeanBottom = local_col(T, {'capacityWallPressureTotalMeanBottom'}, NaN(n,1));
C.capacityWallPressureTotalMeanTop = local_col(T, {'capacityWallPressureTotalMeanTop'}, NaN(n,1));
C.capacityWallPressureVirialMeanLeft = local_col(T, {'capacityWallPressureVirialMeanLeft'}, NaN(n,1));
C.capacityWallPressureVirialMeanRight = local_col(T, {'capacityWallPressureVirialMeanRight'}, NaN(n,1));
C.capacityWallPressureVirialMeanBottom = local_col(T, {'capacityWallPressureVirialMeanBottom'}, NaN(n,1));
C.capacityWallPressureVirialMeanTop = local_col(T, {'capacityWallPressureVirialMeanTop'}, NaN(n,1));
C.capacityWallForceKineticX = local_col(T, {'capacityWallForceKineticX'}, NaN(n,1));
C.capacityWallForceKineticY = local_col(T, {'capacityWallForceKineticY'}, NaN(n,1));
C.capacityWallForceVirialX = local_col(T, {'capacityWallForceVirialX'}, NaN(n,1));
C.capacityWallForceVirialY = local_col(T, {'capacityWallForceVirialY'}, NaN(n,1));
C.capacityWallForceTotalX = local_col(T, {'capacityWallForceTotalX'}, NaN(n,1));
C.capacityWallForceTotalY = local_col(T, {'capacityWallForceTotalY'}, NaN(n,1));
C.capacityWallForceTotalMag = hypot(C.capacityWallForceTotalX, C.capacityWallForceTotalY);

C.resampRemapMassCorrectionStrength = local_col(T, {'resampRemapMassCorrectionStrength','capacityResamplingRemapFactor'}, NaN(n,1));
C.resampWetCells = local_col(T, {'resampWetCells'}, NaN(n,1));
C.resampDryCells = local_col(T, {'resampDryCells'}, NaN(n,1));
C.resampEmptyWetCells = local_col(T, {'resampEmptyWetCells'}, NaN(n,1));
C.resampMeanMass = local_col(T, {'resampMeanMass'}, NaN(n,1));
C.resampStdMass = local_col(T, {'resampStdMass'}, NaN(n,1));
C.resampMRelRms = local_col(T, {'resampMRelRms'}, NaN(n,1));
C.resampPopulationGuardWetNMinAfter = local_col(T, {'resampPopulationGuardWetNMinAfter'}, NaN(n,1));
C.resampPopulationGuardWetNMeanAfter = local_col(T, {'resampPopulationGuardWetNMeanAfter'}, NaN(n,1));
C.resampPopulationGuardWetNMaxAfter = local_col(T, {'resampPopulationGuardWetNMaxAfter'}, NaN(n,1));
C.resampPopulationGuardUnderfullCells = local_col(T, {'resampPopulationGuardUnderfullCells'}, NaN(n,1));
C.resampPopulationGuardOverfullCells = local_col(T, {'resampPopulationGuardOverfullCells'}, NaN(n,1));
C.resampPopulationGuardSplitParticlesCreated = local_col(T, {'resampPopulationGuardSplitParticlesCreated'}, NaN(n,1));
C.resampPopulationGuardExtractedParticles = local_col(T, {'resampPopulationGuardExtractedParticles'}, NaN(n,1));
C.resampParticleMassMin = local_col(T, {'resampParticleMassMin'}, NaN(n,1));
C.resampParticleMassMax = local_col(T, {'resampParticleMassMax'}, NaN(n,1));
C.resampMassGuardParticleMassMinAfter = local_col(T, {'resampMassGuardParticleMassMinAfter'}, NaN(n,1));
C.resampMassGuardParticleMassMaxAfter = local_col(T, {'resampMassGuardParticleMassMaxAfter'}, NaN(n,1));

C.inletParticlesInserted = local_col(T, {'inletParticlesInserted'}, NaN(n,1));
C.inletReservoirDeleted = local_col(T, {'inletReservoirDeleted'}, NaN(n,1));
C.inletBackflowDeleted = local_col(T, {'inletBackflowDeleted'}, NaN(n,1));
C.inletNetParticleDelta = local_col(T, {'inletNetParticleDelta'}, NaN(n,1));
C.outletParticlesDeleted = local_col(T, {'outletParticlesDeleted'}, NaN(n,1));

C.meanKinetic = local_col(T, {'meanKinetic','kineticMean'}, NaN(n,1));
C.kBTEstimate = local_col(T, {'kBTEstimate','kBTMean','meanKBT'}, NaN(n,1));
C.thermostatKBTAfter = local_col(T, {'thermostatKBTAfter'}, NaN(n,1));
C.meanVx = local_col(T, {'meanVx','meanUx'}, NaN(n,1));
C.meanVy = local_col(T, {'meanVy','meanUy'}, NaN(n,1));
C.Px = local_col(T, {'Px','momentumX','totalMomentumX'}, NaN(n,1));
C.Py = local_col(T, {'Py','momentumY','totalMomentumY'}, NaN(n,1));
C.Pmag = hypot(C.Px, C.Py);
C.dtStep = local_step_dt(C.time);
C.dPxStep = [NaN; diff(C.Px)];
C.dPyStep = [NaN; diff(C.Py)];
C.dPmagStep = hypot(C.dPxStep, C.dPyStep);
C.dPxDt = C.dPxStep ./ C.dtStep;
C.dPyDt = C.dPyStep ./ C.dtStep;

% Momentum-budget diagnostics.  Most of these columns are optional: current
% 0147/0149 runtime files already expose total momentum and several
% resampling/Q6 momentum components, while future code patches may add
% explicit inlet/wall/virial/thermostat impulse columns.  The analyzer keeps
% all missing terms as NaN and only sums available terms.
C.q6MomentumCorrectionVx = local_col(T, {'q6MomentumCorrectionVx'}, NaN(n,1));
C.q6MomentumCorrectionVy = local_col(T, {'q6MomentumCorrectionVy'}, NaN(n,1));
C.q6MomentumDeltaX = local_col(T, {'q6MomentumDeltaX','q6MomentumCorrectionPx','q6MomentumImpulseX','deltaPQ6X'}, NaN(n,1));
C.q6MomentumDeltaY = local_col(T, {'q6MomentumDeltaY','q6MomentumCorrectionPy','q6MomentumImpulseY','deltaPQ6Y'}, NaN(n,1));
if all(isnan(C.q6MomentumDeltaX)) && ~all(isnan(C.q6MomentumCorrectionVx)) && ~all(isnan(C.totalMass))
    C.q6MomentumDeltaX = C.totalMass .* C.q6MomentumCorrectionVx;
end
if all(isnan(C.q6MomentumDeltaY)) && ~all(isnan(C.q6MomentumCorrectionVy)) && ~all(isnan(C.totalMass))
    C.q6MomentumDeltaY = C.totalMass .* C.q6MomentumCorrectionVy;
end

C.inletMomentumDeltaX = local_col(T, {'inletMomentumDeltaX','inletNetMomentumDeltaX','inletImpulseX','deltaPInletX'}, NaN(n,1));
C.inletMomentumDeltaY = local_col(T, {'inletMomentumDeltaY','inletNetMomentumDeltaY','inletImpulseY','deltaPInletY'}, NaN(n,1));
C.wallMomentumDeltaX = local_col(T, {'wallMomentumDeltaX','wallImpulseX','solidWallMomentumDeltaX','boundaryWallMomentumDeltaX','deltaPWallX'}, NaN(n,1));
C.wallMomentumDeltaY = local_col(T, {'wallMomentumDeltaY','wallImpulseY','solidWallMomentumDeltaY','boundaryWallMomentumDeltaY','deltaPWallY'}, NaN(n,1));
C.virialMomentumDeltaX = local_col(T, {'capacityVirialMomentumDeltaX','capacityVirialKickMomentumDeltaX','virialMomentumDeltaX','virialImpulseX','deltaPVirialX'}, NaN(n,1));
C.virialMomentumDeltaY = local_col(T, {'capacityVirialMomentumDeltaY','capacityVirialKickMomentumDeltaY','virialMomentumDeltaY','virialImpulseY','deltaPVirialY'}, NaN(n,1));
C.virialMomentumRawX = local_col(T, {'capacityVirialMomentumRawX','capacityVirialKickMomentumRawX','virialMomentumRawX','virialRawImpulseX'}, NaN(n,1));
C.virialMomentumRawY = local_col(T, {'capacityVirialMomentumRawY','capacityVirialKickMomentumRawY','virialMomentumRawY','virialRawImpulseY'}, NaN(n,1));
C.virialMomentumCorrectionX = local_col(T, {'capacityVirialMomentumCorrectionX','capacityVirialKickMomentumCorrectionX','virialMomentumCorrectionX'}, NaN(n,1));
C.virialMomentumCorrectionY = local_col(T, {'capacityVirialMomentumCorrectionY','capacityVirialKickMomentumCorrectionY','virialMomentumCorrectionY'}, NaN(n,1));
C.thermostatMomentumDeltaX = local_col(T, {'thermostatMomentumDeltaX','thermostatImpulseX','deltaPThermostatX'}, NaN(n,1));
C.thermostatMomentumDeltaY = local_col(T, {'thermostatMomentumDeltaY','thermostatImpulseY','deltaPThermostatY'}, NaN(n,1));

C.resampExtractionMomentumDeltaX = -local_col(T, {'resampExtractionApplyMomentumX'}, NaN(n,1));
C.resampExtractionMomentumDeltaY = -local_col(T, {'resampExtractionApplyMomentumY'}, NaN(n,1));
C.resampInsertionMomentumDeltaX = local_col(T, {'resampInsertionApplyMomentumX'}, NaN(n,1));
C.resampInsertionMomentumDeltaY = local_col(T, {'resampInsertionApplyMomentumY'}, NaN(n,1));
C.resampRemapMomentumDeltaX = local_col(T, {'resampRemapMomentumDeltaX'}, NaN(n,1));
C.resampRemapMomentumDeltaY = local_col(T, {'resampRemapMomentumDeltaY'}, NaN(n,1));
if all(isnan(C.resampRemapMomentumDeltaX))
    beforeX = local_col(T, {'resampRemapMomentumXBefore'}, NaN(n,1));
    afterX = local_col(T, {'resampRemapMomentumXAfter'}, NaN(n,1));
    if ~all(isnan(beforeX)) && ~all(isnan(afterX))
        C.resampRemapMomentumDeltaX = afterX - beforeX;
    end
end
if all(isnan(C.resampRemapMomentumDeltaY))
    beforeY = local_col(T, {'resampRemapMomentumYBefore'}, NaN(n,1));
    afterY = local_col(T, {'resampRemapMomentumYAfter'}, NaN(n,1));
    if ~all(isnan(beforeY)) && ~all(isnan(afterY))
        C.resampRemapMomentumDeltaY = afterY - beforeY;
    end
end
C.resampLatentActivationMomentumDeltaX = local_col(T, {'resampLatentActivationMomentumX'}, NaN(n,1));
C.resampLatentActivationMomentumDeltaY = local_col(T, {'resampLatentActivationMomentumY'}, NaN(n,1));
C.resampMomentumDeltaX = local_sum_available(n, {C.resampExtractionMomentumDeltaX, C.resampInsertionMomentumDeltaX, C.resampRemapMomentumDeltaX, C.resampLatentActivationMomentumDeltaX});
C.resampMomentumDeltaY = local_sum_available(n, {C.resampExtractionMomentumDeltaY, C.resampInsertionMomentumDeltaY, C.resampRemapMomentumDeltaY, C.resampLatentActivationMomentumDeltaY});

C.knownMomentumDeltaX = local_sum_available(n, {C.inletMomentumDeltaX, C.wallMomentumDeltaX, C.q6MomentumDeltaX, C.virialMomentumDeltaX, C.thermostatMomentumDeltaX, C.resampMomentumDeltaX});
C.knownMomentumDeltaY = local_sum_available(n, {C.inletMomentumDeltaY, C.wallMomentumDeltaY, C.q6MomentumDeltaY, C.virialMomentumDeltaY, C.thermostatMomentumDeltaY, C.resampMomentumDeltaY});
if ~all(isnan(C.knownMomentumDeltaX))
    C.momentumBudgetResidualX = C.dPxStep - C.knownMomentumDeltaX;
else
    C.momentumBudgetResidualX = NaN(n,1);
end
if ~all(isnan(C.knownMomentumDeltaY))
    C.momentumBudgetResidualY = C.dPyStep - C.knownMomentumDeltaY;
else
    C.momentumBudgetResidualY = NaN(n,1);
end
end

% -------------------------------------------------------------------------
function x = local_col(T, names, fallback)
x = [];
vars = T.Properties.VariableNames;
for i = 1:numel(names)
    idx = find(strcmp(vars, names{i}), 1);
    if ~isempty(idx)
        x = T.(vars{idx});
        if iscell(x) || isstring(x) || ischar(x)
            x = str2double(string(x));
        end
        x = double(x(:));
        return;
    end
end
if isscalar(fallback)
    x = fallback * ones(height(T),1);
else
    x = double(fallback(:));
end
end

% -------------------------------------------------------------------------
function S = local_build_summary_table(cases)
caseName = strings(numel(cases),1);
finalStep = NaN(numel(cases),1);
finalTime = NaN(numel(cases),1);
finalMass = NaN(numel(cases),1);
finalOverfill = NaN(numel(cases),1);
maxOverfill = NaN(numel(cases),1);
finalQ6Factor = NaN(numel(cases),1);
finalQ6StrengthEff = NaN(numel(cases),1);
finalKvirEff = NaN(numel(cases),1);
finalPvirMean = NaN(numel(cases),1);
maxPvirMean = NaN(numel(cases),1);
finalVirialKickRms = NaN(numel(cases),1);
finalRemapStrength = NaN(numel(cases),1);
finalKBT = NaN(numel(cases),1);
finalMeanKinetic = NaN(numel(cases),1);
finalDivAfter = NaN(numel(cases),1);
maxEmptyWetCells = NaN(numel(cases),1);
maxParticleMass = NaN(numel(cases),1);
finalMomentumX = NaN(numel(cases),1);
finalMomentumY = NaN(numel(cases),1);
finalMomentumMag = NaN(numel(cases),1);
maxAbsMomentumX = NaN(numel(cases),1);
maxAbsMomentumY = NaN(numel(cases),1);
maxStepMomentumJump = NaN(numel(cases),1);
maxAbsMomentumResidualX = NaN(numel(cases),1);
maxAbsMomentumResidualY = NaN(numel(cases),1);
finalWallPressureTotalMean = NaN(numel(cases),1);
maxWallPressureTotalMean = NaN(numel(cases),1);
finalWallPressureVirialMean = NaN(numel(cases),1);
maxWallPressureVirialMean = NaN(numel(cases),1);
finalWallForceTotalX = NaN(numel(cases),1);
finalWallForceTotalY = NaN(numel(cases),1);
maxWallForceTotalMag = NaN(numel(cases),1);

for k = 1:numel(cases)
    C = cases(k);
    caseName(k) = string(C.label);
    finalStep(k) = local_last(C.step);
    finalTime(k) = local_last(C.time);
    finalMass(k) = local_last(C.totalMass);
    finalOverfill(k) = local_last(C.capacityOverfillRatio);
    maxOverfill(k) = local_nanmax(C.capacityOverfillRatio);
    finalQ6Factor(k) = local_last(C.capacityQ6ProjectionFactor);
    finalQ6StrengthEff(k) = local_last(C.q6ProjectionStrengthEffective);
    finalKvirEff(k) = local_last(C.capacityVirialKEffective);
    finalPvirMean(k) = local_last(C.capacityVirialPressureMean);
    maxPvirMean(k) = local_nanmax(C.capacityVirialPressureMean);
    finalVirialKickRms(k) = local_last(C.capacityVirialKickVelocityRms);
    finalRemapStrength(k) = local_last(C.resampRemapMassCorrectionStrength);
    finalKBT(k) = local_last(C.kBTEstimate);
    finalMeanKinetic(k) = local_last(C.meanKinetic);
    finalDivAfter(k) = local_last(C.q6DivAfterProjectedFluxRms);
    maxEmptyWetCells(k) = local_nanmax(C.resampEmptyWetCells);
    maxParticleMass(k) = local_nanmax(C.resampParticleMassMax);
    finalMomentumX(k) = local_last(C.Px);
    finalMomentumY(k) = local_last(C.Py);
    finalMomentumMag(k) = local_last(C.Pmag);
    maxAbsMomentumX(k) = local_nanmax(abs(C.Px));
    maxAbsMomentumY(k) = local_nanmax(abs(C.Py));
    maxStepMomentumJump(k) = local_nanmax(C.dPmagStep);
    maxAbsMomentumResidualX(k) = local_nanmax(abs(C.momentumBudgetResidualX));
    maxAbsMomentumResidualY(k) = local_nanmax(abs(C.momentumBudgetResidualY));
    finalWallPressureTotalMean(k) = local_last(C.capacityWallPressureTotalMeanAll);
    maxWallPressureTotalMean(k) = local_nanmax(C.capacityWallPressureTotalMeanAll);
    finalWallPressureVirialMean(k) = local_last(C.capacityWallPressureVirialMeanAll);
    maxWallPressureVirialMean(k) = local_nanmax(C.capacityWallPressureVirialMeanAll);
    finalWallForceTotalX(k) = local_last(C.capacityWallForceTotalX);
    finalWallForceTotalY(k) = local_last(C.capacityWallForceTotalY);
    maxWallForceTotalMag(k) = local_nanmax(C.capacityWallForceTotalMag);
end

S = table(caseName, finalStep, finalTime, finalMass, finalOverfill, maxOverfill, ...
    finalQ6Factor, finalQ6StrengthEff, finalKvirEff, finalPvirMean, maxPvirMean, ...
    finalVirialKickRms, finalRemapStrength, finalKBT, finalMeanKinetic, ...
    finalDivAfter, maxEmptyWetCells, maxParticleMass, finalMomentumX, ...
    finalMomentumY, finalMomentumMag, maxAbsMomentumX, maxAbsMomentumY, ...
    maxStepMomentumJump, maxAbsMomentumResidualX, maxAbsMomentumResidualY, ...
    finalWallPressureTotalMean, maxWallPressureTotalMean, ...
    finalWallPressureVirialMean, maxWallPressureVirialMean, ...
    finalWallForceTotalX, finalWallForceTotalY, maxWallForceTotalMag);
end

% -------------------------------------------------------------------------
function local_make_case_figures(C, opts)
vis = local_visible(opts.showFigures);
base = fullfile(opts.outputDir, C.name);

% Figure 1: mass, overfill, inlet balance
fig = figure('Name', ['closed capacity mass - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(3,1,1);
plot(C.time, C.totalMass, 'LineWidth', 1.2); hold on;
plot(C.time, C.capacityReferenceMass, '--', 'LineWidth', 1.0);
ylabel('mass'); grid on;
legend(local_existing_labels({'M_{tot}','M_{ref}'}, {C.totalMass,C.capacityReferenceMass}), 'Location','best');
title(['Closed capacity mass response: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(3,1,2);
plot(C.time, 100*C.capacityOverfillRatio, 'LineWidth', 1.2);
ylabel('overfill [%]'); grid on;
local_tiled_or_subplot(3,1,3);
plot(C.time, C.q6OpenBoundaryFluxBalance, 'LineWidth', 1.2); hold on;
plot(C.time, C.q6OpenBoundaryMeanDivergence, '--', 'LineWidth', 1.0);
xlabel('time'); ylabel('flux/div'); grid on;
legend(local_existing_labels({'flux balance','mean div'}, {C.q6OpenBoundaryFluxBalance,C.q6OpenBoundaryMeanDivergence}), 'Location','best');
local_save_fig(fig, base + "_mass_overfill", opts);

% Figure 2: Q6 weakening and divergence
fig = figure('Name', ['closed capacity Q6 - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(3,1,1);
plot(C.time, C.q6ProjectionStrengthEffective, 'LineWidth', 1.2); hold on;
plot(C.time, C.q6ProjectionStrengthNominal, '--', 'LineWidth', 1.0);
ylabel('Q6 strength'); grid on;
legend(local_existing_labels({'effective','nominal'}, {C.q6ProjectionStrengthEffective,C.q6ProjectionStrengthNominal}), 'Location','best');
title(['Q6 capacity weakening: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(3,1,2);
plot(C.time, C.capacityQ6ProjectionFactor, 'LineWidth', 1.2);
ylabel('capacity factor'); grid on;
local_tiled_or_subplot(3,1,3);
semilogy(C.time, abs(C.q6DivBeforeRms), 'LineWidth', 1.0); hold on;
semilogy(C.time, abs(C.q6DivAfterProjectedFluxRms), 'LineWidth', 1.2);
xlabel('time'); ylabel('div RMS'); grid on;
legend(local_existing_labels({'before','after'}, {C.q6DivBeforeRms,C.q6DivAfterProjectedFluxRms}), 'Location','best');
local_save_fig(fig, base + "_q6_divergence", opts);

% Figure 3: Virial response
fig = figure('Name', ['closed capacity virial - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(3,1,1);
plot(C.time, C.capacityVirialKEffective, 'LineWidth', 1.2);
ylabel('K_{vir,eff}'); grid on;
title(['Virial response: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(3,1,2);
plot(C.time, C.capacityVirialPressureMean, 'LineWidth', 1.2); hold on;
plot(C.time, C.capacityVirialPressureRms, '--', 'LineWidth', 1.0);
plot(C.time, C.capacityVirialPressureMax, ':', 'LineWidth', 1.0);
ylabel('P_{vir}'); grid on;
legend(local_existing_labels({'mean','rms','max'}, {C.capacityVirialPressureMean,C.capacityVirialPressureRms,C.capacityVirialPressureMax}), 'Location','best');
local_tiled_or_subplot(3,1,3);
plot(C.time, C.capacityVirialKickVelocityRms, 'LineWidth', 1.2); hold on;
plot(C.time, C.capacityVirialKickVelocityMax, '--', 'LineWidth', 1.0);
xlabel('time'); ylabel('|du| virial'); grid on;
legend(local_existing_labels({'rms','max'}, {C.capacityVirialKickVelocityRms,C.capacityVirialKickVelocityMax}), 'Location','best');
local_save_fig(fig, base + "_virial", opts);

% Figure 4: wall loads implied by Pkin + Pvir on solid boundary portions
fig = figure('Name', ['closed capacity wall load - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(4,1,1);
plot(C.time, C.capacityWallPressureKineticMeanAll, 'LineWidth', 1.0); hold on;
plot(C.time, C.capacityWallPressureVirialMeanAll, 'LineWidth', 1.2);
plot(C.time, C.capacityWallPressureTotalMeanAll, '--', 'LineWidth', 1.2);
ylabel('mean wall p'); grid on;
legend(local_existing_labels({'kinetic','virial','total'}, {C.capacityWallPressureKineticMeanAll,C.capacityWallPressureVirialMeanAll,C.capacityWallPressureTotalMeanAll}), 'Location','best');
title(['Closed-capacity wall load: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(4,1,2);
plot(C.time, C.capacityWallPressureTotalMeanLeft, 'LineWidth', 1.0); hold on;
plot(C.time, C.capacityWallPressureTotalMeanRight, 'LineWidth', 1.0);
plot(C.time, C.capacityWallPressureTotalMeanBottom, 'LineWidth', 1.0);
plot(C.time, C.capacityWallPressureTotalMeanTop, 'LineWidth', 1.0);
ylabel('total p by side'); grid on;
legend(local_existing_labels({'left','right','bottom','top'}, {C.capacityWallPressureTotalMeanLeft,C.capacityWallPressureTotalMeanRight,C.capacityWallPressureTotalMeanBottom,C.capacityWallPressureTotalMeanTop}), 'Location','best');
local_tiled_or_subplot(4,1,3);
plot(C.time, C.capacityWallPressureVirialMeanLeft, 'LineWidth', 1.0); hold on;
plot(C.time, C.capacityWallPressureVirialMeanRight, 'LineWidth', 1.0);
plot(C.time, C.capacityWallPressureVirialMeanBottom, 'LineWidth', 1.0);
plot(C.time, C.capacityWallPressureVirialMeanTop, 'LineWidth', 1.0);
ylabel('virial p by side'); grid on;
legend(local_existing_labels({'left','right','bottom','top'}, {C.capacityWallPressureVirialMeanLeft,C.capacityWallPressureVirialMeanRight,C.capacityWallPressureVirialMeanBottom,C.capacityWallPressureVirialMeanTop}), 'Location','best');
local_tiled_or_subplot(4,1,4);
plot(C.time, C.capacityWallForceTotalX, 'LineWidth', 1.1); hold on;
plot(C.time, C.capacityWallForceTotalY, 'LineWidth', 1.1);
plot(C.time, C.capacityWallForceTotalMag, '--', 'LineWidth', 1.0);
xlabel('time'); ylabel('wall force'); grid on;
legend(local_existing_labels({'Fx','Fy','|F|'}, {C.capacityWallForceTotalX,C.capacityWallForceTotalY,C.capacityWallForceTotalMag}), 'Location','best');
local_save_fig(fig, base + "_wall_load", opts);

% Figure 5: Resampling activity
fig = figure('Name', ['closed capacity resampling - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(4,1,1);
plot(C.time, C.resampRemapMassCorrectionStrength, 'LineWidth', 1.2);
ylabel('remap factor'); grid on;
title(['Resampling under capacity response: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(4,1,2);
plot(C.time, C.resampPopulationGuardWetNMinAfter, 'LineWidth', 1.0); hold on;
plot(C.time, C.resampPopulationGuardWetNMeanAfter, 'LineWidth', 1.2);
plot(C.time, C.resampPopulationGuardWetNMaxAfter, 'LineWidth', 1.0);
ylabel('N wet'); grid on;
legend(local_existing_labels({'min','mean','max'}, {C.resampPopulationGuardWetNMinAfter,C.resampPopulationGuardWetNMeanAfter,C.resampPopulationGuardWetNMaxAfter}), 'Location','best');
local_tiled_or_subplot(4,1,3);
plot(C.time, C.resampPopulationGuardUnderfullCells, 'LineWidth', 1.0); hold on;
plot(C.time, C.resampPopulationGuardOverfullCells, 'LineWidth', 1.0);
plot(C.time, C.resampEmptyWetCells, 'LineWidth', 1.2);
ylabel('cells'); grid on;
legend(local_existing_labels({'underfull','overfull','empty wet'}, {C.resampPopulationGuardUnderfullCells,C.resampPopulationGuardOverfullCells,C.resampEmptyWetCells}), 'Location','best');
local_tiled_or_subplot(4,1,4);
plot(C.time, C.resampParticleMassMin, 'LineWidth', 1.0); hold on;
plot(C.time, C.resampParticleMassMax, 'LineWidth', 1.0);
plot(C.time, C.resampMassGuardParticleMassMinAfter, '--', 'LineWidth', 1.0);
plot(C.time, C.resampMassGuardParticleMassMaxAfter, '--', 'LineWidth', 1.0);
xlabel('time'); ylabel('particle mass'); grid on;
legend(local_existing_labels({'min raw','max raw','min after','max after'}, {C.resampParticleMassMin,C.resampParticleMassMax,C.resampMassGuardParticleMassMinAfter,C.resampMassGuardParticleMassMaxAfter}), 'Location','best');
local_save_fig(fig, base + "_resampling", opts);

% Figure 5: Inlet and energy
fig = figure('Name', ['closed capacity inlet energy - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(4,1,1);
plot(C.time, C.inletParticlesInserted, 'LineWidth', 1.0); hold on;
plot(C.time, C.inletReservoirDeleted, 'LineWidth', 1.0);
plot(C.time, C.inletNetParticleDelta, 'LineWidth', 1.2);
ylabel('particles/step'); grid on;
legend(local_existing_labels({'inserted','reservoir deleted','net delta'}, {C.inletParticlesInserted,C.inletReservoirDeleted,C.inletNetParticleDelta}), 'Location','best');
title(['Inlet and energy: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(4,1,2);
plot(C.time, C.meanKinetic, 'LineWidth', 1.2); hold on;
plot(C.time, C.kBTEstimate, 'LineWidth', 1.0);
plot(C.time, C.thermostatKBTAfter, '--', 'LineWidth', 1.0);
ylabel('energy / kBT'); grid on;
legend(local_existing_labels({'mean kinetic','kBT estimate','thermostat after'}, {C.meanKinetic,C.kBTEstimate,C.thermostatKBTAfter}), 'Location','best');
local_tiled_or_subplot(4,1,3);
plot(C.time, C.meanVx, 'LineWidth', 1.2); hold on;
plot(C.time, C.meanVy, 'LineWidth', 1.2);
ylabel('mean velocity'); grid on;
legend(local_existing_labels({'mean Vx','mean Vy'}, {C.meanVx,C.meanVy}), 'Location','best');
local_tiled_or_subplot(4,1,4);
plot(C.time, C.Px, 'LineWidth', 1.2); hold on;
plot(C.time, C.Py, 'LineWidth', 1.2);
xlabel('time'); ylabel('momentum'); grid on;
legend(local_existing_labels({'Px','Py'}, {C.Px,C.Py}), 'Location','best');
local_save_fig(fig, base + "_inlet_energy", opts);

% Figure 6: momentum budget and available impulse diagnostics
fig = figure('Name', ['closed capacity momentum - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(5,1,1);
plot(C.time, C.Px, 'LineWidth', 1.2); hold on;
plot(C.time, C.Py, 'LineWidth', 1.2);
plot(C.time, C.Pmag, '--', 'LineWidth', 1.0);
ylabel('P'); grid on;
legend(local_existing_labels({'Px','Py','|P|'}, {C.Px,C.Py,C.Pmag}), 'Location','best');
title(['Momentum diagnostics: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(5,1,2);
plot(C.time, C.dPxStep, 'LineWidth', 1.1); hold on;
plot(C.time, C.dPyStep, 'LineWidth', 1.1);
ylabel('\Delta P/step'); grid on;
legend(local_existing_labels({'Delta Px','Delta Py'}, {C.dPxStep,C.dPyStep}), 'Location','best');
local_tiled_or_subplot(5,1,3);
local_plot_available(C.time, {C.inletMomentumDeltaX, C.wallMomentumDeltaX, C.q6MomentumDeltaX, C.virialMomentumDeltaX, C.thermostatMomentumDeltaX, C.resampMomentumDeltaX}, ...
    {'inlet','wall','q6','virial','thermostat','resampling'});
ylabel('budget X'); grid on;
local_tiled_or_subplot(5,1,4);
local_plot_available(C.time, {C.inletMomentumDeltaY, C.wallMomentumDeltaY, C.q6MomentumDeltaY, C.virialMomentumDeltaY, C.thermostatMomentumDeltaY, C.resampMomentumDeltaY}, ...
    {'inlet','wall','q6','virial','thermostat','resampling'});
ylabel('budget Y'); grid on;
local_tiled_or_subplot(5,1,5);
plot(C.time, C.momentumBudgetResidualX, 'LineWidth', 1.1); hold on;
plot(C.time, C.momentumBudgetResidualY, 'LineWidth', 1.1);
xlabel('time'); ylabel('residual'); grid on;
legend(local_existing_labels({'residual X','residual Y'}, {C.momentumBudgetResidualX,C.momentumBudgetResidualY}), 'Location','best');
local_save_fig(fig, base + "_momentum_budget", opts);

% Figure 7: detailed resampling momentum terms
fig = figure('Name', ['closed capacity resampling momentum - ' C.label], 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(3,1,1);
local_plot_available(C.time, {C.resampExtractionMomentumDeltaX, C.resampInsertionMomentumDeltaX, C.resampRemapMomentumDeltaX, C.resampLatentActivationMomentumDeltaX}, ...
    {'extraction','insertion','remap','latent'});
ylabel('Delta Px'); grid on;
title(['Resampling momentum terms: ' C.label], 'Interpreter','none');
local_tiled_or_subplot(3,1,2);
local_plot_available(C.time, {C.resampExtractionMomentumDeltaY, C.resampInsertionMomentumDeltaY, C.resampRemapMomentumDeltaY, C.resampLatentActivationMomentumDeltaY}, ...
    {'extraction','insertion','remap','latent'});
ylabel('Delta Py'); grid on;
local_tiled_or_subplot(3,1,3);
plot(C.time, C.resampMomentumDeltaX, 'LineWidth', 1.2); hold on;
plot(C.time, C.resampMomentumDeltaY, 'LineWidth', 1.2);
xlabel('time'); ylabel('resamp sum'); grid on;
legend(local_existing_labels({'sum X','sum Y'}, {C.resampMomentumDeltaX,C.resampMomentumDeltaY}), 'Location','best');
local_save_fig(fig, base + "_resampling_momentum", opts);
end

% -------------------------------------------------------------------------
function local_make_comparison_figures(cases, opts)
if numel(cases) < 2
    return;
end
vis = local_visible(opts.showFigures);
fig = figure('Name', 'closed capacity comparison', 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(3,1,1);
hold on; grid on;
for k = 1:numel(cases)
    plot(cases(k).time, 100*cases(k).capacityOverfillRatio, 'LineWidth', 1.1);
end
ylabel('overfill [%]'); title('Closed-capacity comparison');
legend({cases.label}, 'Interpreter','none', 'Location','best');
local_tiled_or_subplot(3,1,2);
hold on; grid on;
for k = 1:numel(cases)
    plot(cases(k).time, cases(k).q6ProjectionStrengthEffective, 'LineWidth', 1.1);
end
ylabel('Q6 strength eff.');
local_tiled_or_subplot(3,1,3);
hold on; grid on;
for k = 1:numel(cases)
    plot(cases(k).time, cases(k).capacityVirialPressureMean, 'LineWidth', 1.1);
end
xlabel('time'); ylabel('P_{vir,mean}');
local_save_fig(fig, fullfile(opts.outputDir, 'comparison_closed_capacity_0147'), opts);

fig = figure('Name', 'closed capacity momentum comparison', 'Color', 'w', 'Visible', vis);
local_tiled_or_subplot(2,1,1);
hold on; grid on;
for k = 1:numel(cases)
    plot(cases(k).time, cases(k).Pmag, 'LineWidth', 1.1);
end
ylabel('|P|'); title('Closed-capacity momentum comparison');
legend({cases.label}, 'Interpreter','none', 'Location','best');
local_tiled_or_subplot(2,1,2);
hold on; grid on;
for k = 1:numel(cases)
    plot(cases(k).time, cases(k).dPmagStep, 'LineWidth', 1.1);
end
xlabel('time'); ylabel('|Delta P|/step');
local_save_fig(fig, fullfile(opts.outputDir, 'comparison_momentum_0147'), opts);
end

% -------------------------------------------------------------------------
function dt = local_step_dt(time)
time = time(:);
dt = [NaN; diff(time)];
finiteDt = dt(isfinite(dt) & dt > 0);
if isempty(finiteDt)
    dt(:) = NaN;
else
    dt(~isfinite(dt) | dt <= 0) = median(finiteDt);
end
end

% -------------------------------------------------------------------------
function y = local_sum_available(n, arrays)
y = zeros(n,1);
anyAvailable = false;
for i = 1:numel(arrays)
    a = arrays{i};
    if isempty(a) || all(isnan(a))
        continue;
    end
    if numel(a) ~= n
        continue;
    end
    a = a(:);
    a(isnan(a)) = 0;
    y = y + a;
    anyAvailable = true;
end
if ~anyAvailable
    y = NaN(n,1);
end
end

% -------------------------------------------------------------------------
function local_plot_available(time, arrays, labels)
hold on;
plotted = false;
usedLabels = {};
for i = 1:numel(arrays)
    a = arrays{i};
    if isempty(a) || all(isnan(a))
        continue;
    end
    plot(time, a, 'LineWidth', 1.0);
    usedLabels{end+1} = labels{i}; %#ok<AGROW>
    plotted = true;
end
if plotted
    legend(usedLabels, 'Location','best');
else
    plot(time, NaN(size(time)), 'LineWidth', 1.0);
    legend({'no available budget terms'}, 'Location','best');
end
end

% -------------------------------------------------------------------------
function local_tiled_or_subplot(m,n,k)
% Use subplot for broad MATLAB compatibility.
subplot(m,n,k);
end

% -------------------------------------------------------------------------
function labels = local_existing_labels(labelsIn, arrays)
keep = false(size(labelsIn));
for i = 1:numel(arrays)
    a = arrays{i};
    keep(i) = ~isempty(a) && ~all(isnan(a));
end
labels = labelsIn(keep);
if isempty(labels)
    labels = {'no available column'};
end
end

% -------------------------------------------------------------------------
function local_save_fig(fig, basePath, opts)
if ~opts.saveFigures
    return;
end
basePath = char(basePath);
try
    savefig(fig, [basePath '.fig']);
catch
    warning('Could not save FIG: %s.fig', basePath);
end
try
    exportgraphics(fig, [basePath '.png'], 'Resolution', 180);
catch
    try
        saveas(fig, [basePath '.png']);
    catch
        warning('Could not save PNG: %s.png', basePath);
    end
end
end

% -------------------------------------------------------------------------
function vis = local_visible(showFigures)
if showFigures
    vis = 'on';
else
    vis = 'off';
end
end

% -------------------------------------------------------------------------
function y = local_last(x)
x = x(:);
idx = find(~isnan(x), 1, 'last');
if isempty(idx)
    y = NaN;
else
    y = x(idx);
end
end

% -------------------------------------------------------------------------
function y = local_nanmax(x)
x = x(:);
x = x(~isnan(x));
if isempty(x)
    y = NaN;
else
    y = max(x);
end
end
