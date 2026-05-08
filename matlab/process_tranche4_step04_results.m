function out = process_tranche4_step04_results(prepOrWorkdir)
%PROCESS_TRANCHE4_STEP04_RESULTS Read tranche 4 outputs and inspect them.

if nargin < 1 || isempty(prepOrWorkdir)
    prepOrWorkdir = '.';
end

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
    workdir = prep.workdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    matPath = fullfile(workdir, 'prep_tranche4_step04.mat');
    assert(exist(matPath, 'file') == 2, 'Cannot find %s.', matPath);
    tmp = load(matPath, 'prep');
    prep = tmp.prep;
else
    error('Unsupported input type for prepOrWorkdir.');
end

prefix = prep.outPrefix;
Sout = read_state_bin(prefix, prep.params.n, true, true);
xOut = Sout.x;
vOut = Sout.v;
Gref = read_cellfields_bin([prefix '_cellfields_ref.bin']);
Gred = read_cellfields_bin([prefix '_cellfields_red.bin']);
Grepair = read_cellfields_bin([prefix '_cellfields_repaired.bin']);
Gout = read_cellfields_bin([prefix '_cellfields_out.bin']);
Praw = read_f64_grid_bin([prefix '_pdrive_raw.bin']);
Psmooth = read_f64_grid_bin([prefix '_pdrive.bin']);
duRepairX = read_f64_grid_bin([prefix '_durepairx.bin']);
duRepairY = read_f64_grid_bin([prefix '_durepairy.bin']);
duEOSX = read_f64_grid_bin([prefix '_dueosx.bin']);
duEOSY = read_f64_grid_bin([prefix '_dueosy.bin']);
mask = read_i32_grid_bin([prefix '_interzone_mask.bin']);
M = read_params_kv([prefix '_runout.kv']);

stats = compare_step04_liquid_closure(prep, Gref, Gred, Grepair, Gout, Praw, Psmooth, duRepairX, duRepairY, duEOSX, duEOSY, M, xOut, vOut);

out = struct();
out.prep = prep;
out.xOut = xOut;
out.vOut = vOut;
out.Gref = Gref;
out.Gred = Gred;
out.Grepair = Grepair;
out.Gout = Gout;
out.Praw = Praw;
out.Psmooth = Psmooth;
out.duRepairX = duRepairX;
out.duRepairY = duRepairY;
out.duEOSX = duEOSX;
out.duEOSY = duEOSY;
out.runout = M;
out.mask = mask;
out.stats = stats;

fprintf('\n=== process_tranche4_step04_results ===\n');
fprintf('workdir       : %s\n', workdir);
fprintf('state out     : %s\n', prefix);
fprintf('runout file   : %s\n', [prefix '_runout.kv']);
fprintf('cell ref      : %s\n', [prefix '_cellfields_ref.bin']);
fprintf('cell red      : %s\n', [prefix '_cellfields_red.bin']);
fprintf('cell repaired : %s\n', [prefix '_cellfields_repaired.bin']);
fprintf('cell out      : %s\n', [prefix '_cellfields_out.bin']);
fprintf('=======================================\n');
end
