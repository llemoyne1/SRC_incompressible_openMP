-- V4.28: close the Git provenance of the qualified multiphase Neumann path.
--
-- The canonical surf commit and official qualification tag are now known
-- exactly.  The builder performs the post-Git-import reconciliation of the
-- dated X candidate emitted by the tag name; this SQL only records the stable
-- milestone metadata available before Git import.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET introduced_commit='6dfda0404c2066f3db378a5d27c30a6dcc898d39',
    tag='surf-neumann-qualified-x9e-fix3-20260910',
    notes=CASE
      WHEN instr(COALESCE(notes,''),'V4.28 Git closure')>0 THEN notes
      ELSE trim(COALESCE(notes,'') ||
        CASE WHEN COALESCE(notes,'')='' THEN '' ELSE ' | ' END ||
        'V4.28 Git closure: canonical surf commit 6dfda0404c2066f3db378a5d27c30a6dcc898d39; official tag surf-neumann-qualified-x9e-fix3-20260910. The dated candidate x9e-fix3-20260910 is a tag alias of x9e-fix3, not a new milestone.')
END
WHERE object_id='milestone:0493x9e-fix3';
