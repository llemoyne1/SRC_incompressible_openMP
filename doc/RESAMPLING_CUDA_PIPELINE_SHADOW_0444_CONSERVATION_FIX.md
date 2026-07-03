# 0444 conservation-pass criterion fix

The initial 0444 end-to-end shadow validator required CPU and GPU final states to
match each other, but also required global momentum to remain close to the
synthetic initial state. The latter is not the purpose of 0444: this validator is
a CPU/GPU equivalence gate for the clean resampling pipeline. The CPU production
reference may change global Px/Py in shifted or variable-mass synthetic cases
through the remap/thermal stages while GPU reproduces that behavior exactly.

This fix keeps mass/Px/Py conservation residuals in the CSV for auditing, but
removes Px/Py conservation from the PASS criterion. Mass conservation remains a
PASS criterion. CPU-vs-GPU equality of mass, Px, Py and KE remains mandatory.
