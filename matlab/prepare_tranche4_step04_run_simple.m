function prep = prepare_tranche4_step04_run_simple(overrides)
%PREPARE_TRANCHE4_STEP04_RUN_SIMPLE Prepare tranche 4 liquid-closure inputs and a WSL shell script.
if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
addpath(thisDir);
rootDir = fileparts(thisDir);
exeDefault = fullfile(rootDir, 'build', 'main_step04_liquid_closure');

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixRef','prefixRed','prefixOut','seed','amp','moveFrac','mode', ...
    'velocityBias','xRef','vRef','xRed','vRed','type','r0'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_tranche4_params(paramsOverrides);
workdir = getfield_if_exists_local(overrides, 'workdir', fullfile(pwd, 'run_tranche4_step04_manual'));
exePath = getfield_if_exists_local(overrides, 'exePath', exeDefault);
prefixRef = getfield_if_exists_local(overrides, 'prefixRef', 'state_ref');
prefixRed = getfield_if_exists_local(overrides, 'prefixRed', 'state_red');
prefixOut = getfield_if_exists_local(overrides, 'prefixOut', 'state_out');
seed = getfield_if_exists_local(overrides, 'seed', 1);
amp = getfield_if_exists_local(overrides, 'amp', 0.25);
moveFrac = getfield_if_exists_local(overrides, 'moveFrac', 0.08);
mode = char(string(getfield_if_exists_local(overrides, 'mode', 'checker')));
velocityBias = getfield_if_exists_local(overrides, 'velocityBias', 0.05);

if isfield(overrides, 'xRef') && isfield(overrides, 'vRef') && isfield(overrides, 'xRed') && isfield(overrides, 'vRed')
    xRef = overrides.xRef;
    vRef = overrides.vRef;
    xRed = overrides.xRed;
    vRed = overrides.vRed;
    if isfield(overrides, 'type'), type = overrides.type; else, type = zeros(size(xRef,1),1,'uint8'); end
    if isfield(overrides, 'r0'), r0 = overrides.r0; else, r0 = xRef; end
    stateInfo = struct('mode', 'user_supplied');
else
    [xRef, vRef, xRed, vRed, type, r0, stateInfo] = build_ad_hoc_ref_red_states(params, ...
        'seed', seed, 'amp', amp, 'moveFrac', moveFrac, 'mode', mode, 'velocityBias', velocityBias);
end

if ~exist(workdir, 'dir')
    mkdir(workdir);
end
paramsPath = fullfile(workdir, 'params.kv');
refPrefix = fullfile(workdir, prefixRef);
redPrefix = fullfile(workdir, prefixRed);
outPrefix = fullfile(workdir, prefixOut);
runScriptPath = fullfile(workdir, 'run_step04.sh');

write_params_kv(params, paramsPath);
write_state_bin(refPrefix, xRef, vRef, type, r0);
write_state_bin(redPrefix, xRed, vRed, type, r0);

refXLinux = to_linux_path_local([refPrefix '_x.bin']);
refVLinux = to_linux_path_local([refPrefix '_v.bin']);
redXLinux = to_linux_path_local([redPrefix '_x.bin']);
redVLinux = to_linux_path_local([redPrefix '_v.bin']);
typeLinux = to_linux_path_local([refPrefix '_type.bin']);
r0Linux = to_linux_path_local([refPrefix '_r0.bin']);
paramsLinux = to_linux_path_local(paramsPath);
outLinux = to_linux_path_local(outPrefix);
exeLinux = to_linux_path_local(exePath);
runScriptLinux = to_linux_path_local(runScriptPath);

write_shell_script_local(runScriptPath, exeLinux, paramsLinux, refXLinux, refVLinux, redXLinux, redVLinux, typeLinux, r0Linux, outLinux);

prep = struct();
prep.params = params;
prep.xRef0 = xRef;
prep.vRef0 = vRef;
prep.xRed0 = xRed;
prep.vRed0 = vRed;
prep.type0 = type;
prep.r00 = r0;
prep.stateInfo = stateInfo;
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.refPrefix = refPrefix;
prep.redPrefix = redPrefix;
prep.outPrefix = outPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = runScriptLinux;
prep.hasType = true;
prep.hasR0 = true;
save(fullfile(workdir, 'prep_tranche4_step04.mat'), 'prep');

fprintf('\n=== prepare_tranche4_step04_run_simple ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('stateMode      : %s\n', stateInfo.mode);
fprintf('run script     : %s\n', runScriptPath);
fprintf('run script WSL : %s\n', runScriptLinux);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('==========================================\n');
end

function write_shell_script_local(scriptPath, exeLinux, paramsLinux, refXLinux, refVLinux, redXLinux, redVLinux, typeLinux, r0Linux, outLinux)
fid = fopen(scriptPath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', scriptPath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '#!/usr/bin/env bash\n');
fprintf(fid, 'set -euo pipefail\n');
fprintf(fid, 'chmod +x "%s"\n', exeLinux);
fprintf(fid, '"%s" \\\n', exeLinux);
fprintf(fid, '  "%s" \\\n', paramsLinux);
fprintf(fid, '  "%s" \\\n', refXLinux);
fprintf(fid, '  "%s" \\\n', refVLinux);
fprintf(fid, '  "%s" \\\n', redXLinux);
fprintf(fid, '  "%s" \\\n', redVLinux);
fprintf(fid, '  "%s" \\\n', typeLinux);
fprintf(fid, '  "%s" \\\n', r0Linux);
fprintf(fid, '  "%s" \\\n', outLinux);
fprintf(fid, '  1 \\\n');
fprintf(fid, '  1 \\\n');
fprintf(fid, '  1\n');
end

function pLinux = to_linux_path_local(p)
p = char(string(p));
if ispc
    [tf, ~, linuxPath] = wsl_unc_to_linux_local(p);
    if tf
        pLinux = linuxPath;
        return;
    end
    error('Chemin non WSL sous Windows: %s', p);
end
pLinux = p;
end

function [tf, distro, linuxPath] = wsl_unc_to_linux_local(p)
p = char(string(p));
p = strrep(p, '/', '\\');
linuxPath = '';
distro = '';
tf = false;
tok = regexp(p, '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\?(.*)$', 'tokens', 'once', 'ignorecase');
if isempty(tok)
    return;
end
distro = tok{1}; %#ok<NASGU>
rest = tok{2};
if isempty(rest)
    linuxPath = '/';
    tf = true;
    return;
end
parts = regexp(rest, '\\+', 'split');
parts = resolve_unc_parts_local(parts);
linuxPath = ['/' strjoin(parts, '/')];
tf = true;
end

function partsOut = resolve_unc_parts_local(partsIn)
partsOut = {};
for i = 1:numel(partsIn)
    tok = partsIn{i};
    if isempty(tok) || strcmp(tok, '.')
        continue;
    end
    if strcmp(tok, '..')
        assert(~isempty(partsOut), 'Chemin WSL invalide: remontee au-dessus de la racine Linux.');
        partsOut(end) = [];
    else
        partsOut{end+1} = tok; %#ok<AGROW>
    end
end
end

function v = getfield_if_exists_local(s, name, defaultValue)
if isfield(s, name)
    v = s.(name);
else
    v = defaultValue;
end
end
