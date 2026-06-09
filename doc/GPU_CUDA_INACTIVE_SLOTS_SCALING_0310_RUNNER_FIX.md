# 0310 runner fix — inactive-slot scaling audit

This small fix makes the inactive-slot scaling runner create the parent directory
for per-run stdout/stderr logs before shell redirection is evaluated.

Without the directory, bash fails before launching the demo wrapper; the manifest
then reports `exitCode=1`, while `summaryRows`, `guardRows`, `flagRows`, and
`surveyRows` remain zero for every run.

No C++ or CUDA code is changed.
