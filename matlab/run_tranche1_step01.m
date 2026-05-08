function out = run_tranche1_step01(params, x, v, varargin)
%RUN_TRANCHE1_STEP01 Orchestrate tranche 1 MATLAB <-> C++ execution.
%
% out = run_tranche1_step01(params, x, v)
% out = run_tranche1_step01(params, x, v, 'type', type, 'r0', r0, ...
%     'exePath', exePath, 'workdir', workdir, 'prefixIn', prefixIn, ...
%     'prefixOut', prefixOut, 'compareAfter', true)
%
% Required:
%   params : struct compatible with write_params_kv
%   x, v   : n x 2 particle arrays
%
% Optional name-value pairs:
%   'type'         : uint8 vector, length n
%   'r0'           : n x 2 array
%   'exePath'      : path to main_step01_stream_bc_collision executable
%   'workdir'      : directory for params/state/output files
%   'prefixIn'     : basename for input dumps within workdir
%   'prefixOut'    : basename for output dumps within workdir
%   'compareAfter' : logical, default true
%
% This function writes params/state dumps, runs the C++ executable,
% then optionally reads and compares the outputs.

p = inputParser;
p.addParameter('type', [], @(z) isempty(z) || isa(z,'uint8') || isnumeric(z));
p.addParameter('r0', [], @(z) isempty(z) || (isnumeric(z) && size(z,2)==2));
p.addParameter('exePath', '', @(s) ischar(s) || isstring(s));
p.addParameter('workdir', '', @(s) ischar(s) || isstring(s));
p.addParameter('prefixIn', 'state_in', @(s) ischar(s) || isstring(s));
p.addParameter('prefixOut', 'state_out', @(s) ischar(s) || isstring(s));
p.addParameter('compareAfter', true, @(b) islogical(b) || isnumeric(b));
p.parse(varargin{:});
opt = p.Results;

assert(size(x,2)==2, 'x must be n x 2');
assert(size(v,2)==2, 'v must be n x 2');
assert(size(x,1)==size(v,1), 'x and v must have same number of rows');
assert(isfield(params,'n'), 'params.n must exist');
assert(params.n==size(x,1), 'params.n must equal size(x,1)');

if isempty(opt.workdir)
    workdir = fullfile(tempdir, 'tranche1_step01_run');
else
    workdir = char(opt.workdir);
end
if ~exist(workdir, 'dir')
    mkdir(workdir);
end

if isempty(opt.exePath)
    thisFile = mfilename('fullpath');
    matlabDir = fileparts(thisFile);
    trancheRoot = fileparts(matlabDir);
    defaultExe = fullfile(trancheRoot, 'build', 'main_step01_stream_bc_collision');
    if ispc
        defaultExe = [defaultExe '.exe'];
    end
    exePath = defaultExe;
else
    exePath = char(opt.exePath);
end
assert(exist(exePath, 'file')==2, 'Executable not found: %s', exePath);

prefixIn = char(opt.prefixIn);
prefixOut = char(opt.prefixOut);

paramsPath = fullfile(workdir, 'params.kv');
stateInPrefix = fullfile(workdir, prefixIn);
stateOutPrefix = fullfile(workdir, prefixOut);

hasType = ~isempty(opt.type);
hasR0 = ~isempty(opt.r0);

if hasType
    type = uint8(opt.type(:));
else
    type = [];
end
if hasR0
    r0 = opt.r0;
else
    r0 = [];
end

write_params_kv(params, paramsPath);
write_state_bin(stateInPrefix, x, v, type, r0);

if hasType
    typePath = [stateInPrefix '_type.bin'];
else
    typePath = fullfile(workdir, 'dummy_type.bin');
    fid = fopen(typePath, 'w'); fclose(fid);
end
if hasR0
    r0Path = [stateInPrefix '_r0.bin'];
else
    r0Path = fullfile(workdir, 'dummy_r0.bin');
    fid = fopen(r0Path, 'w'); fclose(fid);
end

xPath = [stateInPrefix '_x.bin'];
vPath = [stateInPrefix '_v.bin'];

cmd = strjoin({ ...
    quote_arg(exePath), ...
    quote_arg(paramsPath), ...
    quote_arg(xPath), ...
    quote_arg(vPath), ...
    quote_arg(typePath), ...
    quote_arg(r0Path), ...
    quote_arg(stateOutPrefix), ...
    ternary_str(hasType), ...
    ternary_str(hasR0)}, ' ');

fprintf('\n=== run_tranche1_step01 ===\n');
fprintf('workdir   : %s\n', workdir);
fprintf('exePath   : %s\n', exePath);
fprintf('command   : %s\n', cmd);
[status, cmdout] = system(cmd);
fprintf('%s', cmdout);
assert(status==0, 'C++ executable failed with status %d.', status);

out = struct();
out.workdir = workdir;
out.exePath = exePath;
out.paramsPath = paramsPath;
out.stateInPrefix = stateInPrefix;
out.stateOutPrefix = stateOutPrefix;
out.command = cmd;
out.status = status;
out.cmdout = cmdout;
out.hasType = hasType;
out.hasR0 = hasR0;

if opt.compareAfter
    out.compare = compare_step01_stream_bc_collision(stateInPrefix, stateOutPrefix, params);
else
    out.Sout = read_state_bin(stateOutPrefix, params.n, hasType, hasR0);
    out.G = read_cellfields_bin([stateOutPrefix '_cellfields.bin']);
    out.runout = read_params_kv([stateOutPrefix '_runout.kv']);
end

fprintf('==========================\n');
end

function s = quote_arg(a)
a = char(string(a));
if ispc
    s = ['"' strrep(a, '"', '""') '"'];
else
    s = ['''' strrep(a, '''', '''"'"''') ''''];
end
end

function s = ternary_str(tf)
if tf
    s = '1';
else
    s = '0';
end
end
