function prep = prepare_tranche1_step01_run(overrides)
%PREPARE_TRANCHE1_STEP01_RUN
% Prepare MATLAB inputs for tranche 1 step01 without executing the C++ code.
% It generates params, x, v, type, r0, writes the input files, and returns
% the command to launch manually.
%
% Usage:
%   prep = prepare_tranche1_step01_run();
%   prep = prepare_tranche1_step01_run(struct('Nx',64,'Ny',64));
%
% Then launch prep.command in a shell, and post-process with:
%   out = process_tranche1_step01_results(prep);

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('overrides doit etre un struct scalaire ou vide.');
end

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
addpath(thisDir);

if ispc && is_wsl_unc_path(thisDir)
    exeDefault = fullfile(thisDir, '..', 'build', 'main_step01_stream_bc_collision');
else
    exeDefault = fullfile(thisDir, '..', 'build', exe_name_local('main_step01_stream_bc_collision'));
end

paramsOverrides = overrides;
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','seed'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_tranche1_params(paramsOverrides);
workdir = getfield_if_exists(overrides, 'workdir', fullfile(pwd, 'run_tranche1_step01_manual')); %#ok<GFLD>
exePath = getfield_if_exists(overrides, 'exePath', exeDefault); %#ok<GFLD>
prefixIn = getfield_if_exists(overrides, 'prefixIn', 'state_in'); %#ok<GFLD>
prefixOut = getfield_if_exists(overrides, 'prefixOut', 'state_out'); %#ok<GFLD>
seed = getfield_if_exists(overrides, 'seed', 1); %#ok<GFLD>

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

[~, command, execInfo] = build_command_local(exePath, paramsPath, xPath, vPath, typePath, r0Path, stateOutPrefix, true, true, workdir);

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
prep.command = command;
prep.execInfo = execInfo;
prep.hasType = true;
prep.hasR0 = true;
prep.seed = seed;

save(fullfile(workdir, 'prep_tranche1_step01.mat'), 'prep');

fprintf('\n=== prepare_tranche1_step01_run ===\n');
fprintf('workdir   : %s\n', workdir);
fprintf('exePath   : %s\n', exePath);
fprintf('mode      : %s\n', execInfo.mode);
if isfield(execInfo, 'linuxExePath')
    fprintf('linux exe : %s\n', execInfo.linuxExePath);
end
fprintf('command   : %s\n', command);
fprintf('inputs ecrits dans : %s\n', workdir);
fprintf('fichier prep       : %s\n', fullfile(workdir, 'prep_tranche1_step01.mat'));
fprintf('===================================\n');
end

function [wslMode, cmd, info] = build_command_local(exePath, paramsPath, xPath, vPath, typePath, r0Path, stateOutPrefix, hasType, hasR0, workdir)
info = struct();
exePath = char(string(exePath));
workdir = char(string(workdir));

[tfExe, distroExe, exeLinux] = wsl_unc_to_linux_local(exePath);
[tfWk,  distroWk,  ~] = wsl_unc_to_linux_local(workdir);

wslMode = ispc && (tfExe || tfWk);
if ~wslMode
    cmd = strjoin({ ...
        quote_arg_winposix_local(exePath), ...
        quote_arg_winposix_local(paramsPath), ...
        quote_arg_winposix_local(xPath), ...
        quote_arg_winposix_local(vPath), ...
        quote_arg_winposix_local(typePath), ...
        quote_arg_winposix_local(r0Path), ...
        quote_arg_winposix_local(stateOutPrefix), ...
        ternary_str_local(hasType), ...
        ternary_str_local(hasR0)}, ' ');
    info.mode = 'direct';
    return;
end

if tfExe
    distro = distroExe;
else
    distro = distroWk;
end

[ok, ~, paramsLinux] = wsl_unc_to_linux_local(paramsPath);
assert(ok, 'paramsPath must be under the same WSL distro when using WSL mode.');
[ok, ~, xLinux] = wsl_unc_to_linux_local(xPath);      assert(ok, 'xPath must be a WSL path.');
[ok, ~, vLinux] = wsl_unc_to_linux_local(vPath);      assert(ok, 'vPath must be a WSL path.');
[ok, ~, typeLinux] = wsl_unc_to_linux_local(typePath);assert(ok, 'typePath must be a WSL path.');
[ok, ~, r0Linux] = wsl_unc_to_linux_local(r0Path);    assert(ok, 'r0Path must be a WSL path.');
[ok, ~, outLinux] = wsl_unc_to_linux_local(stateOutPrefix); assert(ok, 'stateOutPrefix must be a WSL path.');

if ~tfExe
    error('When using WSL mode, exePath must point to a WSL executable path.');
end

linuxArgs = {exeLinux, paramsLinux, xLinux, vLinux, typeLinux, r0Linux, outLinux, ternary_str_local(hasType), ternary_str_local(hasR0)};
linuxCmd = strjoin(cellfun(@bash_quote_arg_local, linuxArgs, 'UniformOutput', false), ' ');
cmd = ['wsl.exe -d ' quote_arg_winposix_local(distro) ' -- bash -lc ' quote_arg_winposix_local(linuxCmd)];

info.mode = 'wsl';
info.distro = distro;
info.linuxExePath = exeLinux;
end

function s = quote_arg_winposix_local(a)
a = char(string(a));
if ispc
    s = ['"' strrep(a, '"', '""') '"'];
else
    s = ['''' strrep(a, '''', '''"'"''') ''''];
end
end

function s = bash_quote_arg_local(a)
a = char(string(a));
s = ['''' strrep(a, '''', '''"'"''') ''''];
end

function s = ternary_str_local(tf)
if tf
    s = '1';
else
    s = '0';
end
end

function [tf, distro, linuxPath] = wsl_unc_to_linux_local(p)
p = char(string(p));
p = strrep(p, '/', '\\');
linuxPath = '';
distro = '';
tf = false;

prefixes = {'\\wsl.localhost\\', '\\wsl$\\'};
matchPrefix = '';
for k = 1:numel(prefixes)
    pref = prefixes{k};
    if strncmpi(p, pref, length(pref))
        matchPrefix = pref;
        break;
    end
end
if isempty(matchPrefix)
    return;
end
rest = p(length(matchPrefix)+1:end);
parts = regexp(rest, '\\', 'split');
if isempty(parts) || isempty(parts{1})
    return;
end
distro = parts{1};
if numel(parts) == 1
    linuxPath = '/';
else
    linuxPath = ['/' strjoin(parts(2:end), '/')];
end
tf = true;
end

function v = getfield_if_exists(s, name, defaultValue)
if isfield(s, name)
    v = s.(name);
else
    v = defaultValue;
end
end

function name = exe_name_local(base)
if ispc
    name = [base '.exe'];
else
    name = base;
end
end

function tf = is_wsl_unc_path(p)
[tf, ~, ~] = wsl_unc_to_linux_local(p);
end
