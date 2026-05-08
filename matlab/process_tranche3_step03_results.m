function out = process_tranche3_step03_results(prepOrWorkdir, varargin)
%PROCESS_TRANCHE3_STEP03_RESULTS Read tranche 3 outputs after manual execution.
p = inputParser;
p.addParameter('compareAfter', true, @(b) islogical(b) || isnumeric(b));
p.parse(varargin{:});
opt = p.Results;

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    prepFile = fullfile(workdir, 'prep_tranche3_step03.mat');
    assert(exist(prepFile, 'file')==2, 'Fichier prep introuvable: %s', prepFile);
    S = load(prepFile, 'prep');
    prep = S.prep;
else
    error('prepOrWorkdir doit etre une struct prep ou un repertoire de travail.');
end

runoutFile = [prep.stateOutPrefix '_runout.kv'];
baseBeforeFile = [prep.stateOutPrefix '_cellfields_before_base.bin'];
baseAfterFile = [prep.stateOutPrefix '_cellfields_after_base.bin'];
shiftBeforeFile = [prep.stateOutPrefix '_cellfields_before_shifted.bin'];
shiftAfterFile = [prep.stateOutPrefix '_cellfields_after_shifted.bin'];
zoneBaseFile = [prep.stateOutPrefix '_zone_owner_base.bin'];
zoneShiftFile = [prep.stateOutPrefix '_zone_owner_shifted.bin'];
xFile = [prep.stateOutPrefix '_x.bin'];
vFile = [prep.stateOutPrefix '_v.bin'];
basePrefix = [prep.stateOutPrefix '_after_base'];

req = {runoutFile,baseBeforeFile,baseAfterFile,shiftBeforeFile,shiftAfterFile,zoneBaseFile,zoneShiftFile,xFile,vFile,[basePrefix '_x.bin'],[basePrefix '_v.bin']};
for i=1:numel(req)
    assert(exist(req{i},'file')==2, 'Fichier introuvable: %s', req{i});
end

out = struct();
out.prep = prep;
out.Sbase = read_state_bin(basePrefix, prep.params.n, prep.hasType, prep.hasR0);
out.Sout = read_state_bin(prep.stateOutPrefix, prep.params.n, prep.hasType, prep.hasR0);
out.GbeforeBase = read_cellfields_bin(baseBeforeFile);
out.GafterBase = read_cellfields_bin(baseAfterFile);
out.GbeforeShift = read_cellfields_bin(shiftBeforeFile);
out.GafterShift = read_cellfields_bin(shiftAfterFile);
out.zoneOwnerBase = read_i32_grid_bin(zoneBaseFile);
out.zoneOwnerShift = read_i32_grid_bin(zoneShiftFile);
out.runout = read_params_kv(runoutFile);
if opt.compareAfter
    out.compare = compare_step03_double_zone_pass(prep.stateInPrefix, basePrefix, prep.stateOutPrefix, prep.params);
end

fprintf('\n=== process_tranche3_step03_results ===\n');
fprintf('workdir        : %s\n', prep.workdir);
fprintf('state after base : %s\n', basePrefix);
fprintf('state out      : %s\n', prep.stateOutPrefix);
fprintf('runout file    : %s\n', runoutFile);
fprintf('zone owner base: %s\n', zoneBaseFile);
fprintf('zone owner shft: %s\n', zoneShiftFile);
fprintf('=======================================\n');

figure('Name','tranche3_zone_owner');
subplot(1,2,1); imagesc(out.zoneOwnerBase.data); axis equal tight; set(gca,'YDir','normal'); colorbar; title('zone owner map (base)');
subplot(1,2,2); imagesc(out.zoneOwnerShift.data); axis equal tight; set(gca,'YDir','normal'); colorbar; title('zone owner map (shifted)');
end
