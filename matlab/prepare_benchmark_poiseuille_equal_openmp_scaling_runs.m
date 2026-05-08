function batch = prepare_benchmark_poiseuille_equal_openmp_scaling_runs(overrides)
% Prepare several OpenMP Poiseuille benchmark runs for scaling studies.
% Default thread counts: [1 2 4 8 12 15 20]

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
assert(isstruct(overrides) && isscalar(overrides), 'overrides must be a scalar struct.');

if ~isfield(overrides,'threadCounts') || isempty(overrides.threadCounts)
    overrides.threadCounts = [1 2 4 8 12 15 20];
end
threadCounts = overrides.threadCounts(:)';

if ~isfield(overrides,'rootWorkdir') || isempty(overrides.rootWorkdir)
    overrides.rootWorkdir = fullfile(pwd, 'run_benchmark_poiseuille_equal_openmp_scaling');
end
rootWorkdir = overrides.rootWorkdir;
if ~exist(rootWorkdir, 'dir')
    mkdir(rootWorkdir);
end

singleOverrides = overrides;
for f = {'threadCounts','rootWorkdir'}
    if isfield(singleOverrides, f{1})
        singleOverrides = rmfield(singleOverrides, f{1});
    end
end

% Use a cell array first because the returned prep structs may carry
% additional fields that do not match an empty struct.
runsCell = cell(1, numel(threadCounts));
for k = 1:numel(threadCounts)
    nt = threadCounts(k);
    ov = singleOverrides;
    ov.nThreads = nt;
    ov.workdir = fullfile(rootWorkdir, sprintf('threads_%02d', nt));
    runsCell{k} = prepare_benchmark_poiseuille_equal_openmp_run_simple_fixed(ov);
end

% Convert to a struct array once the field set is known.
runs = [runsCell{:}];

masterScriptPath = fullfile(rootWorkdir, 'run_all_openmp_scaling.sh');
fid = fopen(masterScriptPath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', masterScriptPath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '#!/usr/bin/env bash\n');
fprintf(fid, 'set -euo pipefail\n');
for k = 1:numel(runs)
    sh = to_linux_path_local(fullfile(runs(k).workdir, 'run_benchmark_poiseuille_equal_openmp.sh'));
    fprintf(fid, 'echo "===== threads %d ====="\n', runs(k).nThreads);
    fprintf(fid, 'bash "%s"\n', sh);
end

batch = struct();
batch.threadCounts = threadCounts;
batch.rootWorkdir = rootWorkdir;
batch.runs = runs;
batch.masterScriptPath = masterScriptPath;
batch.masterScriptLinux = to_linux_path_local(masterScriptPath);
save(fullfile(rootWorkdir, 'prep_benchmark_poiseuille_openmp_scaling.mat'), 'batch');

fprintf('\n=== prepare_benchmark_poiseuille_equal_openmp_scaling_runs_fixed ===\n');
fprintf('rootWorkdir      : %s\n', rootWorkdir);
fprintf('threadCounts     : %s\n', mat2str(threadCounts));
fprintf('master script    : %s\n', masterScriptPath);
fprintf('master script WSL: %s\n', batch.masterScriptLinux);
fprintf('commande WSL     : bash %s\n', batch.masterScriptLinux);
fprintf('===============================================================\n');
end

function p = to_linux_path_local(a)
p = char(string(a));
if startsWith(p,'/')
    p = strrep(p,'\','/');
    p = regexprep(p,'/+','/');
    return;
end
m = regexp(p, '([^\]+)\(.*)$', 'tokens', 'once');
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

