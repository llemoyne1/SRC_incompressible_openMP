function prep = prepare_benchmark_poiseuille_equal_openmp_profiled_refbuild(overrides)
if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

if isempty(which('build_benchmark_poiseuille_params_equal'))
    error(['build_benchmark_poiseuille_params_equal.m introuvable sur le path. ' ...
           'Ajoute le dossier matlab de benchmark_poiseuille_cpp_equal.']);
end
if isempty(which('build_ad_hoc_state_uniform'))
    error(['build_ad_hoc_state_uniform.m introuvable sur le path. ' ...
           'Ajoute aussi le dossier matlab de tranche1 / benchmark.']);
end
if isempty(which('write_params_kv')) || isempty(which('write_state_bin'))
    error(['write_params_kv.m et/ou write_state_bin.m introuvables sur le path. ' ...
           'Ajoute le dossier matlab de tranche1.']);
end

if ~isfield(overrides,'nThreads') || isempty(overrides.nThreads)
    overrides.nThreads = 8;
end

exeDefault = '/home/llemoyne/gasdyn/mpcd/incompressible/build/main_benchmark_poiseuille_openmp_profiled_refbuild_omp';
if isfield(overrides,'exePath') && ~isempty(overrides.exePath)
    exePath = overrides.exePath;
else
    exePath = exeDefault;
end

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed','nThreads','x','v','type','r0'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_benchmark_poiseuille_params_equal(paramsOverrides);
workdir = getfield_if_exists_local(overrides, 'workdir', fullfile(pwd, 'run_benchmark_poiseuille_equal_openmp_profiled_refbuild_omp'));
prefixIn = getfield_if_exists_local(overrides, 'prefixIn', 'state_in');
prefixOut = getfield_if_exists_local(overrides, 'prefixOut', 'benchmark_out');
seed = getfield_if_exists_local(overrides, 'seed', 1);
nThreads = getfield_if_exists_local(overrides, 'nThreads', 8);

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
runScriptPath = fullfile(workdir, 'run_benchmark_poiseuille_equal_openmp_profiled_refbuild_omp.sh');

write_params_kv(params, paramsPath);
write_state_bin(inPrefix, x, v, type, r0);

paramsLinux = to_linux_path_local(paramsPath);
inPrefixLinux = to_linux_path_local(inPrefix);
outPrefixLinux = to_linux_path_local(outPrefix);
runScriptLinux = to_linux_path_local(runScriptPath);
exeLinux = to_linux_path_local(exePath);

write_shell_script_local(runScriptPath, exeLinux, paramsLinux, inPrefixLinux, outPrefixLinux, nThreads);

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
prep.nThreads = nThreads;
prep.hasType = true;
prep.hasR0 = true;
prep.dumpSteps = parse_dump_steps_local(params.benchmark_dumpSteps);
save(fullfile(workdir, 'prep_benchmark_poiseuille_profiled.mat'), 'prep');

fprintf('\n=== prepare_benchmark_poiseuille_equal_openmp_profiled_refbuild_omp_run_simple ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('nThreads       : %d\n', nThreads);
fprintf('nSteps         : %d\n', params.benchmark_nSteps);
fprintf('dumpSteps      : %s\n', params.benchmark_dumpSteps);
fprintf('bodyForceX     : %.12g\n', params.bodyForceX);
fprintf('gamma          : %.12g\n', params.gamma);
fprintf('zone tiles     : %d x %d\n', params.zoneTileNx, params.zoneTileNy);
fprintf('run script     : %s\n', runScriptPath);
fprintf('run script WSL : %s\n', runScriptLinux);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('==============================================================\n');
end

function write_shell_script_local(scriptPath, exeLinux, paramsLinux, inPrefixLinux, outPrefixLinux, nThreads)
fid = fopen(scriptPath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', scriptPath);
fprintf(fid, '#!/usr/bin/env bash\n');
fprintf(fid, 'set -euo pipefail\n');
fprintf(fid, 'export OMP_NUM_THREADS=%d\n', nThreads);
fprintf(fid, 'chmod +x "%s"\n', exeLinux);
fprintf(fid, '"%s" \\\n', exeLinux);
fprintf(fid, '  "%s" \\\n', paramsLinux);
fprintf(fid, '  "%s_x.bin" \\\n', inPrefixLinux);
fprintf(fid, '  "%s_v.bin" \\\n', inPrefixLinux);
fprintf(fid, '  "%s_type.bin" \\\n', inPrefixLinux);
fprintf(fid, '  "%s_r0.bin" \\\n', inPrefixLinux);
fprintf(fid, '  "%s" \\\n', outPrefixLinux);
fprintf(fid, '  1 \\\n');
fprintf(fid, '  1 \\\n');
fprintf(fid, '  %d\n', nThreads);
fclose(fid);
end

function pLinux = to_linux_path_local(p)
p = char(string(p));
if startsWith(p, '/')
    pLinux = regexprep(strrep(p,'\','/'), '/+', '/');
    return;
end

[tf, linuxPath] = wsl_unc_to_linux_local(p);
if tf
    pLinux = linuxPath;
    return;
end

p2 = strrep(p,'\','/');
p2 = regexprep(p2,'/+','/');
if startsWith(p2, '/')
    pLinux = p2;
    return;
end

error('Chemin non WSL sous Windows:\n%s', p);
end

function [tf, linuxPath] = wsl_unc_to_linux_local(p)
p = char(string(p));
p = strrep(p, '/', '\');
linuxPath = '';
tf = false;

prefixes = {'\\wsl.localhost\', '\\wsl$\'};
for i = 1:numel(prefixes)
    pref = prefixes{i};
    if strncmpi(p, pref, length(pref))
        rest = p(length(pref)+1:end);
        pos = strfind(rest, '\');
        if isempty(pos)
            return;
        end
        tail = rest(pos(1)+1:end); % drop distro name
        tail = strrep(tail, '\', '/');
        tail = regexprep(tail, '/+', '/');
        linuxPath = ['/' tail];
        tf = true;
        return;
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
