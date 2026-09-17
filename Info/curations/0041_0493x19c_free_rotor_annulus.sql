-- V4.41: x19c free inner rotor end-to-end solid/FSI qualification
-- (2026-09-17). Adds one scalar rotor DOF to the validated x19b annulus.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET status='QUALIFIED_WITH_DOCUMENTED_TORQUE_BIAS',
    confidence='A',
    notes=COALESCE(notes,'') ||
      ' Local x19b-fix4 high-SNR result: effective Ri=0.199976991, Ro=0.349989344, rho2D=786521.317; tangential Couette half-difference T_C=29.9952367 +/-0.752329 block SEM versus matched-TG theory 27.3626194, relative difference +9.62122%. Common tangential half-sum=-3.20952218 +/-1.82092. Velocity profile relRMSE=0.0325029, R2=0.985311, gain=0.976747, radial/Ui=0.0180787. x19b is therefore closed as a curved moving-material-wall qualification with an explicitly documented ~10% torque bias.'
WHERE object_id='milestone:0493x19b-fix4';

INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from)
VALUES('milestone:0493x19c','MILESTONE','x19c free rotor annulus','curation:0041_0493x19c_free_rotor_annulus');

INSERT OR REPLACE INTO milestones(
  object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
  nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
  source_file,source_row
) VALUES(
  'milestone:0493x19c','0493x19c','x19c','0493x19c','solides mobiles / FSI',
  'Cylindre intérieur libre sous couple constant dans un anneau Couette',
  'Validation end-to-end du traitement solide: la géométrie circulaire x17 reste stationnaire comme ensemble, mais la vitesse matérielle de la branche intérieure devient une DOF libre Omega. A chaque pas, le collisionneur fournit exactement l impulsion de couple de réaction intérieure; le solide applique I DeltaOmega = J_hydro + T_ext dt - C Omega dt. T_ext est fixé AVANT x19c à partir de la moyenne tardive du couple intérieur total du run prescrit indépendant x19b-fix4 à Omega=0.20. Le run x19c repart du champ fluide établi de fix4 avec Omega0=0.20 et vérifie fermeture mécanique, action-reaction, stationnarité de Omega, reproduction du couple hydrodynamique de référence et maintien du profil Couette.',
  'QUALIFICATION','FSI','PENDING_LOCAL_RUN','A','2026-09-17',NULL,NULL,
  'Primary gate is discrete solid-mechanics closure plus agreement with the independent prescribed-run total inner torque reference. The matched TG continuum result remains a secondary hydrodynamic reference because x19b already documents the residual force/torque discretization bias.',
  'Info/curations/0041_0493x19c_free_rotor_annulus.sql',NULL
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES('milestone:0493x19c','BUILDS_ON','milestone:0493x19b-fix4','A','Free-rotor mechanics closes the solid feedback loop after prescribed curved-wall hydrodynamics and torque were qualified in x19b-fix4.');
