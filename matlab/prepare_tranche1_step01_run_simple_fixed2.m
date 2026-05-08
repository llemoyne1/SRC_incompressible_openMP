function prep = prepare_tranche1_step01_run_simple_fixed2(overrides)
%PREPARE_TRANCHE1_STEP01_RUN_SIMPLE_FIXED2
% Prepare tranche 1 inputs and write a shell script to run manually from WSL.
% This version avoids fragile command construction in MATLAB and uses a more
% robust UNC->Linux path conversion.

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('overrides doit etre un struct scalaire ou vide.');
end

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
addpath(thisDir);

exeDefault = fullfile(thisDir, '..', 'build', 'main_step01_stream_bc_collision');

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_tranche1_params(paramsOverrides);
workdir = getfield_if_exists_local(overrides, 'workdir', fullfile(pwd, 'run_tranche1_step01_manual'));
exePath = getfield_if_exists_local(overrides, 'exePath', exeDefault);
prefixIn = getfield_if_exists_local(overrides, 'prefixIn', 'state_in');
prefixOut = getfield_if_exists_local(overrides, 'prefixOut', 'state_out');
seed = getfield_if_exists_local(overrides, 'seed', 1);

[x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', seed);

if ~exist(workdir, 'dir')
    mkdir(workdir);
end

paramsPath = fullfile(workdir, 'params.kv');
stateInPrefix = fullfile(workdir, prefixIn);
stateOutPrefix = fullfile(workdir, prefixOut);

write_params_kv(params, paramsPath);
write_state_bin(stateInPrefix, x, v, type, r0);

xPath = [stateInPrefix '_x.bin'];
vPath = [stateInPrefix '_v.bin'];
typePath = [stateInPrefix '_type.bin'];
r0Path = [stateInPrefix '_r0.bin'];
runScriptPath = fullfile(workdir, 'run_step01.sh');

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
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.stateInPrefix = stateInPrefix;
prep.stateOutPrefix = stateOutPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = runScriptLinux;
prep.hasType = true;
prep.hasR0 = true;
prep.seed = seed;

save(fullfile(workdir, 'prep_tranche1_step01.mat'), 'prep');

fprintf('\n=== prepare_tranche1_step01_run_simple_fixed2 ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('run script     : %s\n', runScriptPath);
fprintf('run script WSL : %s\n', runScriptLinux);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('================================================\n');
end

function write_shell_script_local(scriptPath, exeLinux, paramsLinux, xLinux, vLinux, typeLinux, r0Linux, outLinux)
fid = fopen(scriptPath, 'w');
if fid < 0
    error('Impossible d''ouvrir le script shell: %s', scriptPath);
end
cleanup = onCleanup(@() fclose(fid));

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

% Match both \\wsl.localhost\Distro\... and \\wsl$\Distro\...
tok = regexp(p, '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\?(.*)$', 'tokens', 'once', 'ignorecase');
if isempty(tok)
    return;
end

distro = tok{1};
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
        if isempty(partsOut)
            error('Chemin WSL invalide: remontee au-dessus de la racine Linux.');
        end
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
