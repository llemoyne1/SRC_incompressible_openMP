# Curation V4.43 — 0493x19d hot-path diagnostic cleanup

Date: 2026-09-18

## Scope

Performance-only cleanup before the systematic SRC / Q6-g-f fluid-characterization campaign.
No physical operator, parameter, ordering, numerical tolerance, FSI law, Q6 closure,
collision rule, thermostat rule, boundary condition, resampling rule, or output produced by
an explicitly enabled diagnostic is changed.

## Audit finding 1 — x19b-fix3 complete angular audit

`FullAngularAudit0493x19bFix3` is instantiated once per solver timestep.  Before this
cleanup, even with `MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=0`, construction copied
`params.outputDir` and unconditionally executed `stages_.reserve(20)`.  The latter may
allocate/free heap storage every timestep although the diagnostic is disabled.

The cleanup:

- caches the process-level x19b-fix3 diagnostic flag once;
- returns from construction immediately when the diagnostic is disabled;
- copies the rotation center and output directory only when enabled;
- reserves the 20-stage buffer only when enabled.

When `MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=1` and the prescribed-rotation preconditions are
met, the same stage captures and CSV output remain active.

## Audit finding 2 — CUDA resident phase profiler

All overloads of `record_cuda_resident_profile_0266()` previously built a profile row before
the existing accumulator checked `cuda_resident_profile_0266_enabled()`.  This created and
assigned diagnostic `std::string` values (`mode`, `phase`) and copied `outputDir` even when
resident profiling was disabled.  Long mode names can require heap allocation.

The cleanup adds an immediate guard at the beginning of each overload.  With
`MPCD_CUDA_RESIDENT_PROFILE_0266=0` (and internal profiling disabled), no profile row or
output-path copy is performed.  With profiling enabled, the original path and CSV content
are preserved.

## FSI scope decision

The x19c free-rotor mechanical accumulator and remaining FSI-only reaction bookkeeping are
not modified.  They are outside the bulk SRC / Q6-g-f characterization hot path and some are
part of the qualified solid mechanics.  This patch deliberately avoids changing them.

## Verification performed on the snapshot

- `g++ -std=c++17 -fsyntax-only -Iinclude src/src_mpcd_base.cpp`: PASS.
- Static inspection confirms that the x19b-fix3 GPU reductions and host synchronization
  remain behind the explicit audit flag.
- Static inspection confirms that the new resident-profile guards precede construction of
  profile-row strings.
- No solver parameter defaults were changed.

A CUDA build and timing comparison must still be performed in the real repository with the
project NVCC toolchain.  Performance claims should be based on that benchmark, not on this
static audit alone.
