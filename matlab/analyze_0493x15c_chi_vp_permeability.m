function result = analyze_0493x15c_chi_vp_permeability(runRoot)
% 0493x15c fixed-chi Brinkman + chiVP force/permeability analyzer.
% Run from repository matlab/ directory; reads ../runs/*.
%
% Force identity under test:
%   Delta P = I_body + I_Brinkman + I_chiVP
%
% Permeability diagnostic:
%   counts exact particle-mass crossings of the mid-plane of the full-height
%   vertical chi slab during periodic streaming.  Signed crossings measure net
%   through-flow; gross crossings retain thermal/back-and-forth traffic.
%
% No viscosity is assumed here.  The reported mobility U_perm/a_x can later be
% converted to an effective Darcy permeability K = nu * U_perm/a_x once the
% constitutive viscosity nu of this exact path is supplied independently.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x15c_chi_vp_permeability','fresh');
end
outDir = fullfile(runRoot,'output');
darcyPath = fullfile(outDir,'chi_solid_impulse_0493x15a.csv');
vpPath = fullfile(outDir,'chi_vp_impulse_0493x15b.csv');
permPath = fullfile(outDir,'chi_permeability_0493x15c.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(darcyPath), 'Missing %s', darcyPath);
assert(isfile(vpPath), 'Missing %s', vpPath);
assert(isfile(permPath), 'Missing %s', permPath);
assert(isfile(sumPath), 'Missing %s', sumPath);
assert(isfile(paramPath), 'Missing %s', paramPath);

D = readtable(darcyPath, 'VariableNamingRule','preserve');
V = readtable(vpPath, 'VariableNamingRule','preserve');
P = readtable(permPath, 'VariableNamingRule','preserve');
S = readtable(sumPath, 'VariableNamingRule','preserve');
ax = readKvNumber(paramPath, 'bodyAccelerationX');
dt = readKvNumber(paramPath, 'dt');
Lx = readKvNumber(paramPath, 'Lx');

% ---------- exact force budget ----------
[stepDV, id, iv] = intersect(D.step, V.step, 'stable');
[steps, idv, is] = intersect(stepDV, S.step, 'stable');
id = id(idv); iv = iv(idv);
keep = steps > 0;
steps = steps(keep); id = id(keep); iv = iv(keep); is = is(keep);
assert(~isempty(steps), 'No common nonzero steps in Darcy, chiVP and summary files');

prevIndex = zeros(size(is));
valid = false(size(is));
for k = 1:numel(is)
    j = find(S.step == steps(k)-1, 1, 'first');
    if ~isempty(j)
        prevIndex(k) = j;
        valid(k) = true;
    end
end
steps = steps(valid); id = id(valid); iv = iv(valid); is = is(valid); prevIndex = prevIndex(valid);
assert(~isempty(steps), 'No consecutive summary rows available');

dPx = S.Px(is) - S.Px(prevIndex);
dPy = S.Py(is) - S.Py(prevIndex);
mass = D.mass(id);
bodyIx = mass .* ax .* dt;
darcyIx = D.fluidImpulseX(id);
darcyIy = D.fluidImpulseY(id);
vpIx = V.fluidImpulseX(iv);
vpIy = V.fluidImpulseY(iv);
predIx = bodyIx + darcyIx + vpIx;
predIy = darcyIy + vpIy;
resX = dPx - predIx;
resY = dPy - predIy;
scaleX = max(abs(bodyIx) + abs(darcyIx) + abs(vpIx), 1e-30);
scaleY = max(abs(bodyIx) + abs(darcyIy) + abs(vpIy), 1e-30);
relX = abs(resX) ./ scaleX;
relY = abs(resY) ./ scaleY;

n = numel(steps);
steady0 = max(1, floor(0.6*n));
ss = steady0:n;
bodyFx = mass .* ax;
darcyReactionFx = -darcyIx ./ dt;
darcyReactionFy = -darcyIy ./ dt;
vpReactionFx = -vpIx ./ dt;
vpReactionFy = -vpIy ./ dt;
totalReactionFx = darcyReactionFx + vpReactionFx;
totalReactionFy = darcyReactionFy + vpReactionFy;
forceRatio = mean(totalReactionFx(ss)) / mean(bodyFx(ss));
transverseRatio = abs(mean(totalReactionFy(ss))) / max(abs(mean(bodyFx(ss))),1e-30);

rmsResidualX = sqrt(mean(resX.^2));
rmsRelativeX = sqrt(mean(relX.^2));
maxRelativeX = max(relX);
rmsResidualY = sqrt(mean(resY.^2));
rmsRelativeY = sqrt(mean(relY.^2));
maxRelativeY = max(relY);
geometryVersions = unique(D.geometryVersion(id));
passClosure = maxRelativeX < 1e-8 && rmsRelativeX < 1e-9 && ...
              maxRelativeY < 1e-8 && rmsRelativeY < 1e-9;

% ---------- exact mid-slab crossing / permeability ----------
assert(all(P.grossCrossingMass >= -1e-14), 'Negative gross crossing mass in %s', permPath);
assert(all(P.leftToRightMass >= -1e-14) && all(P.rightToLeftMass >= -1e-14), ...
       'Negative directional crossing mass in %s', permPath);
permGeom = unique(P.geometryVersion);
permPlane = unique(P.xPlane);
permWidth = unique(P.slabWidth);
assert(numel(permPlane) == 1 && numel(permWidth) == 1, ...
       'x15c expects one fixed slab plane/width; got multiple values');

steadyStartStep = steps(steady0);
ps = P.step >= steadyStartStep;
assert(any(ps), 'No permeability samples in steady window');

steadyNetMassFlux = mean(P.netMassFlux(ps));
steadyGrossMassFlux = mean(P.grossMassFlux(ps));
steadyLrMassFlux = mean(P.leftToRightMass(ps)) / dt;
steadyRlMassFlux = mean(P.rightToLeftMass(ps)) / dt;
meanMassSteady = mean(mass(ss));
% For a 2-D periodic domain rho_bar = M/(Lx*Ly), hence a mass flux through a
% full-height section corresponds to U_perm = mdot/(rho_bar*Ly) = mdot*Lx/M.
steadyPermeationVelocity = steadyNetMassFlux * Lx / max(meanMassSteady,1e-30);
steadyGrossCrossingSpeed = steadyGrossMassFlux * Lx / max(meanMassSteady,1e-30);
permeabilityMobility = steadyPermeationVelocity / max(abs(ax),1e-30);

cumulativeNetMass = sum(P.netCrossingMass);
cumulativeGrossMass = sum(P.grossCrossingMass);
cumulativeNetMassFraction = cumulativeNetMass / max(meanMassSteady,1e-30);
cumulativeGrossMassFraction = cumulativeGrossMass / max(meanMassSteady,1e-30);
steadyDirectionalBias = steadyNetMassFlux / max(steadyGrossMassFlux,1e-30);

meanBulkUx = mean(S.Px(is(ss)) ./ mass(ss));
throughflowOverBulkUx = steadyPermeationVelocity / max(abs(meanBulkUx),1e-30);

% Existing volumetric leakage metric for comparison with the exact crossing flux.
meanSolidLeakRms = NaN;
darcyCostPath = fullfile(outDir,'darcy_cost_0343.csv');
if isfile(darcyCostPath)
    C = readtable(darcyCostPath, 'VariableNamingRule','preserve');
    cs = C.step >= steadyStartStep;
    if any(cs) && ismember('solidLeakRms', C.Properties.VariableNames)
        meanSolidLeakRms = mean(C.solidLeakRms(cs));
    end
end

status = "PASS";
if ~passClosure
    status = "REVIEW";
end

analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

A = table(steps, dPx, bodyIx, darcyIx, vpIx, predIx, resX, relX, ...
    dPy, darcyIy, vpIy, predIy, resY, relY, ...
    darcyReactionFx, vpReactionFx, totalReactionFx, ...
    darcyReactionFy, vpReactionFy, totalReactionFy, ...
    'VariableNames', {'step','deltaPx','bodyImpulseX','darcyFluidImpulseX','chiVpFluidImpulseX', ...
    'predictedDeltaPx','residualX','relativeResidualX','deltaPy','darcyFluidImpulseY', ...
    'chiVpFluidImpulseY','predictedDeltaPy','residualY','relativeResidualY', ...
    'darcyReactionForceX','chiVpReactionForceX','totalReactionForceX', ...
    'darcyReactionForceY','chiVpReactionForceY','totalReactionForceY'});
writetable(A, fullfile(analysisDir,'force_budget_steps_0493x15c.csv'));
writetable(P, fullfile(analysisDir,'permeability_steps_0493x15c.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x15c.txt'),'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'0493x15c fixed chi + chiVP permeability\n');
fprintf(fid,'status=%s\n', status);
fprintf(fid,'steps=%d\n', n);
fprintf(fid,'geometryVersions=%s\n', mat2str(geometryVersions'));
fprintf(fid,'permeabilityGeometryVersions=%s\n', mat2str(permGeom'));
fprintf(fid,'slabPlaneX=%.17g\n', permPlane);
fprintf(fid,'slabWidth=%.17g\n', permWidth);
fprintf(fid,'rmsResidualX=%.17g\n', rmsResidualX);
fprintf(fid,'rmsRelativeX=%.17g\n', rmsRelativeX);
fprintf(fid,'maxRelativeX=%.17g\n', maxRelativeX);
fprintf(fid,'rmsResidualY=%.17g\n', rmsResidualY);
fprintf(fid,'rmsRelativeY=%.17g\n', rmsRelativeY);
fprintf(fid,'maxRelativeY=%.17g\n', maxRelativeY);
fprintf(fid,'steadyStartStep=%d\n', steadyStartStep);
fprintf(fid,'meanDarcyReactionForceX=%.17g\n', mean(darcyReactionFx(ss)));
fprintf(fid,'meanChiVpReactionForceX=%.17g\n', mean(vpReactionFx(ss)));
fprintf(fid,'meanTotalReactionForceX=%.17g\n', mean(totalReactionFx(ss)));
fprintf(fid,'meanBodyForceX=%.17g\n', mean(bodyFx(ss)));
fprintf(fid,'steadyReactionOverBody=%.17g\n', forceRatio);
fprintf(fid,'steadyTransverseOverBody=%.17g\n', transverseRatio);
fprintf(fid,'meanSolidLeakRms=%.17g\n', meanSolidLeakRms);
fprintf(fid,'steadyLeftToRightMassFlux=%.17g\n', steadyLrMassFlux);
fprintf(fid,'steadyRightToLeftMassFlux=%.17g\n', steadyRlMassFlux);
fprintf(fid,'steadyNetMassFlux=%.17g\n', steadyNetMassFlux);
fprintf(fid,'steadyGrossMassFlux=%.17g\n', steadyGrossMassFlux);
fprintf(fid,'steadyDirectionalBias=%.17g\n', steadyDirectionalBias);
fprintf(fid,'steadyPermeationVelocity=%.17g\n', steadyPermeationVelocity);
fprintf(fid,'steadyGrossCrossingSpeed=%.17g\n', steadyGrossCrossingSpeed);
fprintf(fid,'permeabilityMobility_UoverAx=%.17g\n', permeabilityMobility);
fprintf(fid,'meanBulkUx=%.17g\n', meanBulkUx);
fprintf(fid,'throughflowOverBulkUx=%.17g\n', throughflowOverBulkUx);
fprintf(fid,'cumulativeNetCrossingMass=%.17g\n', cumulativeNetMass);
fprintf(fid,'cumulativeGrossCrossingMass=%.17g\n', cumulativeGrossMass);
fprintf(fid,'cumulativeNetCrossingMassFraction=%.17g\n', cumulativeNetMassFraction);
fprintf(fid,'cumulativeGrossCrossingMassFraction=%.17g\n', cumulativeGrossMassFraction);

fprintf('\n===== 0493x15c CHI-VP PERMEABILITY =====\n');
fprintf('status                    = %s\n', status);
fprintf('steps analyzed            = %d\n', n);
fprintf('slab x / width            = %.9g / %.9g\n', permPlane, permWidth);
fprintf('RMS rel force residual X  = %.3e\n', rmsRelativeX);
fprintf('RMS rel force residual Y  = %.3e\n', rmsRelativeY);
fprintf('steady Ftotal/Fbody       = %.9f\n', forceRatio);
fprintf('steady net mass flux      = %.9g\n', steadyNetMassFlux);
fprintf('steady gross mass flux    = %.9g\n', steadyGrossMassFlux);
fprintf('directional bias net/gross= %.6g\n', steadyDirectionalBias);
fprintf('permeation velocity       = %.9g\n', steadyPermeationVelocity);
fprintf('mobility Uperm/|ax|       = %.9g\n', permeabilityMobility);
fprintf('mean bulk Ux              = %.9g\n', meanBulkUx);
fprintf('Uperm/|Ubulk|             = %.9g\n', throughflowOverBulkUx);
fprintf('cumulative gross M/Mfluid = %.9g\n', cumulativeGrossMassFraction);
fprintf('steady solidLeakRms       = %.9g\n', meanSolidLeakRms);
fprintf('analysis                  = %s\n', analysisDir);
fprintf('=========================================\n');

result = struct('status',status,'steps',n,'rmsRelativeX',rmsRelativeX, ...
    'rmsRelativeY',rmsRelativeY,'steadyReactionOverBody',forceRatio, ...
    'steadyNetMassFlux',steadyNetMassFlux,'steadyGrossMassFlux',steadyGrossMassFlux, ...
    'steadyPermeationVelocity',steadyPermeationVelocity, ...
    'permeabilityMobility',permeabilityMobility, ...
    'cumulativeGrossCrossingMassFraction',cumulativeGrossMassFraction, ...
    'meanSolidLeakRms',meanSolidLeakRms,'analysisDir',analysisDir);
end

function value = readKvNumber(path, key)
text = fileread(path);
expr = ['(?m)^\s*' regexptranslate('escape',key) '\s*=\s*([^#\r\n]+)'];
tok = regexp(text, expr, 'tokens', 'once');
assert(~isempty(tok), 'Missing key %s in %s', key, path);
value = str2double(strtrim(tok{1}));
assert(isfinite(value), 'Non-numeric key %s in %s', key, path);
end
