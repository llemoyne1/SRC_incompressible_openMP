function out = process_benchmark_poiseuille_1500_results(prepOrWorkdir)
%PROCESS_BENCHMARK_POISEUILLE_1500_RESULTS Read benchmark outputs and plot metrics.
if nargin < 1 || isempty(prepOrWorkdir)
    prepOrWorkdir = '.';
end

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
    workdir = prep.workdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    matPath = fullfile(workdir, 'prep_benchmark_poiseuille_1500.mat');
    assert(exist(matPath, 'file') == 2, 'Cannot find %s.', matPath);
    tmp = load(matPath, 'prep');
    prep = tmp.prep;
else
    error('Unsupported input type for prepOrWorkdir.');
end

prefix = prep.outPrefix;
metricsPath = [prefix '_metrics.csv'];
runoutPath = [prefix '_runout.kv'];
assert(exist(metricsPath,'file')==2, 'Cannot find %s.', metricsPath);
assert(exist(runoutPath,'file')==2, 'Cannot find %s.', runoutPath);

M = readtable(metricsPath);
R = read_params_kv(runoutPath);
steps = prep.dumpSteps;
Snaps = struct();
for k = 1:numel(steps)
    step = steps(k);
    sfx = sprintf('%s_step%04d', prefix, step);
    Snaps(k).step = step; %#ok<AGROW>
    Snaps(k).state = read_state_bin(sfx, prep.params.n, true, true); %#ok<AGROW>
    Snaps(k).cell = read_cellfields_bin([sfx '_cellfields.bin']); %#ok<AGROW>
end

stats = compare_benchmark_poiseuille_1500(prep, M, Snaps, R);

out = struct();
out.prep = prep;
out.metrics = M;
out.runout = R;
out.snapshots = Snaps;
out.stats = stats;

fprintf('\n=== process_benchmark_poiseuille_1500_results ===\n');
fprintf('workdir       : %s\n', workdir);
fprintf('metrics file  : %s\n', metricsPath);
fprintf('runout file   : %s\n', runoutPath);
fprintf('dump steps    : %s\n', prep.params.benchmark_dumpSteps);
fprintf('===============================================\n');
end
