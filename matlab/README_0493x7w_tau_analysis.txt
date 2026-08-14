0493x7w periodic Darcy-step analysis -- tau_H aligned revision
=============================================================

Purpose
-------
Correct the previous same-Ue comparison, which could pair physically different
convective ages because Ue(t) is non-monotone. This revision uses monotone
convective age tau_H = integral(Ue dt)/H and computes coherent recirculation and
vorticity from tau-window-averaged normalized velocity fields.

Files to copy into repository matlab/
-------------------------------------
  analyze_periodic_darcy_step_0493x7w.m
  run_periodic_darcy_step_analysis_0493x7w.m

Run from matlab/
----------------
  run('run_periodic_darcy_step_analysis_0493x7w.m')

No simulation is launched or modified.

Default coherent windows
------------------------
  tau_H = [1,3]
  tau_H = [4,6]
  tau_H = [7,9]

For each dump, u and v are first divided by that dump's incident Ue. The
normalized velocity fields are then averaged with tau_H Voronoi weights.
Only after this averaging are curl, divergence, interface transmission,
recirculation area and reattachment length computed.

New decision outputs
--------------------
  x7w_step_tau_aligned_0493x7w.csv
  x7w_step_pairwise_tau_aligned_0493x7w.csv
  x7w_step_tau_window_scalars_0493x7w.csv
  x7w_step_tau_window_fields_0493x7w.csv
  x7w_step_tau_window_pairwise_0493x7w.csv
  x7w_step_summary_0493x7w.csv

Figures
-------
  x7w_step_tau_aligned_ratios_0493x7w.png/pdf
  x7w_step_tau_window_ratios_0493x7w.png/pdf
  x7w_step_tau_window_fields_tau_1_3_0493x7w.png/pdf
  x7w_step_tau_window_fields_tau_4_6_0493x7w.png/pdf
  x7w_step_tau_window_fields_tau_7_9_0493x7w.png/pdf

The analyzer deletes legacy generated matched-Ue CSV/figures in the same
analysis directory to prevent accidental reuse of the invalid comparison.

Please return
-------------
1. the complete terminal block beginning
   "===== 0493x7w PERIODIC DARCY STEP ANALYSIS -- TAU-ALIGNED ====="
2. x7w_step_tau_window_fields_0493x7w.csv
3. x7w_step_tau_window_pairwise_0493x7w.csv
4. x7w_step_tau_window_ratios_0493x7w.png
5. the three x7w_step_tau_window_fields_tau_* PNGs

Validation performed here
-------------------------
Static consistency only: no MATLAB/Octave executable is installed in the
analysis environment, so the first execution in MATLAB remains the runtime
syntax/API validation.
