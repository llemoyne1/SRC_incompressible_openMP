# 0333b benchmark-script fix

This small update fixes the 0333 benchmark analyzer failure caused by repeated header rows in `src_runs_0333.tsv`.

Changes:

- `scripts/run_vk_full_periodic_mono_vs_src_0333.sh`
  - writes the SRC table header once instead of once per case.
- `scripts/analyze_vk_full_periodic_mono_vs_src_0333.py`
  - ignores repeated header rows defensively, so existing 0333 artifacts can be analyzed without rerunning the benchmark.

To analyze an already completed but failed 0333 run:

```bash
ART=$(ls -dt dev_history/artifacts/vk_mono_vs_src_0333_* | head -1)
python3 scripts/analyze_vk_full_periodic_mono_vs_src_0333.py "$ART" \
  | tee "$ART/analyze_vk_full_periodic_mono_vs_src_0333.stdout.txt"
```
