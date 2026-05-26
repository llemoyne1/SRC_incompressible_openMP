# Apply 0069 files-only package

From the repository root:

```bash
unzip -o /path/to/0069_backward_step_mass_budget_visual_files_only.zip -d .

git diff --stat
git diff --check

chmod +x scripts/run_backward_step_mass_budget_viz_0069.sh

git add \
  docs/BACKWARD_STEP_MASS_BUDGET_VISUAL_0069.md \
  scripts/run_backward_step_mass_budget_viz_0069.sh \
  matlab/analyze_backward_step_mass_budget_0069.m \
  matlab/make_backward_step_visual_report_0069.m

git commit -m "0069 add backward-step mass budget and visual diagnostics"
git push
```

Run:

```bash
CASE_STEPS=8000 SUMMARY_EVERY=250 DUMP_STATE_EVERY=1000 NUM_THREADS=8 \
  ./scripts/run_backward_step_mass_budget_viz_0069.sh
```

Analyze:

```matlab
cd matlab
R = analyze_backward_step_mass_budget_0069('root','..','runRoot','runs/backward_step_mass_budget_viz_0069');
V = make_backward_step_visual_report_0069('root','..','runRoot','runs/backward_step_mass_budget_viz_0069');
cd ..
```
