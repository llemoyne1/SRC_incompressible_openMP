function out = validate_poiseuille_q6_channel_long(varargin)
%VALIDATE_POISEUILLE_Q6_CHANNEL_LONG Compare long classic and Q6 channel Poiseuille runs.
%
% Run from the matlab/ directory after launching the C++ examples from the repo root:
%
%   out = validate_poiseuille_q6_channel_long('makePlots', true);
%
% This is a thin wrapper around validate_poiseuille_q6_channel_short with long
% run directories and a stationarity-oriented default fit window.

p = inputParser;
p.FunctionName = 'validate_poiseuille_q6_channel_long';
addParameter(p, 'classicRunDir', '../runs/poiseuille_y_classic_solid_thermal_long', @(s) ischar(s) || isstring(s));
addParameter(p, 'q6RunDir', '../runs/poiseuille_y_q6_solid_thermal_long', @(s) ischar(s) || isstring(s));
addParameter(p, 'fitStartFraction', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x < 1);
addParameter(p, 'excludeWallCells', 3, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'frameStride', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

out = validate_poiseuille_q6_channel_short( ...
    'classicRunDir', char(string(opt.classicRunDir)), ...
    'q6RunDir', char(string(opt.q6RunDir)), ...
    'fitStartFraction', opt.fitStartFraction, ...
    'excludeWallCells', opt.excludeWallCells, ...
    'frameStride', opt.frameStride, ...
    'makePlots', logical(opt.makePlots));

fprintf('\n=== Long Poiseuille Q6-channel validation defaults ===\n');
fprintf('classicRunDir     : %s\n', char(string(opt.classicRunDir)));
fprintf('q6RunDir          : %s\n', char(string(opt.q6RunDir)));
fprintf('fitStartFraction  : %.6g\n', opt.fitStartFraction);
fprintf('excludeWallCells  : %.6g\n', opt.excludeWallCells);
fprintf('====================================================\n\n');
end
