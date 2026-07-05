#!/usr/bin/env python3
from pathlib import Path

ROOT = Path.cwd()
HDR = ROOT / 'include' / 'cuda_resampling_pipeline_shadow_0445.h'
MAIN = ROOT / 'src' / 'src_mpcd_base.cpp'
CU = ROOT / 'src' / 'cuda_resampling_pipeline_shadow_0445.cu'

def read(p):
    if not p.exists():
        raise SystemExit(f'[0475a2] missing file: {p}')
    return p.read_text()

def write(p, s):
    p.write_text(s)

# 1) The 0475a env helper is local to the CU translation unit.  Do not declare
# it in the public CUDA header: when the CU also has an unnamed-namespace helper
# with the same name, unqualified calls inside the CU become ambiguous.
h = read(HDR)
h2 = h.replace('bool cuda_resampling_materializer_on_plan_0475a_requested();\n', '')
h2 = h2.replace('inline bool cuda_resampling_materializer_on_plan_0475a_requested() { return false; }\n', '')
if h2 != h:
    write(HDR, h2)

# 2) src_mpcd_base.cpp still needs the same env decision.  Keep it local there,
# without depending on the CU-local helper.
m = read(MAIN)
if 'env_truthy_src_base_0475a' not in m:
    if '#include <cstdlib>' not in m:
        # Insert near other includes.  This is intentionally conservative.
        lines = m.splitlines(True)
        insert_at = 0
        for i, line in enumerate(lines):
            if line.startswith('#include'):
                insert_at = i + 1
        lines.insert(insert_at, '#include <cstdlib>\n')
        m = ''.join(lines)
    marker = 'namespace mpcd {'
    helper = '''namespace {

bool env_truthy_src_base_0475a(const char* name) {
    const char* v = std::getenv(name);
    if (v == nullptr || v[0] == '\\0') return false;
    const char c0 = v[0];
    if (c0 == '0' || c0 == 'f' || c0 == 'F' || c0 == 'n' || c0 == 'N') return false;
    return true;
}

} // namespace

'''
    if marker in m:
        m = m.replace(marker, marker + '\n' + helper, 1)
    else:
        raise SystemExit('[0475a2] missing namespace mpcd anchor in src_mpcd_base.cpp')

m2 = m.replace(
    'cuda_resampling_materializer_on_plan_0475a_requested() &&',
    'env_truthy_src_base_0475a("MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A") &&'
)
if m2 != m:
    write(MAIN, m2)
else:
    # If the expression was already replaced, still ensure helper/include were written.
    if m != read(MAIN):
        write(MAIN, m)

# 3) Leave the CU helper local.  Verify that it exists, because the CU still uses
# it for the materializer bypass decision.
s = read(CU)
if 'bool cuda_resampling_materializer_on_plan_0475a_requested()' not in s:
    raise SystemExit('[0475a2] CU-local 0475a helper not found; apply 0475a first')

print('[0475a2] fixed 0475a helper ambiguity')
