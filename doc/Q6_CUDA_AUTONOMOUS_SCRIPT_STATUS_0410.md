# Q6 CUDA autonomous scripts 0410

This differential bundle updates/generates autonomous scripts using `run_cuda_q6_resident_poiseuille_autonomous_0406.sh` as the reference pattern: three run modes, livevis enabled for all modes by default, terminal progress preserved, and `/usr/bin/time -o` kept for validation summaries.

Included scripts:

- `scripts/run_cuda_q6_resident_tg_autonomous_0405.sh`
  - existing TG autonomous three-mode script aligned with the 0406 progress/livevis behavior.
- `scripts/run_cuda_q6_resident_box_io_fullface_0404.sh`
  - existing full-face inlet/outlet box script aligned with the standardized three mode names.
- `scripts/run_cuda_q6_resident_box_segmented_autonomous_0409.sh`
  - new same-face segmented box script using the current partial segmented inlet/outlet resident Q6 CUDA path.

Run modes used consistently:

- `src_cuda_classic`: SRC CUDA classic, no Q6.
- `src_q6_cpu`: SRC + Q6 CPU projection.
- `src_q6_cuda`: SRC + Q6 CUDA resident projection when supported by the current code path.

Important support note for backward-step and hard VK cylinder:

The current resident Q6 CUDA guards in the provided snapshot still reject `immersedSolidEnable=true` for the resident Q6 path. Therefore, a physically hard backward-step obstacle or hard immersed VK cylinder cannot honestly be turned into a fully resident `src_q6_cuda` three-mode script only by changing bash scripts. Those cases need a source-level extension of the resident Q6 CUDA support to immersed solids/cut faces. Until then:

- use `src_cuda_classic` for resident classic obstacle/VK checks;
- use `src_q6_cpu` for validated Q6 with immersed solids;
- keep `src_q6_cuda` for TG, Poiseuille/wall channel, full-face IO box, and the supported segmented IO subset.
