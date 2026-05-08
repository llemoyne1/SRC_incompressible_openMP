function prep = prepare_tranche3_step03_run_simple(overrides)
%PREPARE_TRANCHE3_STEP03_RUN_SIMPLE Prepare tranche 3 double-pass inputs and a WSL shell script.
if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
addpath(thisDir);
rootDir = fileparts(thisDir);
exeDefault = fullfile(rootDir, 'build', 'main_step03_double_zone_pass');

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed','stateMode','amp','x','v','type','r0'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_tranche2_params(paramsOverrides);
workdir = getfield_if_exists_local(overrides, 'workdir', fullfile(pwd, 'run_tranche3_step03_manual'));
exePath = getfield_if_exists_local(overrides, 'exePath', exeDefault);
prefixIn = getfield_if_exists_local(overrides, 'prefixIn', 'state_in');
prefixOut = getfield_if_exists_local(overrides, 'prefixOut', 'state_out');
seed = getfield_if_exists_local(overrides, 'seed', 1);
stateMode = char(string(getfield_if_exists_local(overrides, 'stateMode', 'modulated')));
amp = getfield_if_exists_local(overrides, 'amp', 0.35);

if isfield(overrides, 'x') && isfield(overrides, 'v')
    x = overrides.x;
    v = overrides.v;
    if isfield(overrides, 'type'), type = overrides.type; else, type = zeros(size(x,1),1,'uint8'); end
    if isfield(overrides, 'r0'),   r0 = overrides.r0;   else, r0 = x; end
    stateInfo = struct('mode', 'user_supplied');
else
    switch lower(stateMode)
        case 'modulated'
            [x, v, type, r0, stateInfo] = build_ad_hoc_state_modulated(params, 'seed', seed, 'amp', amp);
        case 'uniform'
            [x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', seed);
            stateInfo = struct('mode', 'uniform');
        otherwise
            error('Unknown stateMode: %s', stateMode);
    end
end

if ~exist(workdir, 'dir')
    mkdir(workdir);
end

paramsPath = fullfile(workdir, 'params.kv');
stateInPrefix = fullfile(workdir, prefixIn);
stateOutPrefix = fullfile(workdir, prefixOut);
runScriptPath = fullfile(workdir, 'run_step03.sh');

write_params_kv(params, paramsPath);
write_state_bin(stateInPrefix, x, v, type, r0);

xPath = [stateInPrefix '_x.bin'];
vPath = [stateInPrefix '_v.bin'];
typePath = [stateInPrefix '_type.bin'];
r0Path = [stateInPrefix '_r0.bin'];

exeLinux = to_linux_path_local(exePath);
paramsLinux = to_linux_path_local(paramsPath);
xLinux = to_linux_path_local(xPath);
vLinux = to_linux_path_local(vPath);
typeLinux = to_linux_path_local(typePath);
r0Linux = to_linux_path_local(r0Path);
outLinux = to_linux_path_local(stateOutPrefix);
runScriptLinux = to_linux_path_local(runScriptPath);

write_shell_script_local(runScriptPath, exeLinux, paramsLinux, xLinux, vLinux, typeLinux, r0Linux, outLinux);

prep = struct();
prep.params = params;
prep.x0 = x;
prep.v0 = v;
prep.type0 = type;
prep.r00 = r0;
prep.stateInfo = stateInfo;
prep.seed = seed;
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.stateInPrefix = stateInPrefix;
prep.stateOutPrefix = stateOutPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = runScriptLinux;
prep.hasType = true;
prep.hasR0 = true;
save(fullfile(workdir, 'prep_tranche3_step03.mat'), 'prep');

fprintf('\n=== prepare_tranche3_step03_run_simple ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('stateMode      : %s\n', stateInfo.mode);
fprintf('run script     : %s\n', runScriptPath);
fprintf('run script WSL : %s\n', runScriptLinux);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('==========================================\n');
end

function write_shell_script_local(scriptPath, exeLinux, paramsLinux, xLinux, vLinux, typeLinux, r0Linux, outLinux)
fid = fopen(scriptPath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', scriptPath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '#!/usr/bin/env bash\n');
fprintf(fid, 'set -euo pipefail\n');
fprintf(fid, 'chmod +x "%s"\n', exeLinux);
fprintf(fid, '"%s" \\\n', exeLinux);
fprintf(fid, '  "%s" \\\n', paramsLinux);
fprintf(fid, '  "%s" \\\n', xLinux);
fprintf(fid, '  "%s" \\\n', vLinux);
fprintf(fid, '  "%s" \\\n', typeLinux);
fprintf(fid, '  "%s" \\\n', r0Linux);
fprintf(fid, '  "%s" \\\n', outLinux);
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
