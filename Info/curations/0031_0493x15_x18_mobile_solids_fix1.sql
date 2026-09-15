-- V4.31-fix1: provenance correction + local functional validation of x18d (2026-09-15)
-- No new scientific milestone. The active parameter snapshot carries precise
-- introduction hints; this curation records the operator-reported local validation.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET status='VALIDATED/FUNCTIONAL: x18d appliqué sur le worktree réel, compilation CUDA locale réussie et runs hinged_plate_2d fonctionnels; gain de performance non encore quantifié par benchmark.',
    notes='x18c spécialisé reste non canonique. x18d est le chemin normal global pour les solides mobiles; diagnostics lourds opt-in. Validation fonctionnelle locale rapportée le 15/09/2026; aucun facteur d’accélération n’est revendiqué sans benchmark.'
WHERE object_id='milestone:0493x18d';

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x18d',
  'OPERATOR_VALIDATION',
  'Info/docs/CURATION_0493X15_X18_MOBILE_SOLIDS_V4_31_FIX1.md',
  'A',
  'Validation locale rapportée le 15/09/2026: patch x18d appliqué, compilation CUDA réussie et runs du volet hinged_plate_2d fonctionnels. Le benchmark de gain de performance reste à quantifier.'
);
