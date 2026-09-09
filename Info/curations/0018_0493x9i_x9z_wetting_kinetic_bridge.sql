-- V4.17: accelerated evidence-driven closure of the remaining x9 cycle.
-- This curation replaces two coarse historical aggregates by attested identities,
-- consolidates wetting/capillary qualification, and records the late-x9 kinetic
-- retention chain that bridges the Laplace model to the x10 free-surface closure.
-- No C++/CUDA or runner is changed by this documentary curation.

-- Aggregates are no longer canonical once their constituent identities are curated.
-- They have no Git candidate linked to them and no curated relation in the V4.16 baseline.
DELETE FROM objects WHERE object_id IN ('milestone:0493x9a-x9c','milestone:0493x9i-x9l');

-- New identities absent from the raw reference.
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES
('milestone:0493x9i','MILESTONE','x9i','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9j','MILESTONE','x9j','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9k','MILESTONE','x9k','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9l','MILESTONE','x9l','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9n','MILESTONE','x9n','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9o','MILESTONE','x9o','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9p','MILESTONE','x9p','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9q','MILESTONE','x9q','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9t','MILESTONE','x9t','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9u','MILESTONE','x9u','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9v','MILESTONE','x9v','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9w','MILESTONE','x9w','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9x','MILESTONE','x9x','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9y','MILESTONE','x9y','curation:0018_0493x9i_x9z_wetting_kinetic_bridge'),
('milestone:0493x9z','MILESTONE','x9z','curation:0018_0493x9i_x9z_wetting_kinetic_bridge');

INSERT OR REPLACE INTO milestones(object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,source_file,source_row) VALUES
('milestone:0493x9i','0493x9i','x9i','0493x9i','x9 : tension superficielle, courbure et mouillage','Première fermeture d''angle de contact par normale imposée','Introduit phaseInterfaceContactAngleDegrees, mesuré à travers la phase A, et impose dans la bande de contact nAB.nWall=-cos(theta) en remplaçant localement la normale p3. alpha_x6c et le crossing physique x6f restent inchangés.','CODE','SURFACE_TENSION','Prototype historique : angle local exact mais biais de div(n)/courbure; conservé comme baseline derrière un gate de test','A',NULL,NULL,NULL,'-1 désactive la fermeture. Le mur reste un troisième objet géométrique fourni par x9h et ne devient pas phase B. La courbure de contact n''était qu''informative à cette étape.','0493x9i_contact_angle_review.diff',NULL),
('milestone:0493x9j','0493x9j','x9j','0493x9j','x9 : tension superficielle, courbure et mouillage','Fermeture d''angle par ghost-alpha de courbure','Remplace la discontinuité de normale x9i par des échantillons alpha virtuels derrière une paroi statique pendant les trois passes p3 et les dérivées Scharr; la condition de Young est portée par le champ réservé à la courbure.','CODE','SURFACE_TENSION','Prototype historique supplanté : améliore certains angles mais ne préserve pas suffisamment la géométrie multi-couche','A',NULL,NULL,NULL,'Le chemin hard-normal x9i reste reproductible sous MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I. x9j ne déplace jamais l''interface physique alpha=0.5.','README_0493X9J_GHOST_ALPHA_CONTACT.md',NULL),
('milestone:0493x9k','0493x9k','x9k','0493x9k','x9 : tension superficielle, courbure et mouillage','Ghost-alpha par miroir cisaillé','Prolonge x9j à toutes les profondeurs ghost par réflexion du point à travers le mur puis décalage tangentiel proportionnel à cot(theta), avant interpolation du vrai champ alphaK. À 90 degrés la loi se réduit exactement au miroir ordinaire.','CODE','SURFACE_TENSION','Prototype historique supplanté : angle robuste mais une transformation affine ne préserve pas un cercle, donc biais de courbure angle-dépendant','A',NULL,NULL,NULL,'Domaine expérimental strict 0<theta<180; aucune nouvelle clé persistante. alpha_x6c, crossing x6f, sigma, phiGamma, CG et B1 restent inchangés.','README_0493X9K_SHEARED_MIRROR_GHOST.md',NULL),
('milestone:0493x9l','0493x9l','x9l','0493x9l','x9 : tension superficielle, courbure et mouillage','Reconstruction de normale au mur-face','Laisse alpha physique et alphaK p3 inchangés, impose la normale de Young au mur physique et reconstruit par rotation les normales du premier centre fluide et du premier ghost à partir d''une normale p3 plus intérieure, avant div(n).','CODE','SURFACE_TENSION','Expérience négative hors voisinage de 90 degrés; gardée comme comparaison et supplantée par x9m','A',NULL,NULL,NULL,'Parois statiques seulement; gate expérimental MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L. Le sweep géométrique ne suffisait pas à rendre la courbure robuste sur toute la plage angulaire.','README_0493X9L_WALLFACE_NORMAL.md',NULL),
('milestone:0493x9n','0493x9n','x9n','0493x9n','x9 : tension superficielle, courbure et mouillage','Qualification géométrique étendue de x9m','Teste sans changement de solveur la fermeture x9m sur contacts plans kappa=0, scaling circulaire 1/R sur plusieurs rayons et ellipses à courbure locale variable afin d''écarter un simple ajustement au premier cap circulaire.','QUALIFICATION','SURFACE_TENSION','Qualification scripts-only de la robustesse géométrique statique x9m','A',NULL,NULL,NULL,'22 cas one-step par défaut. Le chemin physique testé reste exactement x9m; aucune recompilation n''est requise.','README_0493X9N_GEOMETRIC_QUALIFICATION.md',NULL),
('milestone:0493x9o','0493x9o','x9o','0493x9o','x9 : tension superficielle, courbure et mouillage','Qualification de phase sous-maille tangentielle de x9m','Translate tangentiellement de 0, 0.25h, 0.5h et 0.75h les deux géométries x9n les plus sensibles afin de mesurer le biais de phase de grille sans déplacer le mur physique.','QUALIFICATION','SURFACE_TENSION','Qualification scripts-only; quantifie la sensibilité résiduelle de x9m à la phase sous-maille','A',NULL,NULL,NULL,'Aucun changement C++/CUDA. Le critère porte sur la moyenne des quatre phases, leur demi-étendue et l''erreur absolue basse courbure.','README_0493X9O_PHASE_QUALIFICATION.md',NULL),
('milestone:0493x9p','0493x9p','x9p','0493x9p','x9 : tension superficielle, courbure et mouillage','Qualification dynamique de goutte sessile x9m','Fait évoluer des calottes 60/90/120 degrés et des transitions 90 vers 60/120; reconstruit l''angle global physique indépendamment par COM et moments afin de vérifier sens de mouillage, conservation et approche de la cible.','QUALIFICATION','SURFACE_TENSION','Résultat dynamique partiel : sens mouillage/démouillage correct, mais équilibre comprimé vers 90 degrés et courbure de ligne triple encore bruitée','A',NULL,NULL,NULL,'Qualification-only, sans physique nouvelle. Elle établit la limite importante de x9m : bonne fermeture statique mais pas encore loi dynamique de ligne de contact universelle.','README_0493X9P_SESSILE_DYNAMICS.md',NULL),
('milestone:0493x9q','0493x9q','x9q','0493x9q','x9 : tension superficielle, courbure et mouillage','Test de potentialité jet gravitaire / pincement / impact','Runner-only : injecte un jet liquide par un segment supérieur dans gaz ou vide, sous gravité, pour provoquer langue pendante, col/pincement, chute et impact sur la paroi avec la chaîne capillaire x9.','BENCHMARK','SURFACE_TENSION','Benchmark exploratoire sans seuil physique dur; démontre des changements de topologie et expose la faiblesse de courbure sous-résolue traitée par x9r','A',NULL,NULL,NULL,'Le cas est explicitement de potentialité, pas une calibration de temps de breakup, taille de goutte ou Weber critique. Aucun source solveur n''est modifié par x9q.','README_0493X9Q_DRIPPING_JET_POTENTIAL.md',NULL),
('milestone:0493x9t','0493x9t','x9t','0493x9t','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Première rétention cinétique liquide-vide conservative','Ajoute une fermeture interne pour les particules de phase A traversant l''interface vers le vide : sélection selon phaseInterfaceKineticReflectionFraction, transformation élastique conservative par groupes candidat/receveur et transmission/évaporation optionnelle.','CODE','FREE_SURFACE_KINETICS','Prototype actif de rétention cinétique; première étape du pont x9 vers la fermeture de surface libre x10','A',NULL,NULL,NULL,'Le contrôle mathématique vérifie conservation exacte P/K de la transformation à deux groupes. Le runner de qualification utilise une goutte liquide-vide haute kBT où le chemin pré-x9t évaporait visiblement.','run_0493x9t_vacuum_drop_reflection.sh',NULL),
('milestone:0493x9u','0493x9u','x9u','0493x9u','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Extension de la réflexion aux sorties de support','Étend x9t aux sorties de support en distinguant crossings historiques alpha=0.5 et support-exit, et recherche un bain de recul intérieur jusqu''à deux cellules avec bilan exact de quantité de mouvement et énergie.','CODE','FREE_SURFACE_KINETICS','Étape active intermédiaire; couverture support-edge améliorée mais le choix de bain sera corrigé par x9w','A',NULL,NULL,NULL,'L''audit partitionne crossings, profondeur du bain 0/1/2, transmissions, réflexions et échecs; r=1 exige une application complète dans le domaine qualifié.','run_0493x9u_vacuum_drop_reflection.sh',NULL),
('milestone:0493x9v','0493x9v','x9v','0493x9v','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Diagnostic des voies de fuite de la fermeture x9u','Exécute exactement la physique x9u et instrumente à cadence de résumé les halos, échecs de recherche de bain, bains non bulk, réflexions non appliquées et particules encore sortantes après réflexion.','DIAGNOSTIC','FREE_SURFACE_KINETICS','Diagnostic passif; aucune nouvelle passe particulaire ni modification de physique','A',NULL,NULL,NULL,'La campagne identifie notamment qu''un bain de recul peut appartenir au halo occupé tout en restant du côté alpha<0.5, ce qui motive x9w.','run_0493x9v_vacuum_drop_diagnostic.sh',NULL),
('milestone:0493x9w','0493x9w','x9w','0493x9w','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Bain de recul strictement bulk','Corrige x9u après le diagnostic x9v : un bain cinétique receveur doit appartenir au bulk liquide physique alpha>=0.5; un halo occupé n''est plus autorisé à se bootstrapper comme support cohésif.','FIX','FREE_SURFACE_KINETICS','Correctif actif de sélection du bain; recherche bornée à deux cellules et conservation P/K maintenue','A',NULL,NULL,NULL,'L''invariant x9w impose supportExitBathAlphaLTHalf=0. Il ne rajoute pas de passe particulaire de production.','run_0493x9w_vacuum_drop_bulk_bath.sh',NULL),
('milestone:0493x9x','0493x9x','x9x','0493x9x','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Réflexion au crossing physique prédit','Remplace le seul critère de cellule/support par la détection du crossing réel entre la position courante et x+v*dt dans alpha, avec gate d''advection relative (v-u_bulk).n>0 et correction de position au temps de crossing.','CODE','FREE_SURFACE_KINETICS','Étape active intermédiaire : déclenchement géométrique au crossing physique, sans nouvelle passe globale','A',NULL,NULL,NULL,'Une garde shell d''une cellule subsiste; le contrôle déterministe vérifie l''identité de placement crossing-time.','run_0493x9x_vacuum_drop_crossing.sh',NULL),
('milestone:0493x9y','0493x9y','x9y','0493x9y','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Côté alpha pointwise et crossing par bissection bornée','Corrige x9x en évaluant le côté intérieur/extérieur au point de départ plutôt qu''au centre de cellule, puis localise les vrais crossings avec quatre bissections dans la passe d''application et conserve le dernier point connu intérieur.','FIX','FREE_SURFACE_KINETICS','Correctif géométrique actif de x9x; supprime l''aliasing centre-cellule sans buffer ou passe globale supplémentaire','A',NULL,NULL,NULL,'Le contrôle mathématique borne l''erreur de fraction de crossing à 1/16 tout en garantissant que le dernier point retenu reste intérieur.','run_0493x9y_vacuum_drop_pointwise.sh',NULL),
('milestone:0493x9z','0493x9z','x9z','0493x9z','x9 : tension superficielle, courbure, mouillage et prélude cinétique','Réflexion individuelle des donneurs et compensation affine du bain','Individualise la mécanique x9y : chaque particule traversante utilise sa propre normale et est réfléchie spéculairement relativement au même bain; une correction affine collective des receveurs restaure exactement quantité de mouvement et énergie.','CODE','FREE_SURFACE_KINETICS','Dernière étape x9 du mécanisme de rétention; loi individuelle explicitement réutilisée ensuite par x10a','A',NULL,NULL,NULL,'Trois passes particulaires historiques seulement, plus une réaction O(Ncell); aucun merge/resampling de nettoyage. L''audit exige que chaque donneur appliqué soit individuellement rentrant et que P/K soient conservés.','run_0493x9z_vacuum_drop_individual.sh',NULL);

-- Consolidate existing raw-reference milestones x9m/x9r/x9s.
UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Fermeture statique de mouillage par ancre hors support',
 summary='Impose la normale de Young au mur puis évalue la courbure de contact à partir de la première normale p3 hors du support contaminé par paroi (couche j=4, centre 4.5h) et de la corde jusqu''au crossing physique : kappa=2 sin(DeltaPhi/2)/L. Ni alpha ni le champ normal p3 ne sont écrasés.',
 nature='CODE',domain='SURFACE_TENSION',status='Fermeture statique préférée du cycle x9; robuste géométriquement, mais dynamique de ligne triple non universellement fermée',confidence='A',
 notes='Qualifiée statiquement sur 30..150 degrés, rayons, interfaces planes/elliptiques et phase de grille. Parois statiques seulement; chi/wallVP et 0/180 degrés exclus. x9p révèle une dynamique quantitative encore imparfaite.',
 source_file='README_0493X9M_OFFSUPPORT_ANCHOR.md',source_row=NULL
WHERE object_id='milestone:0493x9m';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Cutoff de résolution du saut capillaire',
 summary='Ajoute surfaceTensionMinRadiusCells avec 0 comme no-op exact. Pour N_R>0, borne uniquement la courbure interpolée au crossing utilisée dans sigma*kappa à |kappa|<=1/(N_R min(dx,dy)); alpha, crossing, champ p3 brut et LiveVis restent inchangés.',
 nature='FIX',domain='SURFACE_TENSION',status='Correctif actif de courbure sous-résolue; seuil à choisir selon résolution/campagne, non constante physique universelle',confidence='A',
 notes='Motivé par les éjections balistiques du jet lorsque le rayon implicite tombe sous la maille. Le choix historique de développement N_R=3 coupe les singularités locales puis devient transparent au bulk; des campagnes ultérieures emploient aussi 4.',
 source_file='README_0493X9R_CAPILLARY_RESOLUTION_CUTOFF.md',source_row=NULL
WHERE object_id='milestone:0493x9r';

UPDATE milestones SET
 group_name='x9 : tension superficielle, courbure et mouillage',
 name='Benchmark paramétrable d''impact et splash',
 summary='Construit une goutte initiale paramétrable impactant soit une paroi sèche soit une flaque, avec la même physique bulk/capillaire, afin d''observer étalement, lamelle, rim, splash et interaction liquide-liquide lors de changements de topologie.',
 nature='BENCHMARK',domain='SURFACE_TENSION',status='Démonstration/qualification morphologique qualitative; pas une mesure convergée de Weber critique',confidence='A',
 notes='Le runner x9s sert ensuite de socle à la série cinétique x9t-x9z et aux campagnes x10-x12. TARGET=wall|puddle ne change pas le backend, seulement l''état initial/cible.',
 source_file='run_0493x9s_splash.sh',source_row=NULL
WHERE object_id='milestone:0493x9s';

-- Primary historical evidence archived byte-for-byte.
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9i','HISTORICAL_SOURCE','Info/inputs/historical/0493x9i_contact_angle_review.diff',NULL,'A','Primary x9i review diff with full contact-angle contract'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9i' AND path='Info/inputs/historical/0493x9i_contact_angle_review.diff');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9j','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9J_GHOST_ALPHA_CONTACT.md',NULL,'A','Primary x9j ghost-alpha documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9j' AND path='Info/inputs/historical/README_0493X9J_GHOST_ALPHA_CONTACT.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9k','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9K_SHEARED_MIRROR_GHOST.md',NULL,'A','Primary x9k sheared-mirror documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9k' AND path='Info/inputs/historical/README_0493X9K_SHEARED_MIRROR_GHOST.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9l','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9L_WALLFACE_NORMAL.md',NULL,'A','Primary x9l wall-face normal experiment documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9l' AND path='Info/inputs/historical/README_0493X9L_WALLFACE_NORMAL.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9m','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9M_OFFSUPPORT_ANCHOR.md',NULL,'A','Primary x9m off-support static wetting closure documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9m' AND path='Info/inputs/historical/README_0493X9M_OFFSUPPORT_ANCHOR.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9n','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9N_GEOMETRIC_QUALIFICATION.md',NULL,'A','Primary x9n geometric qualification documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9n' AND path='Info/inputs/historical/README_0493X9N_GEOMETRIC_QUALIFICATION.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9o','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9O_PHASE_QUALIFICATION.md',NULL,'A','Primary x9o grid-phase qualification documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9o' AND path='Info/inputs/historical/README_0493X9O_PHASE_QUALIFICATION.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9p','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9P_SESSILE_DYNAMICS.md',NULL,'A','Primary x9p dynamic sessile-drop qualification documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9p' AND path='Info/inputs/historical/README_0493X9P_SESSILE_DYNAMICS.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9q','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9Q_DRIPPING_JET_POTENTIAL.md',NULL,'A','Primary x9q dripping-jet potentiality documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9q' AND path='Info/inputs/historical/README_0493X9Q_DRIPPING_JET_POTENTIAL.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9r','HISTORICAL_SOURCE','Info/inputs/historical/README_0493X9R_CAPILLARY_RESOLUTION_CUTOFF.md',NULL,'A','Primary x9r resolution-cutoff documentation'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9r' AND path='Info/inputs/historical/README_0493X9R_CAPILLARY_RESOLUTION_CUTOFF.md');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9s','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9s_splash.sh',NULL,'A','Snapshot primary x9s parametric splash runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9s' AND path='Info/inputs/historical/run_0493x9s_splash.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9t','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9t_vacuum_drop_reflection.sh',NULL,'A','Snapshot x9t first kinetic-reflection qualification runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9t' AND path='Info/inputs/historical/run_0493x9t_vacuum_drop_reflection.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9u','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9u_vacuum_drop_reflection.sh',NULL,'A','Snapshot x9u support-edge reflection qualification runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9u' AND path='Info/inputs/historical/run_0493x9u_vacuum_drop_reflection.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9v','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9v_vacuum_drop_diagnostic.sh',NULL,'A','Snapshot x9v diagnostic-only escape-path runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9v' AND path='Info/inputs/historical/run_0493x9v_vacuum_drop_diagnostic.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9w','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9w_vacuum_drop_bulk_bath.sh',NULL,'A','Snapshot x9w strict-bulk bath qualification runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9w' AND path='Info/inputs/historical/run_0493x9w_vacuum_drop_bulk_bath.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9x','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9x_vacuum_drop_crossing.sh',NULL,'A','Snapshot x9x crossing-time reflection runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9x' AND path='Info/inputs/historical/run_0493x9x_vacuum_drop_crossing.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9y','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9y_vacuum_drop_pointwise.sh',NULL,'A','Snapshot x9y pointwise-side/bisection runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9y' AND path='Info/inputs/historical/run_0493x9y_vacuum_drop_pointwise.sh');
INSERT INTO evidence(object_id,evidence_type,path,commit_hash,confidence,notes)
SELECT 'milestone:0493x9z','HISTORICAL_SOURCE','Info/inputs/historical/run_0493x9z_vacuum_drop_individual.sh',NULL,'A','Snapshot x9z individual donor-reflection runner'
WHERE NOT EXISTS (SELECT 1 FROM evidence WHERE object_id='milestone:0493x9z' AND path='Info/inputs/historical/run_0493x9z_vacuum_drop_individual.sh');

-- Causal chronology and supersession/repair relations.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x9i','BUILDS_ON','milestone:0493x9h','A','x9i is the first wetting closure on the generic x9h wall geometry provider'),
('milestone:0493x9j','BUILDS_ON','milestone:0493x9i','A','x9j moves the Young condition from hard normal replacement to curvature-only ghost alpha'),
('milestone:0493x9k','BUILDS_ON','milestone:0493x9j','A','x9k replaces linear ghost extension by a depth-consistent sheared mirror'),
('milestone:0493x9l','BUILDS_ON','milestone:0493x9k','A','x9l moves the closure from ghost alpha to wall-face normal geometry'),
('milestone:0493x9m','BUILDS_ON','milestone:0493x9l','A','x9m follows the x9i-x9l negative/biased near-wall curvature experiments'),
('milestone:0493x9m','FIXES','milestone:0493x9l','A','x9m avoids wall-contaminated p3+Scharr support by using an off-support secant construction'),
('milestone:0493x9n','BUILDS_ON','milestone:0493x9m','A','x9n geometrically qualifies the x9m closure without changing it'),
('milestone:0493x9o','BUILDS_ON','milestone:0493x9n','A','x9o isolates tangential grid-phase sensitivity in the most sensitive x9n cases'),
('milestone:0493x9p','BUILDS_ON','milestone:0493x9m','A','x9p tests physical dynamic sessile relaxation of the statically qualified x9m closure'),
('milestone:0493x9q','BUILDS_ON','milestone:0493x9m','A','x9q uses the x9m contact closure inside a strongly time-dependent jet/topology benchmark'),
('milestone:0493x9q','REFERENCES','milestone:0493x9p','C','x9q follows the sessile dynamic qualification but is an exploratory topology test, not an extension of its measurement model'),
('milestone:0493x9q','REFERENCES','milestone:0493x9d','A','x9q exercises the active bulk Laplace pressure-jump path'),
('milestone:0493x9r','BUILDS_ON','milestone:0493x9d','A','x9r regularizes the active x9d sigma*kappa path only below the resolved curvature scale'),
('milestone:0493x9r','REFERENCES','milestone:0493x9q','A','x9r is motivated by sub-grid curvature blow-up isolated in the dripping-jet ablations'),
('milestone:0493x9s','BUILDS_ON','milestone:0493x9r','A','x9s uses the capillary chain including resolution cutoff for parametric wall/puddle impact'),
('milestone:0493x9t','BUILDS_ON','milestone:0493x9s','A','x9t adds kinetic liquid-vacuum retention on the x9s free-drop/splash scaffold'),
('milestone:0493x9u','BUILDS_ON','milestone:0493x9t','A','x9u extends reflection to support-edge exits and bounded inward baths'),
('milestone:0493x9v','BUILDS_ON','milestone:0493x9u','A','x9v observes exactly x9u physics and decomposes remaining escape routes'),
('milestone:0493x9w','BUILDS_ON','milestone:0493x9v','A','x9w implements the strict-bulk bath correction identified by x9v'),
('milestone:0493x9w','FIXES','milestone:0493x9u','A','x9w forbids alpha<0.5 occupied halo cells as recoil baths'),
('milestone:0493x9x','BUILDS_ON','milestone:0493x9w','A','x9x changes reflection triggering to an actual predicted physical alpha crossing'),
('milestone:0493x9y','BUILDS_ON','milestone:0493x9x','A','x9y refines start-side classification and crossing location pointwise'),
('milestone:0493x9y','FIXES','milestone:0493x9x','A','x9y removes cell-centre interior aliasing and bounds crossing location by bisection'),
('milestone:0493x9z','BUILDS_ON','milestone:0493x9y','A','x9z individualizes donor normals and shifts conservation reaction to affine bath compensation'),
('milestone:0493x9z','FIXES','milestone:0493x9y','A','x9z enforces the inward condition separately for every applied donor while retaining exact P/K');

-- Reconcile every attested x9 identity with the imported Git candidate audit.
UPDATE git_milestone_candidates
SET status='LINKED', linked_milestone_object_id='milestone:0493' || label
WHERE label IN ('x9i','x9j','x9k','x9l','x9m','x9n','x9o','x9p','x9q','x9r','x9s','x9t','x9u','x9v','x9w','x9x','x9y','x9z')
  AND EXISTS (SELECT 1 FROM milestones m WHERE m.object_id='milestone:0493' || git_milestone_candidates.label);

-- Direct parameter/control associations for identities created after automatic inventory inference.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9i','A','x9i introduces the persistent prescribed Young angle' FROM symbols WHERE canonical_name='phaseInterfaceContactAngleDegrees';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9j','B','x9j consumes the prescribed Young angle through ghost alpha' FROM symbols WHERE canonical_name='phaseInterfaceContactAngleDegrees';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9k','B','x9k consumes the prescribed Young angle through sheared-mirror ghost alpha' FROM symbols WHERE canonical_name='phaseInterfaceContactAngleDegrees';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9l','B','x9l consumes the prescribed Young angle in wall-face normal reconstruction' FROM symbols WHERE canonical_name='phaseInterfaceContactAngleDegrees';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9m','A','x9m consumes the persistent prescribed Young angle' FROM symbols WHERE canonical_name='phaseInterfaceContactAngleDegrees';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9r','A','x9r introduces/uses the minimum resolved capillary radius' FROM symbols WHERE canonical_name='surfaceTensionMinRadiusCells';

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9i','B','test-only hard-normal baseline gate retained after x9j' FROM symbols WHERE canonical_name='MPCD_Q6_CONTACT_ANGLE_HARD_NORMAL_0493X9I';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9l','A','x9l experimental wall-face closure gate' FROM symbols WHERE canonical_name='MPCD_Q6_CONTACT_ANGLE_WALL_FACE_0493X9L';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT object_id,'ASSOCIATED_WITH','milestone:0493x9m','A','x9m off-support static wetting gate' FROM symbols WHERE canonical_name='MPCD_Q6_CONTACT_ANGLE_OFFSUPPORT_0493X9M';

-- Kinetic reflection and optional transmission/evaporation controls apply throughout x9t-x9z.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT s.object_id,'ASSOCIATED_WITH',m.object_id,'A','late-x9 kinetic retention/reflection control'
FROM symbols s JOIN milestones m ON m.milestone_id IN ('x9t','x9u','x9v','x9w','x9x','x9y','x9z')
WHERE s.canonical_name='phaseInterfaceKineticReflectionFraction';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT s.object_id,'ASSOCIATED_WITH',m.object_id,'B','late-x9 transmitted crossing can use the configured evaporation/target-type path'
FROM symbols s JOIN milestones m ON m.milestone_id IN ('x9t','x9u','x9v','x9w','x9x','x9y','x9z')
WHERE s.canonical_name='phaseInterfaceEvaporationTargetType';

-- Current-tree runners/analyzers when present in the actual repository.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9n','QUALIFIED_BY',object_id,'A','x9n geometric qualification runner' FROM artifacts WHERE path='scripts/run_0493x9n_geometric_qualification.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9o','QUALIFIED_BY',object_id,'A','x9o grid-phase qualification runner' FROM artifacts WHERE path='scripts/run_0493x9o_phase_qualification.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9p','QUALIFIED_BY',object_id,'A','x9p dynamic sessile-drop qualification runner' FROM artifacts WHERE path='scripts/run_0493x9p_sessile_dynamics.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9q','QUALIFIED_BY',object_id,'A','x9q dripping-jet potentiality runner' FROM artifacts WHERE path='scripts/run_0493x9q_dripping_jet_potential.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9r','QUALIFIED_BY',object_id,'A','x9r capillary cutoff stress/causal runner' FROM artifacts WHERE path='scripts/run_0493x9r_dripping_jet_cutoff.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9s','QUALIFIED_BY',object_id,'A','x9s parametric splash runner' FROM artifacts WHERE path='scripts/run_0493x9s_splash.sh';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9t','ANALYZED_BY',object_id,'A','x9t reflection audit analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9t_reflection.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9u','ANALYZED_BY',object_id,'A','x9u support-edge reflection analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9u_reflection.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9v','ANALYZED_BY',object_id,'A','x9v escape-path diagnostic analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9v_escape.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9w','ANALYZED_BY',object_id,'A','x9w strict-bulk bath analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9w_bulk_bath.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9x','ANALYZED_BY',object_id,'A','x9x physical crossing analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9x_crossing.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9y','ANALYZED_BY',object_id,'A','x9y pointwise/bisection analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9y_pointwise.py';
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
SELECT 'milestone:0493x9z','ANALYZED_BY',object_id,'A','x9z individual donor reflection analyzer' FROM artifacts WHERE path='scripts/analyze_0493x9z_individual.py';
