0493x14b/x14c — dynamic qualification runners for 0493x14a per-type thermostat

x14b: active common SRC collision, 120 deg, random sign, gridShift=false.
      Two cases: equal kBT and split kBT. Final state is checked exactly cell by
      cell because the thermostat collision grid is unshifted.

x14c: same common SRC collision with production-like random grid shift enabled.
      Two cases: equal kBT and split kBT. Mass and total momentum are checked;
      global apparent per-type kBT is reported. Exact fixed-cell temperature is
      intentionally not asserted because the final random shift is not stored.

Neither runner modifies ./livevis_control.kv. x12a is OFF. No resampling/refill.
Python helper uses only the standard library.
