function out = process_tranche2_step02_results(prepOrWorkdir, varargin)
%PROCESS_TRANCHE2_STEP02_RESULTS Read tranche 2 outputs after manual execution.

p = inputParser;
p.addParameter('compareAfter', true, @(b) islogical(b) || isnumeric(b));
p.parse(varargin{:});
opt = p.Results;

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    prepFile = fullfile(workdir, 'prep_tranche2_step02.mat');
    assert(exist(prepFile, 'file')==2, 'Fichier prep introuvable: %s', prepFile);
    S = load(prepFile, 'prep');
    prep = S.prep;
else
    error('prepOrWorkdir doit etre une struct prep ou un repertoire de travail.');
end

runoutFile = [prep.stateOutPrefix '_runout.kv'];
GbeforeFile = [prep.stateOutPrefix '_cellfields_before.bin'];
GafterFile = [prep.stateOutPrefix '_cellfields_after.bin'];
zoneFile = [prep.stateOutPrefix '_zone_owner.bin'];
xFile = [prep.stateOutPrefix '_x.bin'];
vFile = [prep.stateOutPrefix '_v.bin'];

assert(exist(runoutFile, 'file')==2, 'Fichier runout introuvable: %s', runoutFile);
assert(exist(GbeforeFile, 'file')==2, 'Fichier cellfields before introuvable: %s', GbeforeFile);
assert(exist(GafterFile, 'file')==2, 'Fichier cellfields after introuvable: %s', GafterFile);
assert(exist(zoneFile, 'file')==2, 'Fichier zone owner introuvable: %s', zoneFile);
assert(exist(xFile, 'file')==2, 'Fichier x de sortie introuvable: %s', xFile);
assert(exist(vFile, 'file')==2, 'Fichier v de sortie introuvable: %s', vFile);

out = struct();
out.prep = prep;
out.Sout = read_state_bin(prep.stateOutPrefix, prep.params.n, prep.hasType, prep.hasR0);
out.Gbefore = read_cellfields_bin(GbeforeFile);
out.Gafter = read_cellfields_bin(GafterFile);
out.zoneOwner = read_i32_grid_bin(zoneFile);
out.runout = read_params_kv(runoutFile);
if opt.compareAfter
    out.compare = compare_step02_zone_pass(prep.stateInPrefix, prep.stateOutPrefix, prep.params);
end

fprintf('\n=== process_tranche2_step02_results ===\n');
fprintf('workdir      : %s\n', prep.workdir);
fprintf('state out    : %s\n', prep.stateOutPrefix);
fprintf('runout file  : %s\n', runoutFile);
fprintf('cell before  : %s\n', GbeforeFile);
fprintf('cell after   : %s\n', GafterFile);
fprintf('zone owner   : %s\n', zoneFile);
fprintf('=======================================\n');

figure('Name','tranche2_zone_owner');
imagesc(out.zoneOwner.data); axis equal tight; set(gca,'YDir','normal'); colorbar;
title(sprintf('zone owner map (%s)', prep.layoutMode));
end
