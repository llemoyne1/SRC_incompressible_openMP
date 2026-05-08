function prep = prepare_step09_openmp_full_validate_syncserial_run_simple(opts)
if nargin < 1, opts = struct(); end
if ~isfield(opts,'nThreads'), opts.nThreads = 8; end
if ~isfield(opts,'exePath') || isempty(opts.exePath)
    opts.exePath = '/home/llemoyne/gasdyn/mpcd/incompressible/build/main_step09_openmp_full_validate_syncserial';
end
if ~isfield(opts,'workdir') || isempty(opts.workdir)
    opts.workdir = fullfile(pwd,'run_step09_openmp_full_validate_syncserial_manual');
end
if ~exist(opts.workdir,'dir'), mkdir(opts.workdir); end
params = build_tranche5_params();
[x,v,type,r0] = build_ad_hoc_state_modulated(params);
write_params_kv(params, fullfile(opts.workdir,'params.kv'));
write_state_bin(fullfile(opts.workdir,'state_in'), x, v, type, r0);
linuxWorkdir = to_linux_path_local(opts.workdir);
exeLinux = to_linux_path_local(opts.exePath);
sh = fullfile(opts.workdir,'run_step09.sh');
fid = fopen(sh,'w');
fprintf(fid,'#!/usr/bin/env bash\nset -euo pipefail\n');
fprintf(fid,'export OMP_NUM_THREADS=%d\n', opts.nThreads);
fprintf(fid,'chmod +x "%s"\n', exeLinux);
fprintf(fid,'"%s" "%s/params.kv" "%s/state_in_x.bin" "%s/state_in_v.bin" "%s/state_in_type.bin" "%s/state_in_r0.bin" "%s/state_out" 1 1 %d\n', ...
    exeLinux, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, opts.nThreads);
fclose(fid);
prep = struct('workdir', opts.workdir, 'exePath', opts.exePath, 'nThreads', opts.nThreads);
end

function p = to_linux_path_local(a)
p = char(string(a));
if startsWith(p,'/')
    p = strrep(p,'\','/');
    p = regexprep(p,'/+','/');
    return;
end
m = regexp(p, '^\\wsl(?:\.localhost|\$)\([^\]+)\(.*)$', 'tokens', 'once');
if ~isempty(m)
    tail = strrep(m{2},'\','/');
    tail = regexprep(tail,'/+','/');
    p = ['/' tail];
    return;
end
p = strrep(p,'\','/');
p = regexprep(p,'/+','/');
if ~startsWith(p,'/')
    error('Chemin non WSL sous Windows: %s', a);
end
end
