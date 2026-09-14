function result = analyze_0493x16c_fictitious_fluid_inventory(runRoot)
% 0493x16c fictitious-domain fluid inventory for dynamic chi solids.
% Run from repository matlab/; reads ../runs/*.
%
% This milestone is diagnostic only. It does NOT change the solid equation of
% motion and does NOT subtract fictitious-fluid inertia. It quantifies the
% numerical fluid retained in the solid fraction (1-chi), after the complete
% fluid-side chi coupling of each step.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x16c_fictitious_fluid_inventory','fresh');
end
outDir = fullfile(runRoot,'output');
dynPath = fullfile(outDir,'chi_solid_dynamics_0493x16a.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(dynPath), 'Missing %s', dynPath);
assert(isfile(sumPath), 'Missing %s', sumPath);
assert(isfile(paramPath), 'Missing %s', paramPath);

D = readtable(dynPath, 'VariableNamingRule','preserve');
S = readtable(sumPath, 'VariableNamingRule','preserve');
assert(~isempty(D) && ~isempty(S), 'Empty x16c input');

solidMass = readKvNumber(paramPath, 'chiSolidMass');
bodyAx = readKvNumber(paramPath, 'bodyAccelerationX');
solidModel = readKvString(paramPath, 'chiSolidModel');
initialDeactivate = readKvNumber(paramPath, 'darcyInitialDeactivateBelowChi');
forcingMode = readKvString(paramPath, 'darcyBrinkmanForcingMode');
assert(abs(bodyAx) < 1e-30, 'x16c qualification requires bodyAccelerationX=0');
assert(strcmp(solidModel,'rigid_slab_1d'), 'Expected rigid_slab_1d, got %s', solidModel);
assert(initialDeactivate < 0, 'Dynamic solid must keep fictitious-domain particles active');

required = {'spatialLoadAvailable0493x16b','cellReactionSumX0493x16b', ...
    'cellReactionSumY0493x16b','cellLoadClosureResidualX0493x16b', ...
    'cellLoadClosureResidualY0493x16b','primaryProjectionResidual0493x16b', ...
    'fictitiousFluidDiagnostic0493x16c','fictitiousFluidMass0493x16c', ...
    'fictitiousFluidMomentumX0493x16c','fictitiousFluidMomentumY0493x16c', ...
    'fictitiousLockedMomentumX0493x16c','fictitiousLockedMomentumY0493x16c', ...
    'fictitiousRelativeMomentumX0493x16c','fictitiousRelativeMomentumY0493x16c', ...
    'fictitiousRelativeVelocityRms0493x16c'};
for j = 1:numel(required)
    assert(ismember(required{j}, D.Properties.VariableNames), ...
        'Missing x16c column %s', required{j});
end

[steps, id, is] = intersect(D.step, S.step, 'stable');
keep = steps > 0;
steps = steps(keep); id = id(keep); is = is(keep);
assert(~isempty(steps), 'No common nonzero steps in x16c dynamics and runtime summary');

% --- x16a/x16b conservation regression, using global scales so near-zero
% instantaneous impulses do not create artificial relative-error spikes.
s0 = find(S.step == 0, 1, 'first');
Psolid0 = D.solidMomentumBeforeX(id(1));
Ptotal0 = S.Px(s0) + Psolid0;
Pfluid = S.Px(is);
Psolid = D.solidMomentumAfterX(id);
Ptotal = Pfluid + Psolid;
totalDrift = Ptotal - Ptotal0;
scaleTotal = max([abs(Ptotal0); abs(Pfluid); abs(Psolid); 1e-30]);
relTotalDrift = abs(totalDrift) / scaleTotal;

prevIndex = zeros(size(is));
valid = false(size(is));
for k = 1:numel(is)
    j = find(S.step == steps(k)-1, 1, 'first');
    if ~isempty(j)
        prevIndex(k) = j;
        valid(k) = true;
    end
end
idC = id(valid); isC = is(valid); prevC = prevIndex(valid);
dPxFluid = S.Px(isC) - S.Px(prevC);
fluidImpulse = D.totalFluidImpulseX(idC);
fluidClosureResidual = dPxFluid - fluidImpulse;
fluidScaleGlobal = max([abs(dPxFluid); abs(fluidImpulse); 1e-30]);
fluidClosureRelative = abs(fluidClosureResidual) / fluidScaleGlobal;

arResidual = D.actionReactionResidualX(id);
actionScaleGlobal = max([abs(D.totalFluidImpulseX(id)); abs(D.solidReactionImpulseX(id)); 1e-30]);
arRelative = abs(arResidual) / actionScaleGlobal;

spatialAvailable = all(D.spatialLoadAvailable0493x16b(id) ~= 0);
cellScaleXGlobal = max([abs(D.cellReactionSumX0493x16b(id)); abs(D.totalFluidImpulseX(id)); 1e-30]);
cellScaleYGlobal = max([abs(D.cellReactionSumY0493x16b(id)); abs(D.totalFluidImpulseY(id)); 1e-30]);
cellClosureRelX = abs(D.cellLoadClosureResidualX0493x16b(id)) / cellScaleXGlobal;
cellClosureRelY = abs(D.cellLoadClosureResidualY0493x16b(id)) / cellScaleYGlobal;
projectionScaleGlobal = max([abs(D.cellReactionSumX0493x16b(id)); abs(D.solidReactionImpulseX(id)); 1e-30]);
projectionRel = abs(D.primaryProjectionResidual0493x16b(id)) / projectionScaleGlobal;

maxRelTotalDrift = max(relTotalDrift);
rmsRelTotalDrift = sqrt(mean(relTotalDrift.^2));
maxRelFluidClosure = max(fluidClosureRelative);
rmsRelFluidClosure = sqrt(mean(fluidClosureRelative.^2));
maxRelActionReaction = max(arRelative);
rmsRelActionReaction = sqrt(mean(arRelative.^2));
maxRelCellClosureX = max(cellClosureRelX);
rmsRelCellClosureX = sqrt(mean(cellClosureRelX.^2));
maxRelCellClosureY = max(cellClosureRelY);
rmsRelCellClosureY = sqrt(mean(cellClosureRelY.^2));
maxRelProjection = max(projectionRel);
rmsRelProjection = sqrt(mean(projectionRel.^2));

% --- x16c fictitious-fluid inventory.
fictAvailable = all(D.fictitiousFluidDiagnostic0493x16c(id) ~= 0);
Mf = D.fictitiousFluidMass0493x16c(id);
PfX = D.fictitiousFluidMomentumX0493x16c(id);
PfY = D.fictitiousFluidMomentumY0493x16c(id);
PlockX = D.fictitiousLockedMomentumX0493x16c(id);
PlockY = D.fictitiousLockedMomentumY0493x16c(id);
PrelX = D.fictitiousRelativeMomentumX0493x16c(id);
PrelY = D.fictitiousRelativeMomentumY0493x16c(id);
UrelRms = D.fictitiousRelativeVelocityRms0493x16c(id);
assert(all(isfinite(Mf)) && all(Mf >= 0), 'Invalid x16c fictitious mass');
assert(all(isfinite(PfX)) && all(isfinite(PlockX)) && all(isfinite(UrelRms)), ...
    'Invalid x16c fictitious momentum diagnostic');

UfX = zeros(size(Mf)); UfY = zeros(size(Mf));
UlockX = zeros(size(Mf)); UlockY = zeros(size(Mf));
positive = Mf > 0;
UfX(positive) = PfX(positive) ./ Mf(positive);
UfY(positive) = PfY(positive) ./ Mf(positive);
UlockX(positive) = PlockX(positive) ./ Mf(positive);
UlockY(positive) = PlockY(positive) ./ Mf(positive);
bulkSlipX = UfX - UlockX;
bulkSlipY = UfY - UlockY;

meanMf = mean(Mf);
minMf = min(Mf); maxMf = max(Mf);
fictMassCV = std(Mf) / max(abs(meanMf),1e-30);
fictMassOverSolid = meanMf / max(abs(solidMass),1e-30);
candidatePhysicalMassIfExcess = solidMass + meanMf;
meanBulkSlipX = mean(bulkSlipX);
rmsBulkSlipX = sqrt(mean(bulkSlipX.^2));
maxAbsBulkSlipX = max(abs(bulkSlipX));
meanBulkSlipY = mean(bulkSlipY);
rmsBulkSlipY = sqrt(mean(bulkSlipY.^2));
maxAbsBulkSlipY = max(abs(bulkSlipY));
meanRelativeVelocityRms = mean(UrelRms);

% Bulk co-motion gain. This uses the actual locked-reference velocity field,
% not an assumed analytic slab velocity.
den = sum(UlockX.^2);
if den > 0
    bulkLockGainX = sum(UlockX .* UfX) / den;
else
    bulkLockGainX = NaN;
end

% Internal algebraic identity of the x16c diagnostic.
relMomClosureX = PfX - PlockX - PrelX;
relMomClosureY = PfY - PlockY - PrelY;
relMomScale = max([abs(PfX); abs(PlockX); abs(PrelX); 1e-30]);
maxRelativeFictitiousMomentumIdentity = max([abs(relMomClosureX); abs(relMomClosureY)]) / relMomScale;

versions = D.geometryVersion(id);
versionStrict = all(diff(versions) == 1);
massRelErr = max(abs(D.mass(id)-solidMass)) / max(abs(solidMass),1e-30);

% x16c PASS qualifies the diagnostic and preserves x16b mechanics. It does not
% impose a physical threshold on fictitious-fluid mass or slip; those are the
% quantities this milestone is intended to measure before choosing a correction.
pass = maxRelTotalDrift < 1e-9 && ...
       maxRelFluidClosure < 1e-9 && ...
       maxRelActionReaction < 1e-9 && ...
       spatialAvailable && fictAvailable && ...
       maxRelCellClosureX < 1e-9 && maxRelCellClosureY < 1e-9 && ...
       maxRelProjection < 1e-9 && ...
       maxRelativeFictitiousMomentumIdentity < 1e-12 && ...
       versionStrict && massRelErr < 1e-14;
status = "PASS";
if ~pass, status = "REVIEW"; end

analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

T = table(steps, S.time(is), D.geometryVersion(id), D.centerXAfter(id), ...
    D.velocityXBefore(id), D.velocityXAfter(id), Mf, PfX, PfY, PlockX, PlockY, ...
    PrelX, PrelY, UfX, UfY, UlockX, UlockY, bulkSlipX, bulkSlipY, UrelRms, ...
    Pfluid, Psolid, Ptotal, totalDrift, ...
    'VariableNames', {'step','time','geometryVersion','centerX','solidVelocityBeforeX','solidVelocityAfterX', ...
    'fictitiousMass','fictitiousMomentumX','fictitiousMomentumY','lockedMomentumX','lockedMomentumY', ...
    'relativeMomentumX','relativeMomentumY','fictitiousBulkVelocityX','fictitiousBulkVelocityY', ...
    'lockedReferenceVelocityX','lockedReferenceVelocityY','bulkSlipX','bulkSlipY','relativeVelocityRms', ...
    'fluidMomentumX','solidMomentumX','totalMomentumX','totalMomentumDriftX'});
writetable(T, fullfile(analysisDir,'fictitious_fluid_steps_0493x16c.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x16c.txt'),'w');
assert(fid >= 0, 'Cannot create x16c summary');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'0493x16c fictitious-domain fluid inventory / rigid slab 1D\n');
fprintf(fid,'status=%s\n',status);
fprintf(fid,'steps=%d\n',numel(steps));
fprintf(fid,'solidModel=%s\n',solidModel);
fprintf(fid,'solidModelMass=%.17g\n',solidMass);
fprintf(fid,'forcingMode=%s\n',forcingMode);
fprintf(fid,'initialDeactivateBelowChi=%.17g\n',initialDeactivate);
fprintf(fid,'fictitiousFluidDiagnosticAvailable=%d\n',fictAvailable);
fprintf(fid,'meanFictitiousFluidMass=%.17g\n',meanMf);
fprintf(fid,'minFictitiousFluidMass=%.17g\n',minMf);
fprintf(fid,'maxFictitiousFluidMass=%.17g\n',maxMf);
fprintf(fid,'fictitiousFluidMassCV=%.17g\n',fictMassCV);
fprintf(fid,'fictitiousFluidMassOverSolidModelMass=%.17g\n',fictMassOverSolid);
fprintf(fid,'candidatePhysicalMassIfSolidModelMassIsExcess=%.17g\n',candidatePhysicalMassIfExcess);
fprintf(fid,'meanFictitiousBulkSlipX=%.17g\n',meanBulkSlipX);
fprintf(fid,'rmsFictitiousBulkSlipX=%.17g\n',rmsBulkSlipX);
fprintf(fid,'maxAbsFictitiousBulkSlipX=%.17g\n',maxAbsBulkSlipX);
fprintf(fid,'meanFictitiousBulkSlipY=%.17g\n',meanBulkSlipY);
fprintf(fid,'rmsFictitiousBulkSlipY=%.17g\n',rmsBulkSlipY);
fprintf(fid,'maxAbsFictitiousBulkSlipY=%.17g\n',maxAbsBulkSlipY);
fprintf(fid,'bulkLockGainX=%.17g\n',bulkLockGainX);
fprintf(fid,'meanFictitiousRelativeVelocityRms=%.17g\n',meanRelativeVelocityRms);
fprintf(fid,'maxRelativeFictitiousMomentumIdentity=%.17g\n',maxRelativeFictitiousMomentumIdentity);
fprintf(fid,'maxRelativeTotalMomentumDriftX=%.17g\n',maxRelTotalDrift);
fprintf(fid,'maxRelativeFluidImpulseClosureX=%.17g\n',maxRelFluidClosure);
fprintf(fid,'maxRelativeActionReactionX=%.17g\n',maxRelActionReaction);
fprintf(fid,'maxRelativeCellLoadClosureX=%.17g\n',maxRelCellClosureX);
fprintf(fid,'maxRelativeCellLoadClosureY=%.17g\n',maxRelCellClosureY);
fprintf(fid,'maxRelativePrimaryProjection=%.17g\n',maxRelProjection);
fprintf(fid,'solidMassRelativeError=%.17g\n',massRelErr);

fprintf('\n===== 0493x16c FICTITIOUS-DOMAIN FLUID INVENTORY =====\n');
fprintf('status                              = %s\n',status);
fprintf('solid model mass                    = %.9g\n',solidMass);
fprintf('mean fictitious-fluid mass          = %.9g\n',meanMf);
fprintf('fictitious / solid-model mass       = %.6f\n',fictMassOverSolid);
fprintf('fictitious mass CV                  = %.3e\n',fictMassCV);
fprintf('candidate physical mass (excess convention) = %.9g\n',candidatePhysicalMassIfExcess);
fprintf('bulk lock gain x                    = %.9g\n',bulkLockGainX);
fprintf('RMS / max |bulk slip x|             = %.3e / %.3e\n',rmsBulkSlipX,maxAbsBulkSlipX);
fprintf('mean particle-relative velocity RMS = %.6g\n',meanRelativeVelocityRms);
fprintf('max rel total momentum drift        = %.3e\n',maxRelTotalDrift);
fprintf('max rel action-reaction residual    = %.3e\n',maxRelActionReaction);
fprintf('analysis                            = %s\n',analysisDir);
fprintf('=========================================================\n');

figure;
plot(S.time(is), Mf, '-');
xlabel('time'); ylabel('M_{fict}'); title('0493x16c fictitious-fluid mass'); grid on;

figure;
plot(S.time(is), UlockX, '-', S.time(is), UfX, '-');
xlabel('time'); ylabel('velocity x');
legend('solid reference','fictitious-fluid bulk','Location','best');
title('0493x16c fictitious-fluid bulk locking'); grid on;

figure;
plot(S.time(is), bulkSlipX, '-');
xlabel('time'); ylabel('U_{fict}-U_s'); title('0493x16c fictitious-fluid bulk slip'); grid on;

result = struct('status',status,'steps',numel(steps), ...
    'meanFictitiousFluidMass',meanMf, ...
    'fictitiousFluidMassOverSolidModelMass',fictMassOverSolid, ...
    'candidatePhysicalMassIfSolidModelMassIsExcess',candidatePhysicalMassIfExcess, ...
    'bulkLockGainX',bulkLockGainX, ...
    'rmsFictitiousBulkSlipX',rmsBulkSlipX, ...
    'maxAbsFictitiousBulkSlipX',maxAbsBulkSlipX, ...
    'meanFictitiousRelativeVelocityRms',meanRelativeVelocityRms, ...
    'maxRelativeTotalMomentumDriftX',maxRelTotalDrift, ...
    'maxRelativeActionReactionX',maxRelActionReaction, ...
    'analysisDir',analysisDir);
end

function value = readKvNumber(path, key)
text = fileread(path);
expr = ['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok = regexp(text, expr, 'tokens', 'once');
assert(~isempty(tok), 'Missing key %s in %s', key, path);
value = str2double(strtrim(tok{1}));
assert(isfinite(value), 'Non-numeric key %s in %s', key, path);
end

function value = readKvString(path, key)
text = fileread(path);
expr = ['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok = regexp(text, expr, 'tokens', 'once');
assert(~isempty(tok), 'Missing key %s in %s', key, path);
value = strtrim(tok{1});
end
