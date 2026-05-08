function out = run_tranche1_all_in_one(overrides)
%RUN_TRANCHE1_ALL_IN_ONE
% Script MATLAB tout-en-un pour la tranche 1 :
%  1) construit params
%  2) construit un etat initial ad hoc x,v,type,r0
%  3) ecrit les dumps d'entree
%  4) lance l'executable C++ step01
%  5) relit les sorties
%  6) lance la comparaison MATLAB
%
% Usage minimal:
%   out = run_tranche1_all_in_one();
%
% Avec surcharges:
%   out = run_tranche1_all_in_one(struct('Nx',64,'Ny',64,'gamma',20));
%
% Remarques:
% - Ce script doit etre place dans le meme dossier que les scripts utilitaires
%   build_tranche1_params, build_ad_hoc_state_uniform, run_tranche1_step01, etc.
% - L'executable C++ est suppose se trouver dans ../build/

if nargin < 1 || isempty(overrides)
    overrides = struct();
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('overrides doit etre un struct scalaire ou vide.');
end

thisFile = mfilename('fullpath');
thisDir  = fileparts(thisFile);
addpath(thisDir);

% Localisation par defaut de l'executable compile
exeDefault = fullfile(thisDir, '..', 'build', exe_name_local('main_step01_stream_bc_collision'));

% Construction params a partir des surcharges utilisateur
paramsOverrides = overrides;

% Certains champs sont interpretes comme options runtime de l'orchestrateur
runtimeFields = {'workdir','exePath','prefixIn','prefixOut','compareAfter','seed'};
for k = 1:numel(runtimeFields)
    f = runtimeFields{k};
    if isfield(paramsOverrides, f)
        paramsOverrides = rmfield(paramsOverrides, f);
    end
end

params = build_tranche1_params(paramsOverrides);

% Options runtime
workdir = getfield_if_exists(overrides, 'workdir', fullfile(pwd, 'run_tranche1_all_in_one')); %#ok<GFLD>
exePath = getfield_if_exists(overrides, 'exePath', exeDefault); %#ok<GFLD>
prefixIn = getfield_if_exists(overrides, 'prefixIn', 'state_in'); %#ok<GFLD>
prefixOut = getfield_if_exists(overrides, 'prefixOut', 'state_out'); %#ok<GFLD>
compareAfter = logical(getfield_if_exists(overrides, 'compareAfter', true)); %#ok<GFLD>
seed = getfield_if_exists(overrides, 'seed', 1); %#ok<GFLD>

% Etat initial ad hoc
[x, v, type, r0] = build_ad_hoc_state_uniform(params, 'seed', seed);

% Execution complete tranche 1
out = run_tranche1_step01(params, x, v, ...
    'type', type, ...
    'r0', r0, ...
    'exePath', exePath, ...
    'workdir', workdir, ...
    'prefixIn', prefixIn, ...
    'prefixOut', prefixOut, ...
    'compareAfter', compareAfter);

% Champs utilitaires supplementaires
out.params = params;
out.x0 = x;
out.v0 = v;
out.type0 = type;
out.r00 = r0;
out.exePath = exePath;
out.workdir = workdir;

fprintf('\n=== run_tranche1_all_in_one termine ===\n');
fprintf('Repertoire de travail : %s\n', workdir);
fprintf('Executable            : %s\n', exePath);
fprintf('n particules          : %d\n', size(x,1));
fprintf('Nx x Ny               : %d x %d\n', params.Nx, params.Ny);
fprintf('=====================================\n');

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
