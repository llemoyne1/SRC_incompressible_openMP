%RUN_TOPO_NACA_REFERENCE_COMPARISON_0354 Interactive MATLAB driver.
%
% Run from MATLAB after setting the repository root as current directory, or let
% this script infer it from its own location.

thisFile = mfilename('fullpath');
thisDir = fileparts(thisFile);
repoRoot = fileparts(fileparts(thisDir));
cd(repoRoot);
addpath(genpath('matlab'));

proxyCsv = fullfile('runs','topo_darcy_naca_re_sweep_0353','naca_re_polar_proxy_0353.csv');
referenceCsv = fullfile('data','reference','naca0012_ladson_re6e6_reference_0354.csv');
outDir = fullfile('runs','topo_matlab_plots_0354');

C = plot_topo_naca_reference_comparison_0354(proxyCsv, ...
    'ReferenceCsv', referenceCsv, ...
    'OutputDir', outDir, ...
    'ShowFigures', true);

disp(C);
