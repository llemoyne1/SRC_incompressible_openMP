# 0417 — restart-friendly inactive-slot reservoir

## Goal

Allow `.smpcd` input states and dumps to contain only active fluid particles while
letting the code reconstruct an inactive reservoir at load time.

This makes compact dumps produced with:

```text
dumpRoleFilter = fluid
```

usable as restart inputs for CUDA resident inlet/outlet paths that need inactive
slots for particle insertion.

## New parameter

```text
initialInactiveSlots = 0
```

Semantics are intentionally fixed to **ensure**:

```text
if current inactive slots >= initialInactiveSlots: do nothing
else: append missing inactive slots
```

There is deliberately no `append` mode and no mode flag.

Appended inactive slots use fixed storage-only defaults:

```text
x = 0
y = 0
vx = 0
vy = 0
mass = 1
type = 0
role = Inactive
```

The positions and velocities of inactive slots are irrelevant until an insertion
kernel activates a slot, at which point they are overwritten.

## Typical script usage

For an inlet/outlet case that previously required inactive particles inside the
initial `.smpcd` file, generate/store only active particles and put this in the
`.kv`:

```text
initialInactiveSlots = ${INACTIVE_SLOTS}
dumpRoleFilter = fluid
summaryRoleFilter = fluid
```

A compact fluid-only dump can then be restarted with the same
`initialInactiveSlots` setting.

## Expected effects

At step 0, `summary_runtime.csv` should report:

```text
nFluidParticles   = active particles read from inputState
nInactiveParticles >= initialInactiveSlots
```

If the input state already contains enough inactive slots, the loader does not
add more; this preserves compatibility with older full-capacity `.smpcd` files.

## Validation sequence

1. Run an inlet/outlet CUDA resident case from an active-only `.smpcd` with
   `initialInactiveSlots > 0`.
2. Confirm that `summary_runtime.csv` reports non-zero `nInactiveParticles`.
3. Confirm that the resident inlet path does not fail with reservoir exhaustion.
4. Produce a dump with `dumpRoleFilter = fluid`.
5. Restart from that dump using the same `initialInactiveSlots` value.

This is not a bitwise restart guarantee: RNG/time-state persistence is a
separate topic. The purpose here is to make the particle-storage capacity
restart-compatible.
