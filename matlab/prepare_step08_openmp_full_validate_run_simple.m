
function prep = prepare_step08_openmp_full_validate_run_simple(opts)
if nargin < 1, opts = struct(); end
rootDir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
matlabDir = fileparts(mfilename('fullpath'));
if ~isfield(opts,'nThreads'), opts.nThreads = 8; end
if ~isfield(opts,'exePath') || isempty(opts.exePath)
    opts.exePath = '/home/llemoyne/gasdyn/mpcd/incompressible/build/main_step08_openmp_full_validate';
end
if ~isfield(opts,'workdir') || isempty(opts.workdir)
    opts.workdir = fullfile(pwd,'run_step08_openmp_full_validate_manual');
end
if ~exist(opts.workdir,'dir'), mkdir(opts.workdir); end
params = build_tranche5_params();
[x,v,type,r0] = build_ad_hoc_state_modulated(params);
write_params_kv(params, fullfile(opts.workdir,'params.kv'));
write_state_bin(fullfile(opts.workdir,'state_in_x.bin'), x);
write_state_bin(fullfile(opts.workdir,'state_in_v.bin'), v);
write_u8_local(fullfile(opts.workdir,'state_in_type.bin'), uint8(type(:)));
write_state_bin(fullfile(opts.workdir,'state_in_r0.bin'), r0);
linuxWorkdir = to_linux_path_local(opts.workdir);
exeLinux = to_linux_path_local(opts.exePath);
sh = fullfile(opts.workdir,'run_step08.sh');
fid = fopen(sh,'w');
fprintf(fid,'#!/usr/bin/env bash\nset -euo pipefail\n');
fprintf(fid,'export OMP_NUM_THREADS=%d\n', opts.nThreads);
fprintf(fid,'chmod +x "%s"\n', exeLinux);
fprintf(fid,'"%s" "%s/params.kv" "%s/state_in_x.bin" "%s/state_in_v.bin" "%s/state_in_type.bin" "%s/state_in_r0.bin" "%s/state_out" 1 1 %d\n', exeLinux, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, linuxWorkdir, opts.nThreads);
fclose(fid);
fileattrib(sh,'+x');
prep = struct('workdir', opts.workdir, 'exePath', opts.exePath, 'nThreads', opts.nThreads);
end

function p = to_linux_path_local(a)
p = char(string(a));
if startsWith(p,'/'), p = regexprep(strrep(p,'\','/'), '/+', '/'); return; end
m = regexp(p, '^\\\\wsl(?:\.localhost|\$)\\([^\\]+)\\(.*)$', 'tokens', 'once');
if ~isempty(m)
    tail = m{2};
    tail = strrep(tail,'\','/');
    tail = regexprep(tail,'/+', '/');
    p = ['/' tail];
    return;
end
p = strrep(p,'\','/');
p = regexprep(p,'/+', '/');
if ~startsWith(p,'/'), error('Chemin non WSL sous Windows: %s', a); end
end

function write_u8_local(path, u)
fid=fopen(path,'wb'); fwrite(fid,u,'uint8'); fclose(fid);
end
