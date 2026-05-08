function out = process_tranche5_step05_results(prepOrWorkdir)
%PROCESS_TRANCHE5_STEP05_RESULTS Read tranche 5 outputs and inspect them.

if nargin < 1 || isempty(prepOrWorkdir)
    prepOrWorkdir = '.';
end

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
    workdir = prep.workdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    matPath = fullfile(workdir, 'prep_tranche5_step05.mat');
    assert(exist(matPath, 'file') == 2, 'Cannot find %s.', matPath);
    tmp = load(matPath, 'prep');
    prep = tmp.prep;
else
    error('Unsupported input type for prepOrWorkdir.');
end

prefix = prep.outPrefix;
Sref = read_state_bin([prefix '_ref'], prep.params.n, true, true);
Sbase = read_state_bin([prefix '_after_base'], prep.params.n, true, true);
Sred = read_state_bin([prefix '_red'], prep.params.n, true, true);
Sout = read_state_bin(prefix, prep.params.n, true, true);

Gref = read_cellfields_bin([prefix '_cellfields_ref.bin']);
Gbase = read_cellfields_bin([prefix '_cellfields_after_base.bin']);
Gred = read_cellfields_bin([prefix '_cellfields_red.bin']);
Gout = read_cellfields_bin([prefix '_cellfields_out.bin']);
Praw = read_f64_grid_bin([prefix '_pdrive_raw.bin']);
Psmooth = read_f64_grid_bin([prefix '_pdrive.bin']);
mask = read_i32_grid_bin([prefix '_interzone_mask.bin']);
zoneBase = read_i32_grid_bin([prefix '_zone_owner_base.bin']);
zoneShifted = read_i32_grid_bin([prefix '_zone_owner_shifted.bin']);
M = read_params_kv([prefix '_runout.kv']);

stats = compare_step05_full_step(prep, Sref, Sbase, Sred, Sout, Gref, Gbase, Gred, Gout, Praw, Psmooth, M);

out = struct();
out.prep = prep;
out.Sref = Sref;
out.Sbase = Sbase;
out.Sred = Sred;
out.Sout = Sout;
out.Gref = Gref;
out.Gbase = Gbase;
out.Gred = Gred;
out.Gout = Gout;
out.Praw = Praw;
out.Psmooth = Psmooth;
out.mask = mask;
out.zoneBase = zoneBase;
out.zoneShifted = zoneShifted;
out.runout = M;
out.stats = stats;

fprintf('\n=== process_tranche5_step05_results ===\n');
fprintf('workdir         : %s\n', workdir);
fprintf('state ref       : %s\n', [prefix '_ref']);
fprintf('state after base: %s\n', [prefix '_after_base']);
fprintf('state red       : %s\n', [prefix '_red']);
fprintf('state out       : %s\n', prefix);
fprintf('runout file     : %s\n', [prefix '_runout.kv']);
fprintf('zone owner base : %s\n', [prefix '_zone_owner_base.bin']);
fprintf('zone owner shft : %s\n', [prefix '_zone_owner_shifted.bin']);
fprintf('========================================\n');
end
