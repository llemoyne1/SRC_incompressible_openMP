# 0493x21e fix2 — robust checkpoint CSV parsing

No solver, physics, parameter, or analysis change.

The previous fix attempted to strip CR with awk but matched a literal `\\r`
instead of the CR record terminator.  Fix2 reads `selected_checkpoint_0493x21e.csv`
with Python's `csv.DictReader`, eliminating the line-ending ambiguity.

Run again with RESTART=1. The completed active R40_seed4932401 case is reused.
