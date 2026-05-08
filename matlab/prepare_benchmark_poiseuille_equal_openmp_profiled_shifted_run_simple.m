function prep = prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple(overrides)
if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

if isempty(which('build_benchmark_poiseuille_params_equal'))
    error('build_benchmark_poiseuille_params_equal.m introuvable sur le path.');
end
if isempty(which('build_ad_hoc_state_uniform'))
    error('build_ad_hoc_state_uniform.m introuvable sur le path.');
end
if isempty(which('write_params_kv')) || isempty(which('write_state_bin'))
    error('write_params_kv.m et/ou write_state_bin.m introuvables sur le path.');
end

if ~isfield(overrides,'nThreads') || isempty(overrides.nThreads)
    overrides.nThreads = 8;
end
exeDefault = '/home/llemoyne/gasdyn/mpcd/incompressible/build/main_benchmark_poiseuille_openmp_profiled_shifted_profiled';
if isfield(overrides,'exePath') && ~isempty(overrides.exePath)
    exePath = overrides.exePath;
else
    exePath = exeDefault;
end

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed','nThreads','x','v','type','r0'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f), paramsOverrides = rmfield(paramsOverrides, f); end
end

params = build_benchmark_poiseuille_params_equal(paramsOverrides);
workdir = getf(overrides, 'workdir', fullfile(pwd, 'rbps8'));
prefixIn = getf(overrides, 'prefixIn', 'in');
prefixOut = getf(overrides, 'prefixOut', 'out');
seed = getf(overrides, 'seed', 1);
nThreads = getf(overrides, 'nThreads', 8);

if isfield(overrides, 'x') && isfield(overrides, 'v')
    x = overrides.x; v = overrides.v;
    if isfield(overrides,'type'), type = overrides.type; else, type = zeros(size(x,1),1,'uint8'); end
    if isfield(overrides,'r0'), r0 = overrides.r0; else, r0 = x; end
else
    [x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', seed, 'removeMean', true);
end

if ~exist(workdir,'dir'), mkdir(workdir); end
paramsPath = fullfile(workdir, 'params.kv');
inPrefix = fullfile(workdir, prefixIn);
outPrefix = fullfile(workdir, prefixOut);
runScriptPath = fullfile(workdir, 'run_benchmark_poiseuille_equal_openmp_profiled_shifted.sh');

write_params_kv(params, paramsPath);
write_state_bin(inPrefix, x, v, type, r0);
paramsLinux = to_linux(paramsPath);
inPrefixLinux = to_linux(inPrefix);
outPrefixLinux = to_linux(outPrefix);
runScriptLinux = to_linux(runScriptPath);
exeLinux = to_linux(exePath);

fid = fopen(runScriptPath, 'w');
assert(fid>=0);
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

prep = struct();
prep.params = params;
prep.workdir = workdir;
prep.exePath = exePath;
prep.paramsPath = paramsPath;
prep.inPrefix = inPrefix;
prep.outPrefix = outPrefix;
prep.runScriptPath = runScriptPath;
prep.runScriptLinux = runScriptLinux;
prep.nThreads = nThreads;
prep.dumpSteps = parse_dump_steps_local(params.benchmark_dumpSteps);

fprintf('\n=== prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple ===\n');
fprintf('workdir        : %s\n', workdir);
fprintf('exePath        : %s\n', exePath);
fprintf('nThreads       : %d\n', nThreads);
fprintf('commande WSL   : bash %s\n', runScriptLinux);
fprintf('===============================================================\n');
end

function p = to_linux(a)
p = char(string(a));
if startsWith(p,'/')
    p = regexprep(strrep(p,'\','/'), '/+', '/');
    return;
end
p = strrep(p,'/','\');
pref = '\\wsl.localhost\';
pref2 = '\\wsl$\';
if strncmpi(p,pref,length(pref)) || strncmpi(p,pref2,length(pref2))
    if strncmpi(p,pref,length(pref))
        rest = p(length(pref)+1:end);
    else
        rest = p(length(pref2)+1:end);
    end
    pos = strfind(rest, '\');
    tail = rest(pos(1)+1:end);
    tail = strrep(tail,'\','/');
    p = ['/' regexprep(tail,'/+','/')];
    return;
end
p = regexprep(strrep(p,'\','/'), '/+', '/');
if ~startsWith(p,'/'), error('Chemin non WSL sous Windows:\n%s', a); end
end

function v = getf(s,name,def)
if isfield(s,name), v=s.(name); else, v=def; end
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
