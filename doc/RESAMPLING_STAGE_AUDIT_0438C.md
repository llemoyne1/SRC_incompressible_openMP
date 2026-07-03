# 0438C — resampling stage audit helper

This helper inspects periodic 0438 runs and separates `resampComputed=1` from sub-stages that actually mutate or recondition the particle state: transfer planning, extraction/insertion, remap, thermal renormalization, mass guard, population guard and latent activation.

It is intended to clarify cases where `resampPoorCells=resampRichCells=resampTransferPairs=0` while `nFluidParticles` still changes.

Run example:

```bash
python3 scripts/analyze_resampling_stages_0438c.py \
  --root runs/0438_shear_periodic_equiv_g40_s2000

cat runs/0438_shear_periodic_equiv_g40_s2000/resampling_stage_audit_0438c.md
column -s, -t < runs/0438_shear_periodic_equiv_g40_s2000/resampling_stage_audit_0438c.csv | less -S
```
