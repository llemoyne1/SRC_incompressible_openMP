# 0337b — fix missing livevis env helper functions

0337a used `env_int_0337`, `env_double_0337`, and `env_string_0337` in `main_src_mpcd_base.cpp`, but the helper insertion was missing from the generated file.  This patch adds those local helpers in the anonymous namespace next to `env_truthy_0260`.
