-- V4.43: x19d performance-only cleanup of disabled diagnostics in the generic timestep
-- hot path (2026-09-18). No physical operator or qualified FSI mechanics is modified.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET notes = COALESCE(notes,'') ||
  ' 0493x19d performance maintenance 2026-09-18: the x19b-fix3 complete angular audit now has an allocation-free disabled path (cached process-level flag, no outputDir copy and no stage-vector reserve when OFF). CUDA resident phase-profile recorders now return before constructing diagnostic strings or copying outputDir when profiling is OFF. Explicitly enabled diagnostic behavior is preserved; free-rotor/FSI mechanics are unchanged.'
WHERE object_id='milestone:0493x19b-fix3';

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19b-fix3','PERFORMANCE_EVIDENCE',
  'Info/docs/CURATION_0493X19D_HOTPATH_DIAGNOSTIC_CLEANUP_V4_43.md','A',
  'Static hot-path audit and performance-only cleanup before the systematic fluid-characterization campaign; disabled x19b-fix3 audit and resident profiling no longer construct unnecessary heap-backed diagnostic state.'
);
