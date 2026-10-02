-- V4.46: article-oriented characterization from x20c through the current x21e frontier.
-- 2026-09-20. Documentary curation only: no solver/source/runtime behavior is modified.
-- Curations 0043-0045 already preserve x19d, x20a and x20b; this file closes their
-- completed statuses and adds x20c-x20j plus x21a-x21e with evidence-driven qualifiers.
PRAGMA foreign_keys=ON;

-- x20a/x20b were introduced as READY_FOR_LOCAL_CAMPAIGN. Preserve the records but
-- update their status now that the article data acquisition has completed.
UPDATE milestones
SET status='COMPLETED_SUPERSEDED_TG_BY_X20B',
    notes=COALESCE(notes,'') ||
      ' Campaign completed. Final article transport assembly retains x20a MSD and acoustic measurements, while Taylor-Green viscosity is replaced by the longer x20b requalification where available. Nominal x20a MSD Q6-G-F/SRC ratio is about 1.122; acoustic SRC propagation remains close to sqrt(kBT/m).'
WHERE object_id='milestone:0493x20a';

UPDATE milestones
SET status='COMPLETED_STATUS_AWARE_ARTICLE_DATASET',
    notes=COALESCE(notes,'') ||
      ' Campaign completed: 12 physical points x 2 models x 6 matched seeds = 144 TG runs on 128x128, with PASS/REVIEW/INVALID retained pointwise rather than hidden by a global verdict. Final transport tables combine x20b TG with x20a MSD.'
WHERE object_id='milestone:0493x20b';

-- ---------------------------------------------------------------------------
-- x20c-x20j: article transport / longitudinal characterization.
-- ---------------------------------------------------------------------------
INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES
('milestone:0493x20c','MILESTONE','x20c alpha extension','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20d','MILESTONE','x20d high-alpha TG confirmation','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20e','MILESTONE','x20e nominal longitudinal pilot','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20f','MILESTONE','x20f reduced longitudinal map','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20g','MILESTONE','x20g historical angle-path audit','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20h','MILESTONE','x20h fresh x20f angle-path probe','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20i','MILESTONE','x20i clean longitudinal alpha rerun','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x20j','MILESTONE','x20j alpha175 long-wave qualification','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x21a','MILESTONE','x21a strong capillary static pilot','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x21b','MILESTONE','x21b weak-capillary long-baseline pilot','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x21c','MILESTONE','x21c shadow Young-Laplace protocol','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x21d','MILESTONE','x21d article capillary pilot','curation:0046_0493x20c_x21e_article_characterization'),
('milestone:0493x21e','MILESTONE','x21e article capillary radius campaign','curation:0046_0493x20c_x21e_article_characterization');

INSERT OR REPLACE INTO milestones(
 object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
 nature,domain,status,confidence,introduced_date,introduced_commit,tag,notes,
 source_file,source_row
) VALUES
('milestone:0493x20c','0493x20c','x20c','0493x20c',
 'JCP article characterization','Extension en angle SRC du jeu transport article',
 'Etend le balayage alpha_SRC avec TG et MSD apparies SRC/Q6-G-F. Les points 30 et 45 deg sont conserves comme mesures article; les viscosites haute-angle 165/175 deg sont traitees comme preliminaires et remplacees par x20d.',
 'QUALIFICATION','BULK_FLUID','COMPLETED_ALPHA_EXTENSION','A','2026-09-19',NULL,NULL,
 'Six seeds TG/MSD par modele sur les extensions; les statuts PASS/REVIEW/INVALID sont conserves. La table finale article preserve explicitement la provenance x20c.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/x20c_results_aggregated.csv',NULL),

('milestone:0493x20d','0493x20d','x20d','0493x20d',
 'JCP article characterization','Confirmation Taylor-Green haute-angle a resolution accrue',
 'Requalifie alpha_SRC=165 et 175 deg sur TG 256x256, mode (1,1), six seeds par modele. Les quatre ensembles SRC/Q6-G-F passent les criteres de viscosite et remplacent les estimations haute-angle x20c.',
 'QUALIFICATION','BULK_FLUID','PASS_HIGH_ALPHA_TG_CONFIRMATION','A','2026-09-19',NULL,NULL,
 'alpha165: nu_SRC=0.004208334604, nu_Q6GF=0.003105024404, ratio apparie=0.740344. alpha175: nu_SRC=0.009431787002, nu_Q6GF=0.005861715686, ratio apparie=0.622753. Les MSD x20c restent utilises.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/x20d_results_aggregated.csv',NULL),

('milestone:0493x20e','0493x20e','x20e','0493x20e',
 'JCP article characterization','Pilote longitudinal nominal SRC / Q6-G-F',
 'Teste directement la propagation longitudinale au point nominal. SRC presente un mode propagatif resolu proche de l echelle thermique; la fermeture Q6-G-F supprime le mode longitudinal coherent sous le protocole.',
 'QUALIFICATION','LONGITUDINAL','PASS_NOMINAL_LONGITUDINAL_DISCRIMINATION','A','2026-09-19',NULL,NULL,
 'Ma=0.05: c_SRC=0.353910; Ma=0.10: c_SRC=0.350673. Q6-G-F: c non assignable; amplitude longitudinale fortement reduite. Le residu de divergence sur les faces projetees est interprete comme residu a la contrainte active, distinct de la divergence cellulaire reconstruite.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_pilot_decision_0493x20e.txt',NULL),

('milestone:0493x20f','0493x20f','x20f','0493x20f',
 'JCP article characterization','Carte longitudinale reduite',
 'Etend le pilote longitudinal a ell bas/haut, gamma=6 et angles extremes. Les branches non-angle sont exploitables; les sorties alpha30/alpha175 de la campagne initiale sont invalidees par reutilisation/staleness et ne sont pas retenues scientifiquement.',
 'QUALIFICATION','LONGITUDINAL','PARTIAL_VALID_NONANGLE_ALPHA_BRANCHES_INVALID','A','2026-09-19',NULL,NULL,
 'ell_low Q6-G-F AL_tail=0.03764 et residu projete/pre=0.002434; ell_high 0.03977 et 0.003710; gamma6 0.06256 et 0.002101. Les branches alpha de cette campagne ne doivent pas etre reutilisees.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_map_decision_0493x20f.txt',NULL),

('milestone:0493x20g','0493x20g','x20g','0493x20g',
 'JCP article characterization','Audit historique de sensibilite a l angle SRC',
 'Verifie sur le chemin historique de calibration que alpha=30 et 175 deg conduisent a des trajectoires differentes des le premier pas; ecarte une insensibilite intrinseque du solveur a rotationAngle.',
 'DIAGNOSTIC','LONGITUDINAL','PASS_HISTORICAL_PATH_ANGLE_SENSITIVE','A','2026-09-19',NULL,NULL,
 'Audit sans modification de physique; binaire historique ab718f8f... et chemin standalone historique.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/audit_rotation_angle_0493x20g.txt',NULL),

('milestone:0493x20h','0493x20h','x20h','0493x20h',
 'JCP article characterization','Probe frais du chemin x20f sensible a l angle',
 'Rejoue le chemin helper x20f dans des environnements ORIGINAL/SYNCED/SANITIZED et montre dans les trois cas une divergence alpha30/175 des le step 1. La collision de sorties x20f est donc attribuee a la campagne reutilisee/stale, pas au chemin numerique.',
 'DIAGNOSTIC','LONGITUDINAL','PASS_FRESH_X20F_PATH_ANGLE_SENSITIVE','A','2026-09-19',NULL,NULL,
 'Aucune physique modifiee; diagnostic de provenance/campagne.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/x20h_verdict.txt',NULL),

('milestone:0493x20i','0493x20i','x20i','0493x20i',
 'JCP article characterization','Rerun longitudinal propre alpha30 / alpha175',
 'Rejoue les angles extremes dans des repertoires propres. A alpha30 SRC redevient propagatif et Q6-G-F reste non resolvable; a alpha175 la longueur d onde standard reste trop amortie pour le critere zero-crossing.',
 'QUALIFICATION','LONGITUDINAL','COMPLETED_CLEAN_ALPHA_RERUN','A','2026-09-19',NULL,NULL,
 'alpha30 SRC c=0.358544, Q6-G-F AL_tail=0.04694 avec residu projete/pre=0.004122. alpha175 standard: non resolvable pour SRC et Q6-G-F; ce point motive x20j.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_alpha_clean_decision_0493x20i.txt',NULL),

('milestone:0493x20j','0493x20j','x20j','0493x20j',
 'JCP article characterization','Qualification longitudinale longue longueur d onde a alpha175',
 'Allonge la longueur d onde a alpha_SRC=175 deg et ajoute un estimateur amorti. SRC presente un mode longitudinal amorti mais propagatif; la fermeture Q6-G-F reste non resolvable.',
 'QUALIFICATION','LONGITUDINAL','PASS_LONGWAVE_DISCRIMINATION_DAMPED_FALLBACK','A','2026-09-19',NULL,NULL,
 'SRC: c_damped=0.364249, R2 moyen=0.991676, beta/omega moyen=0.16275. Q6-G-F: damped fit non resolvable, R2 moyen=0.40558, beta/omega moyen=2.2958. Aucune vitesse acoustique n est assignee a la fermeture.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_alpha175_longwave_decision_0493x20j.txt',NULL),

('milestone:0493x21a','0493x21a','x21a','0493x21a',
 'JCP article characterization','Pilote statique capillaire fort',
 'Pilote de goutte R/h=64 a sigma=10000 avec la chaine surface libre qualifiee. Il confirme qu une goutte fortement capillaire peut rester macroscopiquement reguliere mais montre que la pression Q6 absolue et la courbure brute x9e ne constituent pas, seules, une calibration Young-Laplace propre.',
 'CALIBRATOR','SURFACE_TENSION','PILOT_NOT_RETAINED_FOR_FINAL_CALIBRATION','A','2026-09-19',NULL,NULL,
 'Le pilote sert a definir le protocole article; il ne remet pas en cause le mecanisme capillaire. La calibration finale doit isoler l increment capillaire et employer la courbure effectivement injectee.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/traceability_0493x21a.txt',NULL),

('milestone:0493x21b','0493x21b','x21b','0493x21b',
 'JCP article characterization','Pilote faible sigma avec controle sigma0 long',
 'Teste sigma=120 a R/h=64 avec une baseline sigma=0 longue. Le protocole est abandonne car la goutte libre sigma0 evolue/disperse et cesse d etre un controle geometriquement comparable.',
 'CALIBRATOR','SURFACE_TENSION','SUPERSEDED_PROTOCOL','A','2026-09-19',NULL,NULL,
 'Resultat methodologique: ne pas utiliser de baseline sigma0 libre longue pour la calibration statique; utiliser des probes courts issus du meme checkpoint.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/README_0493x21b.md',NULL),

('milestone:0493x21c','0493x21c','x21c','0493x21c',
 'JCP article characterization','Protocole shadow Young-Laplace sans baseline libre longue',
 'Selectionne trois checkpoints d une goutte active sigma=945 sur plateau geometrique, puis lance depuis chaque etat des probes 2-step sigma=945/sigma=0 apparies, six repetitions. Le protocole isole un increment de pression a geometrie identique.',
 'CALIBRATOR','SURFACE_TENSION','PASS_SHADOW_PROTOCOL_PHYSICS_VERDICT_NOT_ASSIGNED','A','2026-09-19',NULL,NULL,
 '18/18 paires integres. deltaP global moyen=-44303.8, CV global inter-checkpoint=6.24%; CV intra-checkpoint ~1e-6 et mismatch rayon/aire nul au premier pas. Le collecteur no-code n estime volontairement pas sigma_eff avec curvatureMean brut. Le patch diagnostic face-kappa propose ensuite a ete retire/non retenu; aucun changement solveur canonique.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/shadow_collection_report_0493x21c_nocode.txt',NULL),

('milestone:0493x21d','0493x21d','x21d','0493x21d',
 'JCP article characterization','Pilote article de goutte statique sigma=10000',
 'Valide sur un seul cas R/h=64 la chaine de production des donnees article: plateau, rayon effectif, pression, vitesse parasite et clipping, avant balayage multi-rayons. La courbure brute x9e est conservee comme diagnostic mais pas comme metrique article.',
 'CALIBRATOR','SURFACE_TENSION','PASS_PIPELINE_ARTICLE_STATIC_DROP','A','2026-09-20',NULL,NULL,
 'Plateau 750..1500 PASS; Reff/h=59.6181; drift Reff=0.036%, aire=0.073%; axisRatio=1.02284; clipMean=1.998%, clipMax=5.518%. Le binaire courant 422a199e... differe du binaire historique seulement par x19d dans src_mpcd_base.cpp; le coeur capillaire cuda_q6_resident_0400.cu est bit-a-bit identique au commit 74297ce.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/capillary_pilot_report_0493x21d.txt',NULL),

('milestone:0493x21e','0493x21e','x21e','0493x21e',
 'JCP article characterization','Campagne multi-rayons pour figure/tableau capillaires article',
 'Campagne sigma=10000, R/h=40,48,56,64,72,80, trois seeds, 1500 steps actifs puis shadows 2-step sigma/sigma0. La courbure article est reconstruite offline suivant exactement x6c -> p3/Scharr -> interpolation face alpha=0.5 -> cutoff x9r et validee contre les compteurs runtime.',
 'QUALIFICATION','SURFACE_TENSION','IN_PROGRESS_ARTICLE_RADIUS_CAMPAIGN','A','2026-09-20',NULL,NULL,
 'Objectif unique: produire fig_07_capillary_calibration, table_03_capillary_calibration et table_S3_capillary_map. Premier run R40 seed4932401 termine avec plateau PASS 600..1500 et checkpoint 1500. Un bug de parsing CRLF du chemin checkpoint a ete corrige dans runner fix2; aucune physique n a change.',
 'Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/README_0493x21e_fix2.md',NULL);

-- Primary evidence files.
INSERT INTO evidence(object_id,evidence_type,path,confidence,notes) VALUES
('milestone:0493x20c','ARTICLE_DATASET','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/article_transport_table_final.csv','A','Final assembled transport table; x20d replaces high-alpha TG viscosities, x20a/x20c retain MSD provenance.'),
('milestone:0493x20d','ARTICLE_DATASET','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/x20d_ratios_paired.csv','A','Matched-seed high-alpha TG ratios.'),
('milestone:0493x20e','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_pilot_decision_0493x20e.txt','A','Nominal acoustic discrimination decision.'),
('milestone:0493x20f','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_map_decision_0493x20f.txt','A','Reduced longitudinal map with non-angle valid branches and contaminated angle branches documented.'),
('milestone:0493x20g','AUDIT','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/audit_rotation_angle_0493x20g.txt','A','Historical-path rotation-angle sensitivity audit.'),
('milestone:0493x20h','AUDIT','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/x20h_verdict.txt','A','Fresh x20f helper-path angle sensitivity audit.'),
('milestone:0493x20i','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_alpha_clean_decision_0493x20i.txt','A','Clean alpha rerun decision.'),
('milestone:0493x20j','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/longitudinal_alpha175_longwave_decision_0493x20j.txt','A','Long-wave damped-fit qualification.'),
('milestone:0493x21c','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/shadow_checkpoint_pressure_summary_0493x21c_nocode.csv','A','Checkpoint-wise paired shadow pressure statistics.'),
('milestone:0493x21d','ANALYSIS','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/capillary_pilot_realization_0493x21d.csv','A','One-run article-pipeline pilot realization.'),
('milestone:0493x21d','PROVENANCE_AUDIT','Info/inputs/historical/0493x20c_x21e_article_characterization_20260920/binary_provenance_audit_0493x21d.txt','A','Shows current capillary CUDA core and params/build script identical to reference commit while x19d diagnostic/performance changes reside in src_mpcd_base.cpp.');

-- Causal/documentary links.
INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES
('milestone:0493x20c','BUILDS_ON','milestone:0493x20b','A','extends the article transport map along alpha_SRC'),
('milestone:0493x20d','BUILDS_ON','milestone:0493x20c','A','replaces preliminary high-alpha viscosity measurements'),
('milestone:0493x20e','BUILDS_ON','milestone:0493x20b','A','uses the article nominal fluid and separates longitudinal propagation from transverse transport'),
('milestone:0493x20f','BUILDS_ON','milestone:0493x20e','A','reduced longitudinal parameter map'),
('milestone:0493x20g','REFERENCES','milestone:0493x20f','A','tests whether the angle anomaly could arise from an angle-insensitive runtime path'),
('milestone:0493x20h','REFERENCES','milestone:0493x20f','A','tests the exact fresh x20f helper path'),
('milestone:0493x20i','BUILDS_ON','milestone:0493x20h','A','clean replacement of contaminated x20f angle branches'),
('milestone:0493x20j','BUILDS_ON','milestone:0493x20i','A','long-wave resolution of the alpha175 SRC branch'),
('milestone:0493x21a','BUILDS_ON','milestone:0493x13h','A','starts article-specific static capillary characterization from the qualified surface-free chain'),
('milestone:0493x21b','BUILDS_ON','milestone:0493x21a','A','tests lower sigma but exposes the long sigma0 baseline limitation'),
('milestone:0493x21c','BUILDS_ON','milestone:0493x21b','A','replaces long sigma0 evolution by same-checkpoint short shadows'),
('milestone:0493x21d','BUILDS_ON','milestone:0493x21c','A','validates the article measurement pipeline at sigma=10000'),
('milestone:0493x21e','BUILDS_ON','milestone:0493x21d','A','multi-radius production campaign for Section 3.4 figures and tables');
