function prep = prepare_benchmark_poiseuille_1500_run_simple(overrides)
%PREPARE_BENCHMARK_POISEUILLE_1500_RUN_SIMPLE Prepare Poiseuille benchmark inputs and run script.
if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
addpath(thisDir);
rootDir = fileparts(thisDir);
exeDefault = fullfile(rootDir, 'build', 'main_benchmark_poiseuille');

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed','x','v','type','r0'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_benchmark_poiseuille_params(paramsOverrides);
workdir = getfield_if_exists_local(overrides, 'workdir', fullfile(pwd, 'run_benchmark_poiseuille_1500'));
exePath = getfield_if_exists_local(overrides, 'exePath', exeDefault);
prefixIn = getfield_if_exists_local(overrides, 'prefixIn', 'state_in');
prefixOut = getfield_if_exists_local(overrides, 'prefixOut', 'benchmark_out');
seed = getfield_if_exists_local(overrides, 'seed', 1);

if isfield(overrides, 'x') && isfield(overrides, 'v')
    x = overrides.x;
    v = overrides.v;
    if isfield(overrides, 'type'), type = overrides.type; else, type = zeros(size(x,1),1,'uint8'); end
    if isfield(overrides, 'r0'), r0 = overrides.r0; else, r0 = x; end
    stateInfo = struct('mode', 'user_supplied');
else
    [x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', seed, 'removeMean', true);
    stateInfo = struct('mode', 'uniform');
end

if ~exist(workdir, 'dir')
    mkdir(workdir);
end
paramsPath = fullfile(workdir, 'params.kv');
inPrefix = fullfile(workdir, prefixIn);
outPrefix = fullfile(workdir, prefixOut);
runScriptPath = fullfile(workdir, 'run_benchmark_poiseuille.sh');

write_params_kv(params, paramsPath);
write_state_bin(inPrefix, x, v, type, r0);

xLinux = to_linux_path_local([inPrefix '_x.bin']);
vLinux = to_linux_path_local([inPrefix '_v.bin']);
typeLinux = to_linux_path_local([inPrefix '_type.bin']);
r0Linux = to_linux_path_local([inPrefix '_r0.bin']);
paramsLinux = to_linux_path_local(paramsPath);
outLinux = to_linux_path_local(outPrefix);
exeLinux = to_linux_path_local(exePath);
runScriptLinux = to_linux_path_local(runScriptPath);

write_shell_script_local(runScriptPath, exeLinux, paramsLinux, xLinux, vLinux, typeLinux, r0Linux, outLinux);

prep = struct();
prep.params = params;
prep.x0 = x;
prep.v0 = v;
prep.type0 = type;
prep.r00 = r0;
prep.stateInfo = stateInfo;
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.inPrefix = inPrefix;
prep.outPrefix = outPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = runScriptLinux;
prep.hasType = true;
prep.hasR0 = true;
prep.dumpSteps = parse_dump_steps_local(params.benchmark_dumpSteps);
save(fullfile(workdir, 'prep_benchmark_poiseuille_1500.mat'), 'prep');

fprintf('\n=== prepare_benchmark_poiseuille_1500_run_simple ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('nSteps         : %d\n', params.benchmark_nSteps);
fprintf('dumpSteps      : %s\n', params.benchmark_dumpSteps);
fprintf('run script     : %s\n', runScriptPath);
fprintf('run script WSL : %s\n', runScriptLinux);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('===============================================\n');
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

function steps = parse_dump_steps_local(s)
if isstring(s), s = char(s); end
parts = regexp(s, ',', 'split');
steps = zeros(1, numel(parts));
for k = 1:numel(parts)
    steps(k) = str2double(strtrim(parts{k}));
end
steps = unique(steps(~isnan(steps)));
end
