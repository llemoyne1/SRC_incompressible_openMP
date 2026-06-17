%RUN_TOPO_WAKE_DENSITY_0358 Example launcher for wake-density diagnostics.
% Edit runRoot before running from MATLAB.

runRoot = 'runs/topo_vk_0356f_darcy5000_matched';
outputDir = fullfile(runRoot, 'analysis');

[T,S] = analyze_topo_wake_density_0358(runRoot, ...
    'OutputDir', outputDir, ...
    'MakePlots', true, ...
    'ShowFigures', true);

disp(S)
