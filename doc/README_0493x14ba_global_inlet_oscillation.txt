0493x14ba — global periodic inlet-velocity oscillation
=====================================================

Purpose
-------
Add one global sinusoidal modulation to all inlet velocities and to every
matching Q6 open-boundary flux target, without overloading the existing startup
ramp semantics.

The effective multiplier is

  F(t) = F_ramp(t) * F_osc(t)

with

  F_osc(t) = 1                                              for t_eff < t_start
             1 + A sin(2*pi*(t_eff-t_start)/T + phi)        otherwise

  t_eff = t + t_offset.

Parameters
----------
Canonical .kv keys:

  inletVelocityOscillationEnable      = false
  inletVelocityOscillationAmplitude   = 0.0
  inletVelocityOscillationPeriod      = 1.0
  inletVelocityOscillationPhase       = 0.0
  inletVelocityOscillationStartTime   = 0.0
  inletVelocityOscillationTimeOffset  = 0.0

Short aliases with inletOscillation* are accepted for all six keys.

Amplitude is a dimensionless relative velocity amplitude and is constrained to
0 <= A <= 1.  This prevents a segment declared as an inlet from silently
reversing direction.  Period must be finite and strictly positive when the
oscillation is enabled.  Phase is in radians and all times use solver time units.

Scope
-----
The factor is deliberately global: every active inlet face or inlet segment gets
the same factor.  Spatial profiles remain independent and are multiplied after
the temporal factor exactly as before.

The implementation covers the same paths that already consume the historical
inlet ramp:

  * CPU/open-boundary particle path: src/boundary_base.cpp
  * CPU Q6 projection adapter:       src/q6_projection_adapter.cpp
  * CUDA classic resident IO:        src/cuda_classic_src_io_resident_0263.cu
  * CUDA Q6 resident flux path:       src/cuda_q6_resident_0400.cu

With inletVelocityOscillationEnable=false, the new multiplier is exactly 1.0,
so the historical ramp-only and steady-inlet behaviour is unchanged.

Restart phase continuity
------------------------
The executable restarts its local time at zero on a hydrodynamic restart.  Set
inletVelocityOscillationTimeOffset to the global physical time already elapsed
so the sine phase remains continuous.

The x14ay Basilisk gamma-refinement runner included in this patch supports this
through BASILISK_PULSE_RUNTIME_ENABLE.  It keeps the pulse OFF by default to
preserve direct comparability with prior gamma-refinement runs.  When enabled,
it writes the Basilisk 5% amplitude and its St-based period to the solver params.
For a direct state_step_N.smpcd restart it auto-uses N*dt as time offset; chained
restart segments should supply INLET_OSCILLATION_TIME_OFFSET explicitly.

Basilisk benchmark use
----------------------
For the current 2-D analogue:

  BASILISK_PULSE_RUNTIME_ENABLE=1
  BASILISK_PULSE_REL_AMPLITUDE=0.05
  INLET_OSCILLATION_PHASE=0.0
  INLET_OSCILLATION_START_TIME=0.0

The runner derives T = D/(St U), with St=5/3.  Phase zero reproduces the
Basilisk convention U(0)=U0 and initially increasing velocity.

Qualification intent
--------------------
This changes C++/CUDA inlet boundary behaviour only when explicitly enabled and
therefore requires a targeted qualification before calling the pulsed path
qualified.  At minimum verify:

  1. oscillation OFF reproduces the pre-x14ba steady/ramp path;
  2. parser rejects A outside [0,1] and non-positive T;
  3. at phase 0 the inlet follows 1, 1+A, 1, 1-A, 1 over one period;
  4. particle-inlet and Q6 flux paths remain phase locked;
  5. restart with t_offset preserves phase.

No change is made to ./livevis_control.kv.
