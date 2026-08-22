#!/usr/bin/env python3
import csv
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit(
        "usage: analyze_0493x10h_mobile_interface.py "
        "<cuda_phase_kinetic_crossing_0493x9z.csv>")

p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("[0493x10h-check] ERROR empty CSV")

def I(r,k): return int(float(r.get(k,0) or 0))
def F(r,k): return float(r.get(k,0) or 0)
def S(k): return sum(I(r,k) for r in rows)
def maxabs(k): return max((abs(F(r,k)) for r in rows), default=0.0)

hard_checks = S("hardFinalEndpointChecks")
hard_corr = S("hardFinalEndpointCorrections")
hard_miss = S("hardFinalLocalAnchorMisses")

interior = S("interiorCrossings")
shell_cross = S("shellGuardCrossings")
shell_recoverable = S("shellRecoverableParticles")
shell_seal_candidates = S("shellHardRetentionCandidates")
interior_final_out = S("appliedInteriorFinalOutside")
shell_final_out = S("shellHardRetentionFinalOutside")

deep = [I(r,"deepOuterParticles") for r in rows]
outer = [I(r,"phaseAOuterCellParticles") for r in rows]
shell = [I(r,"shellParticles") for r in rows]

active = S("globalReactionActive")
trivial = S("globalReactionTrivial")
invalid = S("globalReactionInvalid")
scales = [F(r,"globalReactionScale") for r in rows if I(r,"globalReactionActive")]

dp = max(maxabs("deltaPx"), maxabs("deltaPy"))
de = maxabs("deltaKineticEnergy")
formula = maxabs("globalReactionFormulaResidual")

print("===== 0493x10h MOBILE INTERFACE / RELATIVE THERMAL RETENTION =====")
print(f"file={p} rows={len(rows)} lastStep={rows[-1].get('step','?')}")
print("--- interface mobility contract ---")
print(f"universalHardBarrier checks={hard_checks} corrections={hard_corr} anchorMisses={hard_miss}")
print(f"interiorDonorCrossings={interior} interiorDonorFinalOutside={interior_final_out}")
print(f"shellDonorCrossings={shell_cross} selectiveShellSealCandidates={shell_seal_candidates} "
      f"shellDonorFinalOutside={shell_final_out}")
print(f"shellRecoverable(all)={shell_recoverable} "
      f"nonDonorShellFreeApprox={max(0, shell_recoverable-shell_seal_candidates)}")
print("--- halo / reconstructed-alpha context ---")
print(f"outer first={outer[0]} max={max(outer)} last={outer[-1]}")
print(f"shell first={shell[0]} max={max(shell)} last={shell[-1]}")
print(f"deepOuter first={deep[0]} max={max(deep)} last={deep[-1]}")
print("--- x10g global exact reaction retained ---")
print(f"active={active} trivial={trivial} invalid={invalid}")
if scales:
    print(f"scale a last={scales[-1]:.9g} min={min(scales):.9g} "
          f"max={max(scales):.9g} mean={sum(scales)/len(scales):.9g}")
print(f"max|deltaP|={dp:.12e}")
print(f"max|deltaKE|={de:.12e}")
print(f"max|analyticResidual|={formula:.12e}")

mobile = (
    hard_checks == 0 and hard_corr == 0 and hard_miss == 0 and
    shell_seal_candidates == shell_cross
)
donor_seal = (interior_final_out == 0 and shell_final_out == 0)
cons = (dp < 1e-9 and de < 1e-9 and formula < 1e-9)
glob = (active > 0 and invalid == 0)

print("mobileInterfaceContract=" + ("PASS" if mobile else "FAIL"))
print("thermalDonorSealContract=" + ("PASS" if donor_seal else "FAIL"))
print("conservationContract=" + ("PASS" if cons else "FAIL"))
print("globalReservoirContract=" + ("PASS" if glob else "FAIL"))
print("antiEvaporationOutcome=VISUAL_AND_HALO_REVIEW")
print("shapeContract=VISUAL_PENDING")
print("multiComponentContract=NOT_APPLICABLE_ABLATION_ONLY")
