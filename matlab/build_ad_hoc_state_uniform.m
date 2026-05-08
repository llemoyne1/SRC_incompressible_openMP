function [x, v, type, r0] = build_ad_hoc_state_uniform(params, varargin)
%BUILD_AD_HOC_STATE_UNIFORM
% Etat initial simple pour tester la tranche 1 C++.
% - positions uniformes dans [0,Lx]x[0,Ly]
% - vitesses gaussiennes isotropes de variance kBT
% - retrait optionnel de la vitesse moyenne
%
% Usage:
%   [x,v,type,r0] = build_ad_hoc_state_uniform(params)
%   [x,v,type,r0] = build_ad_hoc_state_uniform(params,'seed',1,'removeMean',true)

p = inputParser;
p.addParameter('seed', [], @(z) isempty(z) || isscalar(z));
p.addParameter('removeMean', true, @(z) islogical(z) || isnumeric(z));
p.parse(varargin{:});
opt = p.Results;

if ~isempty(opt.seed)
    rng(opt.seed);
end

n = params.n;
Lx = params.Lx;
Ly = params.Ly;
kBT = params.kBT;

x = zeros(n,2);
x(:,1) = Lx * rand(n,1);
x(:,2) = Ly * rand(n,1);

sigma = sqrt(kBT);
v = sigma * randn(n,2);

if logical(opt.removeMean)
    v(:,1) = v(:,1) - mean(v(:,1));
    v(:,2) = v(:,2) - mean(v(:,2));
end

type = zeros(n,1,'uint8');
r0 = x;
end
