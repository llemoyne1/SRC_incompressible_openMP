0493x13zk — run_ok checker semantic physics checks

Purpose:
- Preserve local user changes to case-specific physical defaults (sigma, cutoff, interface settings).
- The checker verifies that required parameters remain explicitly visible in each run_ok_*.sh,
  but no longer requires historical literal values such as sigma=945.0.
- No runner, C++/CUDA file, or livevis_control.kv is modified.
