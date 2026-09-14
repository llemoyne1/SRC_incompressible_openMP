function result = analyze_0493x15b_fixed_chi_vp_force_budget(runRoot)
% 0493x15b fixed-chi Brinkman slab + chiVP force-budget analyzer.
% Run from repository matlab/ directory; reads ../runs/* by default.
%
% Exact step identity under test:
%   Delta P = I_body + I_Brinkman + I_chiVP
% The Brinkman and chiVP exchanges are measured independently in their native
% operators.  The cell-relative thermostat should remain globally momentum
% conserving and therefore belongs in the residual, which should be roundoff.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x15b_fixed_chi_vp_force_budget','fresh');
end
outDir = fullfile(runRoot,'output');
darcyPath = fullfile(outDir,'chi_solid_impulse_0493x15a.csv');
vpPath = fullfile(outDir,'chi_vp_impulse_0493x15b.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(darcyPath), 'Missing %s', darcyPath);
assert(isfile(vpPath), 'Missing %s', vpPath);
assert(isfile(sumPath), 'Missing %s', sumPath);
assert(isfile(paramPath), 'Missing %s', paramPath);

D = readtable(darcyPath, 'VariableNamingRule','preserve');
V = readtable(vpPath, 'VariableNamingRule','preserve');
S = readtable(sumPath, 'VariableNamingRule','preserve');
ax = readKvNumber(paramPath, 'bodyAccelerationX');
dt = readKvNumber(paramPath, 'dt');

% Intersect all three diagnostics on the same absolute step.
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

% Primary qualification criterion: exact global momentum closure.  Finite-time
% transverse force and approach to steady force balance are reported but are
% not compared with roundoff thresholds because MPCD forces fluctuate.
passClosure = maxRelativeX < 1e-8 && rmsRelativeX < 1e-9 && ...
              maxRelativeY < 1e-8 && rmsRelativeY < 1e-9;
status = "PASS";
if ~passClosure
    status = "REVIEW";
end

% Existing Darcy metric: velocity leakage inside the penalized solid.  It is
% useful for comparison x15a -> x15b but is not yet a true crossing-flux test.
meanSolidLeakRms = NaN;
darcyCostPath = fullfile(outDir,'darcy_cost_0343.csv');
if isfile(darcyCostPath)
    C = readtable(darcyCostPath, 'VariableNamingRule','preserve');
    [~, ic, ~] = intersect(C.step, steps(ss), 'stable');
    if ~isempty(ic) && ismember('solidLeakRms', C.Properties.VariableNames)
        meanSolidLeakRms = mean(C.solidLeakRms(ic));
    end
end

A = table(steps, dPx, bodyIx, darcyIx, vpIx, predIx, resX, relX, ...
    dPy, darcyIy, vpIy, predIy, resY, relY, ...
    darcyReactionFx, vpReactionFx, totalReactionFx, ...
    darcyReactionFy, vpReactionFy, totalReactionFy, ...
    'VariableNames', {'step','deltaPx','bodyImpulseX','darcyFluidImpulseX','chiVpFluidImpulseX', ...
    'predictedDeltaPx','residualX','relativeResidualX','deltaPy','darcyFluidImpulseY', ...
    'chiVpFluidImpulseY','predictedDeltaPy','residualY','relativeResidualY', ...
    'darcyReactionForceX','chiVpReactionForceX','totalReactionForceX', ...
    'darcyReactionForceY','chiVpReactionForceY','totalReactionForceY'});
analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end
writetable(A, fullfile(analysisDir,'force_budget_steps_0493x15b.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x15b.txt'),'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'0493x15b fixed chi + chiVP force budget\n');
fprintf(fid,'status=%s\n', status);
fprintf(fid,'steps=%d\n', n);
fprintf(fid,'geometryVersions=%s\n', mat2str(geometryVersions'));
fprintf(fid,'rmsResidualX=%.17g\n', rmsResidualX);
fprintf(fid,'rmsRelativeX=%.17g\n', rmsRelativeX);
fprintf(fid,'maxRelativeX=%.17g\n', maxRelativeX);
fprintf(fid,'rmsResidualY=%.17g\n', rmsResidualY);
fprintf(fid,'rmsRelativeY=%.17g\n', rmsRelativeY);
fprintf(fid,'maxRelativeY=%.17g\n', maxRelativeY);
fprintf(fid,'steadyStartStep=%d\n', steps(steady0));
fprintf(fid,'meanDarcyReactionForceX=%.17g\n', mean(darcyReactionFx(ss)));
fprintf(fid,'meanChiVpReactionForceX=%.17g\n', mean(vpReactionFx(ss)));
fprintf(fid,'meanTotalReactionForceX=%.17g\n', mean(totalReactionFx(ss)));
fprintf(fid,'meanBodyForceX=%.17g\n', mean(bodyFx(ss)));
fprintf(fid,'steadyReactionOverBody=%.17g\n', forceRatio);
fprintf(fid,'steadyTransverseOverBody=%.17g\n', transverseRatio);
fprintf(fid,'meanSolidLeakRms=%.17g\n', meanSolidLeakRms);

fprintf('\n===== 0493x15b FIXED CHI + CHI-VP FORCE BUDGET =====\n');
fprintf('status                    = %s\n', status);
fprintf('steps analyzed            = %d\n', n);
fprintf('geometry version(s)       = %s\n', mat2str(geometryVersions'));
fprintf('RMS rel residual X        = %.3e\n', rmsRelativeX);
fprintf('max rel residual X        = %.3e\n', maxRelativeX);
fprintf('RMS rel residual Y        = %.3e\n', rmsRelativeY);
fprintf('max rel residual Y        = %.3e\n', maxRelativeY);
fprintf('mean Darcy reaction Fx    = %.9g\n', mean(darcyReactionFx(ss)));
fprintf('mean chiVP reaction Fx    = %.9g\n', mean(vpReactionFx(ss)));
fprintf('steady Ftotal/Fbody       = %.9f\n', forceRatio);
fprintf('steady |Fy|/Fbody         = %.3e\n', transverseRatio);
fprintf('steady solidLeakRms       = %.6g\n', meanSolidLeakRms);
fprintf('analysis                  = %s\n', analysisDir);
fprintf('========================================================\n');

result = struct('status',status,'steps',n,'rmsRelativeX',rmsRelativeX, ...
    'maxRelativeX',maxRelativeX,'rmsRelativeY',rmsRelativeY,'maxRelativeY',maxRelativeY, ...
    'steadyReactionOverBody',forceRatio,'steadyTransverseOverBody',transverseRatio, ...
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
