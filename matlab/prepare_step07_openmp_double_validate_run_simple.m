function prep = prepare_step07_openmp_double_validate_run_simple(cfg)
if nargin < 1 || isempty(cfg), cfg = struct(); end

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
rootDir  = fileparts(thisDir);

if ~isfield(cfg,'workdir') || isempty(cfg.workdir)
    workdir = fullfile(pwd,'run_step07_openmp_double_validate_manual');
else
    workdir = cfg.workdir;
end
if ~exist(workdir,'dir'), mkdir(workdir); end

if ~isfield(cfg,'nThreads') || isempty(cfg.nThreads)
    nThreads = 8;
else
    nThreads = cfg.nThreads;
end

if ~isfield(cfg,'paramsOverrides') || isempty(cfg.paramsOverrides)
    paramsOverrides = struct();
else
    paramsOverrides = cfg.paramsOverrides;
end
if ~isfield(cfg,'stateMode') || isempty(cfg.stateMode)
    stateMode = 'modulated';
else
    stateMode = cfg.stateMode;
end

if ~isfield(cfg,'exePath') || isempty(cfg.exePath)
    exePath = fullfile(rootDir,'build','main_step07_openmp_double_validate');
else
    exePath = cfg.exePath;
end

params = build_tranche5_params(paramsOverrides);
params.useZoneRedistribution = true;
params.zoneSingleFullDomainMode = false;
params.zonePassthroughMode = false;
params.zoneUseShiftedSecondPass = true;
params.noSurfaceCase = true;
params.redistributionEnableSurfaceTopology = false;
params.redistributionWallWettingEnabled = false;
params.useInterfaceVelocityReorientation = false;

switch lower(stateMode)
    case 'modulated'
        [x,v,type,r0] = build_ad_hoc_state_modulated(params);
    otherwise
        error('Unsupported stateMode: %s', stateMode);
end

paramsPath = fullfile(workdir,'params.kv');
write_params_kv(params, paramsPath);
write_state_bin(fullfile(workdir,'state_in'), x, v, type, r0);

prep = struct();
prep.workdir = workdir;
prep.exePath = exePath;
prep.nThreads = nThreads;
prep.paramsPath = paramsPath;
prep.outPrefix = fullfile(workdir,'state_out');
prep.hasType = 1;
prep.hasR0 = 1;
prep.params = params;

linuxWorkdir = to_linux_path_local(workdir);
linuxExe = to_linux_path_local(exePath);
runSh = fullfile(workdir,'run_step07.sh');
fid = fopen(runSh,'w');
assert(fid>=0,'Cannot create run_step07.sh');
fprintf(fid,'#!/usr/bin/env bash\n');
fprintf(fid,'set -euo pipefail\n');
fprintf(fid,'chmod +x "%s"\n', linuxExe);
fprintf(fid,'"%s" "%s" "%s" "%s" "%s" "%s" "%s" %d %d %d\n', ...
    linuxExe, ...
    join_linux_path_local(linuxWorkdir,'params.kv'), ...
    join_linux_path_local(linuxWorkdir,'state_in_x.bin'), ...
    join_linux_path_local(linuxWorkdir,'state_in_v.bin'), ...
    join_linux_path_local(linuxWorkdir,'state_in_type.bin'), ...
    join_linux_path_local(linuxWorkdir,'state_in_r0.bin'), ...
    join_linux_path_local(linuxWorkdir,'state_out'), ...
    1, 1, nThreads);
fclose(fid);

fprintf('=== prepare_step07_openmp_double_validate_run_simple ===\n');
fprintf('workdir : %s\n', workdir);
fprintf('run via : bash %s\n', join_linux_path_local(linuxWorkdir,'run_step07.sh'));
fprintf('=======================================================\n');
end

function p = to_linux_path_local(p0)
p0 = char(string(p0));
if ispc
    tok = regexp(p0,'^\\\\wsl(?:\.localhost)?\\([^\\]+)\\(.*)$','tokens','once','ignorecase');
    if isempty(tok)
        tok = regexp(p0,'^\\\\wsl\$\\([^\\]+)\\(.*)$','tokens','once','ignorecase');
    end
    if ~isempty(tok)
        rest = strrep(tok{2},'\\','/');
        parts = regexp(rest,'/+','split');
        stk = {};
        for i=1:numel(parts)
            q = parts{i};
            if isempty(q) || strcmp(q,'.')
                continue;
            elseif strcmp(q,'..')
                if ~isempty(stk), stk(end)=[]; end
            else
                stk{end+1} = q; %#ok<AGROW>
            end
        end
        p = ['/' strjoin(stk,'/')];
        return;
    end
end
p = strrep(p0,'\\','/');
end

function p = join_linux_path_local(base, name)
base = char(string(base));
name = char(string(name));
base = regexprep(base, '/+$', '');
name = regexprep(name, '^/+', '');
p = [base '/' name];
end
