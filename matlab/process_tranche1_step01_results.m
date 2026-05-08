function out = process_tranche1_step01_results(prepOrWorkdir, varargin)
%PROCESS_TRANCHE1_STEP01_RESULTS
% Read tranche 1 step01 outputs after manual execution of the C++ program.
%
% Usage:
%   out = process_tranche1_step01_results(prep);
%   out = process_tranche1_step01_results(workdir);
%
% Optional:
%   out = process_tranche1_step01_results(..., 'compareAfter', true);

p = inputParser;
p.addParameter('compareAfter', true, @(b) islogical(b) || isnumeric(b));
p.parse(varargin{:});
opt = p.Results;

if isstruct(prepOrWorkdir)
    prep = prepOrWorkdir;
elseif ischar(prepOrWorkdir) || isstring(prepOrWorkdir)
    workdir = char(string(prepOrWorkdir));
    prepFile = fullfile(workdir, 'prep_tranche1_step01.mat');
    assert(exist(prepFile, 'file')==2, 'Fichier prep introuvable: %s', prepFile);
    S = load(prepFile, 'prep');
    prep = S.prep;
else
    error('prepOrWorkdir doit etre une struct prep ou un repertoire de travail.');
end

runoutFile = [prep.stateOutPrefix '_runout.kv'];
cellFile   = [prep.stateOutPrefix '_cellfields.bin'];
xFile      = [prep.stateOutPrefix '_x.bin'];
vFile      = [prep.stateOutPrefix '_v.bin'];

assert(exist(runoutFile, 'file')==2, 'Fichier runout introuvable: %s', runoutFile);
assert(exist(cellFile, 'file')==2, 'Fichier cellfields introuvable: %s', cellFile);
assert(exist(xFile, 'file')==2, 'Fichier x de sortie introuvable: %s', xFile);
assert(exist(vFile, 'file')==2, 'Fichier v de sortie introuvable: %s', vFile);

out = struct();
out.prep = prep;
out.Sout = read_state_bin(prep.stateOutPrefix, prep.params.n, prep.hasType, prep.hasR0);
out.G = read_cellfields_bin(cellFile);
out.runout = read_params_kv(runoutFile);

if opt.compareAfter
    out.compare = compare_step01_stream_bc_collision(prep.stateInPrefix, prep.stateOutPrefix, prep.params);
end

fprintf('\n=== process_tranche1_step01_results ===\n');
fprintf('workdir     : %s\n', prep.workdir);
fprintf('state out   : %s\n', prep.stateOutPrefix);
fprintf('runout file : %s\n', runoutFile);
fprintf('cellfields  : %s\n', cellFile);
fprintf('=======================================\n');
end
