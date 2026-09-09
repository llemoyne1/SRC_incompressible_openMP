-- V4.24: declare the exact Git introduction for the namespaced 2026-09-07 0414 milestone.
-- Bare numeric label 0414 is historically reused.  Candidate reconciliation itself is
-- deliberately executed post-Git-import by build_src_reference.py using the exact
-- (normalized_label, anchor_commit, milestone_object_id) triple documented here.

UPDATE milestones
SET introduced_commit='e2fe1ca29042c2391cd5b6ee7f9eb7fe9a2065a8',
    notes=CASE
      WHEN instr(COALESCE(notes,''),'V4.24 Git reconciliation')>0 THEN notes
      WHEN COALESCE(notes,'')='' THEN 'V4.24 Git reconciliation: surf commit e2fe1ca introduces the qualified segmented x/y CUDA-resident implementation.'
      ELSE notes || ' | V4.24 Git reconciliation: surf commit e2fe1ca introduces the qualified segmented x/y CUDA-resident implementation.'
    END
WHERE object_id='milestone:20260907-0414-segmented-xy';
