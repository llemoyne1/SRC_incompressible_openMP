function prep = prepare_step08_openmp_full_validate_run_simple_fixed(opts)
if nargin < 1, opts = struct(); end

if ~isfield(opts,'nThreads') || isempty(opts.nThreads)
    opts.nThreads = 8;
end
if ~isfield(opts,'exePath') || isempty(opts.exePath)
    opts.exePath = '/home/llemoyne/gasdyn/mpcd/incompressible/build/main_step08_openmp_full_validate';
end
if ~isfield(opts,'workdir') || isempty(opts.workdir)
    opts.workdir = fullfile(pwd,'run_step08_openmp_full_validate_manual');
end

if ~exist(opts.workdir,'dir')
    mkdir(opts.workdir);
end

params = build_tranche5_params();
[x,v,type,r0] = build_ad_hoc_state_modulated(params);

paramsPath = fullfile(opts.workdir,'params.kv');
statePrefix = fullfile(opts.workdir,'state_in');
sh = fullfile(opts.workdir,'run_step08.sh');

write_params_kv(params, paramsPath);
write_state_bin(statePrefix, x, v, type, r0);

linuxWorkdir = to_linux_path_local(opts.workdir);
exeLinux = to_linux_path_local(opts.exePath);
paramsLinux = join_linux_path_local(linuxWorkdir, 'params.kv');
statePrefixLinux = join_linux_path_local(linuxWorkdir, 'state_in');
outPrefixLinux = join_linux_path_local(linuxWorkdir, 'state_out');

fid = fopen(sh,'w');
assert(fid >= 0, 'Cannot open %s for writing.', sh);
c = onCleanup(@() fclose(fid));

fprintf(fid,'#!/usr/bin/env bash\n');
fprintf(fid,'set -euo pipefail\n');
fprintf(fid,'export OMP_NUM_THREADS=%d\n', opts.nThreads);
fprintf(fid,'"%s" "%s" "%s_x.bin" "%s_v.bin" "%s_type.bin" "%s_r0.bin" "%s" 1 1 %d\n', ...
    exeLinux, paramsLinux, statePrefixLinux, statePrefixLinux, statePrefixLinux, statePrefixLinux, outPrefixLinux, opts.nThreads);
clear c;

prep = struct();
prep.workdir = opts.workdir;
prep.exePath = opts.exePath;
prep.nThreads = opts.nThreads;
prep.paramsPath = paramsPath;
prep.statePrefix = statePrefix;
prep.runScript = sh;
end

function p = to_linux_path_local(a)
p = char(string(a));
if startsWith(p,'/')
    p = regexprep(strrep(p,'\\','/'), '/+', '/');
    return;
end
m = regexp(p, '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\(.*)$', 'tokens', 'once');
if ~isempty(m)
    tail = m{2};
    tail = strrep(tail,'\\','/');
    tail = regexprep(tail,'/+', '/');
    p = ['/' tail];
    return;
end
p = strrep(p,'\\','/');
p = regexprep(p,'/+', '/');
if ~startsWith(p,'/')
    error('Chemin non WSL sous Windows: %s', a);
end
end

function p = join_linux_path_local(base, name)
base = char(string(base));
name = char(string(name));
base = regexprep(strrep(base,'\\','/'), '/+', '/');
name = regexprep(strrep(name,'\\','/'), '/+', '/');
base = regexprep(base, '/+$', '');
name = regexprep(name, '^/+', '');
p = [base '/' name];
end
