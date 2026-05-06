Benchmark Poiseuille OpenMP profilé avec décomposition fine de la passe shifted.

Fichiers principaux :
- build/main_benchmark_poiseuille_openmp_profiled_shifted_profiled
- matlab/prepare_benchmark_poiseuille_equal_openmp_profiled_shifted_run_simple.m

Nouveaux champs runout :
- timeBaseLayout, timeBaseExtract, timeBaseSnapshot, timeBaseAlloc, timeBaseKernel, timeBasePack, timeBaseMerge
- timeShiftedLayout, timeShiftedExtract, timeShiftedSnapshot, timeShiftedAlloc, timeShiftedKernel, timeShiftedPack, timeShiftedMerge
- fractions associées fracBase* et fracShifted*
