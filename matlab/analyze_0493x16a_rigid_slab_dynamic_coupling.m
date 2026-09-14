function result = analyze_0493x16a_rigid_slab_dynamic_coupling(runRoot)
% 0493x16a generic dynamic chi-solid coupling / RigidSlab1D qualification.
% Run from repository matlab/; reads ../runs/*.
%
% Primary invariant (no external/body force):
%   Pfluid(t) + Msolid*Us(t) = constant.
%
% The solid impulse is not reconstructed from a pressure proxy. It is exactly
% the opposite of the fluid impulses already measured in x15:
%   dPsolid = -(I_Brinkman + I_outwardBath + I_chiVP).

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x16a_rigid_slab_dynamic_coupling','fresh');
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
assert(~isempty(D), 'Empty x16a dynamic-solid diagnostic');
assert(any(S.step == 0), 'x16a requires runtime summary step 0');

bodyAx = readKvNumber(paramPath, 'bodyAccelerationX');
solidMass = readKvNumber(paramPath, 'chiSolidMass');
solidModel = readKvString(paramPath, 'chiSolidModel');
initialDeactivate = readKvNumber(paramPath, 'darcyInitialDeactivateBelowChi');
forcingMode = readKvString(paramPath, 'darcyBrinkmanForcingMode');
assert(abs(bodyAx) < 1e-30, 'x16a momentum qualification requires bodyAccelerationX=0');
assert(strcmp(solidModel,'rigid_slab_1d'), 'Expected rigid_slab_1d, got %s', solidModel);
assert(initialDeactivate < 0, 'Dynamic solid must keep fictitious-domain particles active');

[steps, id, is] = intersect(D.step, S.step, 'stable');
keep = steps > 0;
steps = steps(keep); id = id(keep); is = is(keep);
assert(~isempty(steps), 'No common nonzero steps in x16a dynamics and runtime summary');

s0 = find(S.step == 0, 1, 'first');
Psolid0 = D.solidMomentumBeforeX(id(1));
Ptotal0 = S.Px(s0) + Psolid0;
Pfluid = S.Px(is);
Psolid = D.solidMomentumAfterX(id);
Ptotal = Pfluid + Psolid;
totalDrift = Ptotal - Ptotal0;
scaleTotal = max([abs(Ptotal0); abs(Pfluid); abs(Psolid); 1e-30]);
relTotalDrift = abs(totalDrift) / scaleTotal;

% Consecutive fluid momentum closure against exact measured fluid-side impulse.
prevIndex = zeros(size(is));
valid = false(size(is));
for k = 1:numel(is)
    j = find(S.step == steps(k)-1, 1, 'first');
    if ~isempty(j)
        prevIndex(k) = j;
        valid(k) = true;
    end
end
stepsC = steps(valid);
idC = id(valid);
isC = is(valid);
prevC = prevIndex(valid);
dPxFluid = S.Px(isC) - S.Px(prevC);
fluidImpulse = D.totalFluidImpulseX(idC);
fluidClosureResidual = dPxFluid - fluidImpulse;
fluidScale = max(abs(dPxFluid) + abs(fluidImpulse), 1e-30);
fluidClosureRelative = abs(fluidClosureResidual) ./ fluidScale;

arResidual = D.actionReactionResidualX(id);
arScale = max(abs(D.totalFluidImpulseX(id)) + abs(D.solidReactionImpulseX(id)), 1e-30);
arRelative = abs(arResidual) ./ arScale;

maxRelTotalDrift = max(relTotalDrift);
rmsRelTotalDrift = sqrt(mean(relTotalDrift.^2));
maxRelFluidClosure = max(fluidClosureRelative);
rmsRelFluidClosure = sqrt(mean(fluidClosureRelative.^2));
maxRelActionReaction = max(arRelative);
rmsRelActionReaction = sqrt(mean(arRelative.^2));

versions = D.geometryVersion(id);
versionStrict = all(diff(versions) == 1);
centerStart = D.centerXBefore(id(1));
centerEnd = D.centerXAfter(id(end));
velocityStart = D.velocityXBefore(id(1));
velocityEnd = D.velocityXAfter(id(end));
massRelErr = max(abs(D.mass(id)-solidMass)) / max(abs(solidMass),1e-30);

pass = maxRelTotalDrift < 1e-9 && ...
       maxRelFluidClosure < 1e-9 && ...
       maxRelActionReaction < 1e-12 && ...
       versionStrict && massRelErr < 1e-14;
status = "PASS";
if ~pass, status = "REVIEW"; end

analysisDir = fullfile(runRoot,'analysis');
if ~isfolder(analysisDir), mkdir(analysisDir); end

T = table(steps, D.geometryVersion(id), D.centerXBefore(id), D.centerXAfter(id), ...
    D.velocityXBefore(id), D.velocityXAfter(id), Pfluid, Psolid, Ptotal, totalDrift, relTotalDrift, ...
    D.brinkmanFluidImpulseX(id), D.bathFluidImpulseX(id), D.chiVpFluidImpulseX(id), D.totalFluidImpulseX(id), ...
    D.solidReactionImpulseX(id), D.actionReactionResidualX(id), ...
    'VariableNames', {'step','geometryVersion','centerXBefore','centerXAfter', ...
    'velocityXBefore','velocityXAfter','fluidMomentumX','solidMomentumX','totalMomentumX', ...
    'totalMomentumDriftX','relativeTotalMomentumDriftX','brinkmanFluidImpulseX', ...
    'bathFluidImpulseX','chiVpFluidImpulseX','totalFluidImpulseX','solidReactionImpulseX','actionReactionResidualX'});
writetable(T, fullfile(analysisDir,'momentum_steps_0493x16a.csv'));

fid = fopen(fullfile(analysisDir,'summary_0493x16a.txt'),'w');
assert(fid >= 0, 'Cannot create x16a summary');
cleanup = onCleanup(@() fclose(fid));
fprintf(fid,'0493x16a generic dynamic chi-solid / rigid slab 1D\n');
fprintf(fid,'status=%s\n',status);
fprintf(fid,'steps=%d\n',numel(steps));
fprintf(fid,'solidModel=%s\n',solidModel);
fprintf(fid,'solidMass=%.17g\n',solidMass);
fprintf(fid,'forcingMode=%s\n',forcingMode);
fprintf(fid,'initialDeactivateBelowChi=%.17g\n',initialDeactivate);
fprintf(fid,'geometryVersionFirst=%d\n',versions(1));
fprintf(fid,'geometryVersionLast=%d\n',versions(end));
fprintf(fid,'geometryVersionStrict=%d\n',versionStrict);
fprintf(fid,'centerXStart=%.17g\n',centerStart);
fprintf(fid,'centerXEnd=%.17g\n',centerEnd);
fprintf(fid,'velocityXStart=%.17g\n',velocityStart);
fprintf(fid,'velocityXEnd=%.17g\n',velocityEnd);
fprintf(fid,'initialTotalMomentumX=%.17g\n',Ptotal0);
fprintf(fid,'maxAbsTotalMomentumDriftX=%.17g\n',max(abs(totalDrift)));
fprintf(fid,'rmsRelativeTotalMomentumDriftX=%.17g\n',rmsRelTotalDrift);
fprintf(fid,'maxRelativeTotalMomentumDriftX=%.17g\n',maxRelTotalDrift);
fprintf(fid,'rmsRelativeFluidImpulseClosureX=%.17g\n',rmsRelFluidClosure);
fprintf(fid,'maxRelativeFluidImpulseClosureX=%.17g\n',maxRelFluidClosure);
fprintf(fid,'rmsRelativeActionReactionX=%.17g\n',rmsRelActionReaction);
fprintf(fid,'maxRelativeActionReactionX=%.17g\n',maxRelActionReaction);
fprintf(fid,'solidMassRelativeError=%.17g\n',massRelErr);

fprintf('\n===== 0493x16a DYNAMIC CHI-SOLID / RIGID SLAB 1D =====\n');
fprintf('status                           = %s\n',status);
fprintf('solid model / mass               = %s / %.9g\n',solidModel,solidMass);
fprintf('center X start -> end             = %.9g -> %.9g\n',centerStart,centerEnd);
fprintf('velocity X start -> end           = %.9g -> %.9g\n',velocityStart,velocityEnd);
fprintf('max rel total momentum drift      = %.3e\n',maxRelTotalDrift);
fprintf('max rel fluid impulse closure     = %.3e\n',maxRelFluidClosure);
fprintf('max rel action-reaction residual  = %.3e\n',maxRelActionReaction);
fprintf('geometry versions strict +1       = %d\n',versionStrict);
fprintf('analysis                         = %s\n',analysisDir);
fprintf('=========================================================\n');

figure;
plot(S.time(is), Pfluid, '-', S.time(is), Psolid, '-', S.time(is), Ptotal, '-');
xlabel('time'); ylabel('momentum x');
legend('fluid','solid','total','Location','best');
title('0493x16a momentum exchange'); grid on;

figure;
plot(S.time(is), D.centerXAfter(id), '-');
xlabel('time'); ylabel('X_s'); title('0493x16a rigid slab center'); grid on;

figure;
plot(S.time(is), D.velocityXAfter(id), '-');
xlabel('time'); ylabel('U_s'); title('0493x16a rigid slab velocity'); grid on;

result = struct('status',status,'steps',numel(steps), ...
    'maxRelativeTotalMomentumDriftX',maxRelTotalDrift, ...
    'maxRelativeFluidImpulseClosureX',maxRelFluidClosure, ...
    'maxRelativeActionReactionX',maxRelActionReaction, ...
    'centerXStart',centerStart,'centerXEnd',centerEnd, ...
    'velocityXStart',velocityStart,'velocityXEnd',velocityEnd, ...
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
