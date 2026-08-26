# 0490k — Native CUDA species donor/receiver plan

## Purpose

Patch 0490k moves the 0490g species-constrained donor/receiver planner onto CUDA.
The resident 0490h composition workspace supplies, for each cell and species,
`M_{c,s}` and total cell mass. The CUDA planner then:

1. classifies poor receivers and rich donors from the existing mass thresholds;
2. apportions each receiver deficit over the species already present;
3. apportions each donor excess over its species composition;
4. pairs only equal particle types;
5. selects the nearest compatible donor, with donor-cell index as tie break;
6. writes the compact transfer plan on the device.

The deterministic ordering is identical to the CPU 0490g reference:
receiver cell, registry species, then nearest compatible donor.

## Gate status

This is a correctness gate before removing the CPU mirror:

- the CPU 0490g plan is still computed as a strict reference;
- the CUDA plan is compared entry by entry, including type, mass, distance and
  remaining donor/receiver mass;
- on exact/tolerance PASS, the host plan mirror is replaced by the CUDA-built
  plan and downstream extraction/insertion consumes the accepted plan;
- the device composition and plan allocations are persistent across steps.

The compact accepted plan is downloaded during this gate patch. The next
integrated resident validation can connect the device plan directly to the
existing CUDA operation materializer/carrier and quantify the remaining sync.

## Parameters

```text
speciesResamplingTransferEnable = true
speciesResamplingTransferCudaEnable = true
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesTransferCudaComparisonTolerance = 1e-11
```

## Smoke test

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490k \
bash scripts/run_0490k_cuda_species_transfer_plan_smoke.sh
```

The test deliberately places a gas donor closer to a liquid receiver than the
compatible liquid donor. CPU and CUDA trajectories must be identical, and the
GPU plan must select the farther liquid donor without changing global mass of
either species.
