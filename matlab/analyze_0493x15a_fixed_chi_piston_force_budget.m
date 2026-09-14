function result = analyze_0493x15a_fixed_chi_piston_force_budget(runRoot)
% 0493x15a fixed-chi piston / Brinkman slab force-budget analyzer.
% Run from repository matlab/ directory.  By default reads ../runs/*.
%
% Checks the exact full-step momentum identity for the deliberately minimal
% x15a baseline:
%   Delta Px = M ax dt + I_chi,fluid
% where I_chi,fluid is the exact finite-dt deterministic Darcy impulse written
% by chi_solid_impulse_0493x15a.csv.  Collision and cell-relative thermostat
% should be globally momentum-conserving in this configuration.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x15a_fixed_chi_piston_force_budget','fresh');
end
outDir = fullfile(runRoot,'output');
impPath = fullfile(outDir,'chi_solid_impulse_0493x15a.csv');
sumPath = fullfile(outDir,'summary_runtime.csv');
paramPath = fullfile(outDir,'params_used.kv');
assert(isfile(impPath), 'Missing %s', impPath);
assert(isfile(sumPath), 'Missing %s', sumPath);
assert(isfile(paramPath), 'Missing %s', paramPath);

I = readtable(impPath, 'VariableNamingRule','preserve');
S = readtable(sumPath, 'VariableNamingRule','preserve');
ax = readKvNumber(paramPath, 'bodyAccelerationX');
dt = readKvNumber(paramPath, 'dt');

stepI = I.step;
stepS = S.step;
[steps, ia, ib] = intersect(stepI, stepS, 'stable');
keep = steps > 0;
steps = steps(keep); ia = ia(keep); ib = ib(keep);
assert(~isempty(steps), 'No common nonzero steps in impulse and summary files');

% Previous summary row is required for exact Delta P over each step.
prevIndex = zeros(size(ib));
valid = false(size(ib));
for k = 1:numel(ib)
    j = find(stepS == steps(k)-1, 1, 'first');
    if ~isempty(j)
        prevIndex(k) = j;
        valid(k) = true;
    end
end
steps = steps(valid); ia = ia(valid); ib = ib(valid); prevIndex = prevIndex(valid);
assert(~isempty(steps), 'No consecutive summary rows available');

dPx = S.Px(ib) - S.Px(prevIndex);
dPy = S.Py(ib) - S.Py(prevIndex);
mass = I.mass(ia);
bodyIx = mass .* ax .* dt;
chiIx = I.fluidImpulseX(ia);
chiIy = I.fluidImpulseY(ia);
predIx = bodyIx + chiIx;
predIy = chiIy;
resX = dPx - predIx;
resY = dPy - predIy;
scaleX = max(abs(bodyIx) + abs(chiIx), 1e-30);
scaleY = max(abs(chiIy), 1e-30);
relX = abs(resX) ./ scaleX;
relY = abs(resY) ./ max(scaleY, max(abs(dPy),1e-30));

n = numel(steps);
steady0 = max(1, floor(0.6*n));
ss = steady0:n;
reactionFx = I.solidReactionForceX(ia);
reactionFy = I.solidReactionForceY(ia);
bodyFx = mass .* ax;
forceRatio = mean(reactionFx(ss)) / mean(bodyFx(ss));
transverseRatio = abs(mean(reactionFy(ss))) / max(abs(mean(bodyFx(ss))),1e-30);

rmsResidualX = sqrt(mean(resX.^2));
rmsRelativeX = sqrt(mean(relX.^2));
maxRelativeX = max(relX);
rmsRelativeY = sqrt(mean(relY.^2));
impulseComplete = all(I.impulseComplete(ia) == 1);
geometryVersions = unique(I.geometryVersion(ia));

% Strict closure is the primary PASS criterion; steady force ratio is reported
% separately because its convergence depends on chosen run duration/alpha.
passClosure = impulseComplete && maxRelativeX < 1e-8 && rmsRelativeX < 1e-9;
passTransverse = transverseRatio < 1e-8;
status = "PASS";
if ~(passClosure && passTransverse)
    status = "REVIEW";
end

A = table(steps, dPx, bodyIx, chiIx, predIx, resX, relX, dPy, chiIy, resY, relY, ...
    reactionFx, reactionFy, 'VariableNames', ...
    {'step','deltaPx','bodyImpulseX','chiFluidImpulseX','predictedDeltaPx','residualX','relativeResidualX', ...
     'deltaPy','chiFluidImpulseY','residualY','relativeResidualY','solidReactionForceX','solidReactionForceY'});
analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end
writetable(A, fullfile(analysisDir,'force_budget_steps_0493x15a.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x15a.txt'),'w');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'0493x15a fixed chi piston force budget\n');
fprintf(fid,'status=%s\n', status);
fprintf(fid,'steps=%d\n', n);
fprintf(fid,'geometryVersions=%s\n', mat2str(geometryVersions'));
fprintf(fid,'impulseComplete=%d\n', impulseComplete);
fprintf(fid,'rmsResidualX=%.17g\n', rmsResidualX);
fprintf(fid,'rmsRelativeX=%.17g\n', rmsRelativeX);
fprintf(fid,'maxRelativeX=%.17g\n', maxRelativeX);
fprintf(fid,'rmsRelativeY=%.17g\n', rmsRelativeY);
fprintf(fid,'steadyStartStep=%d\n', steps(steady0));
fprintf(fid,'meanReactionForceX=%.17g\n', mean(reactionFx(ss)));
fprintf(fid,'meanBodyForceX=%.17g\n', mean(bodyFx(ss)));
fprintf(fid,'steadyReactionOverBody=%.17g\n', forceRatio);
fprintf(fid,'steadyTransverseOverBody=%.17g\n', transverseRatio);

fprintf('\n===== 0493x15a FIXED CHI PISTON FORCE BUDGET =====\n');
fprintf('status                 = %s\n', status);
fprintf('steps analyzed         = %d\n', n);
fprintf('geometry version(s)    = %s\n', mat2str(geometryVersions'));
fprintf('impulse complete       = %d\n', impulseComplete);
fprintf('RMS rel residual X     = %.3e\n', rmsRelativeX);
fprintf('max rel residual X     = %.3e\n', maxRelativeX);
fprintf('RMS rel residual Y     = %.3e\n', rmsRelativeY);
fprintf('steady Freaction/Fbody = %.9f\n', forceRatio);
fprintf('steady |Fy|/Fbody      = %.3e\n', transverseRatio);
fprintf('analysis               = %s\n', analysisDir);
fprintf('===================================================\n');

result = struct('status',status,'steps',n,'rmsRelativeX',rmsRelativeX, ...
    'maxRelativeX',maxRelativeX,'rmsRelativeY',rmsRelativeY, ...
    'steadyReactionOverBody',forceRatio,'steadyTransverseOverBody',transverseRatio, ...
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
