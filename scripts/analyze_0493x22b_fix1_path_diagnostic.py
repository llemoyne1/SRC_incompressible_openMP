#!/usr/bin/env python3
import csv, json, math, statistics, sys
from pathlib import Path
inp=Path(sys.argv[1]); out=Path(sys.argv[2]); out.mkdir(parents=True,exist_ok=True)
rows=list(csv.DictReader(inp.open()))
by={}
for r in rows:
    by.setdefault(r['variant'],[]).append(float(r['seconds_per_step']))
med={k:statistics.median(v) for k,v in by.items()}
base=med['A0_SRC']
summary={
 'status':'DIAGNOSTIC_ONLY',
 'A0_SRC_median_s_per_step':base,
 'A1_SRC_Q6_median_s_per_step':med.get('A1_SRC_Q6',math.nan),
 'A2_OLD_X22B_Q6GF_median_s_per_step':med.get('A2_OLD_X22B_Q6GF',math.nan),
 'A1_over_A0':med.get('A1_SRC_Q6',math.nan)/base,
 'A2_over_A0':med.get('A2_OLD_X22B_Q6GF',math.nan)/base,
 'A2_over_A1':med.get('A2_OLD_X22B_Q6GF',math.nan)/med.get('A1_SRC_Q6',math.nan),
 'interpretation':'A1 is the historical plain src-q6 path; A2 reproduces the invalid x22b A1 architecture with Q6-G-F free-surface machinery enabled in a full liquid.'
}
(out/'path_diagnostic_summary.json').write_text(json.dumps(summary,indent=2)+'\n')
lines=['===== 0493x22b-fix1 PATH DIAGNOSTIC =====']+[f'{k}={v}' for k,v in summary.items()]
(out/'path_diagnostic_summary.txt').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
