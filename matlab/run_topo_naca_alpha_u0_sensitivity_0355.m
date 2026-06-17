%RUN_TOPO_NACA_ALPHA_U0_SENSITIVITY_0355 Interactive MATLAB driver.

cd('/mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO')
addpath(genpath('matlab'))

combinedCsv = 'runs/topo_darcy_naca_alpha_u0_sweep_0355/naca_alpha_u0_sweep_0355_combined.csv';
T = plot_topo_naca_alpha_u0_sensitivity_0355(combinedCsv, ...
    'OutputDir', 'runs/topo_matlab_plots_0355', ...
    'ShowFigures', true);

disp(T);
