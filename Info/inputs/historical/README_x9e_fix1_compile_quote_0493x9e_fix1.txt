0493x9e-fix1 -- compile quote correction
========================================

Problem fixed
-------------
The x9e runtime banner contained a literal source newline inside a C/C++
string at cuda_classic_src_io_resident_0263.cu around lines 5792-5793.
This caused nvcc errors: missing closing quote / expected ')'.

For a worktree where x9e is ALREADY APPLIED (recommended for current state):

  git apply --check x9e_fix1_compile_quote_after_x9e.patch
  git apply x9e_fix1_compile_quote_after_x9e.patch

Then rebuild normally.

The *_corrected.patch files are corrected full x9e patch variants for future
clean applications from x9d-fix1 or x9c. No physics or performance logic is
changed by this fix; only the diagnostic string literal is repaired.
