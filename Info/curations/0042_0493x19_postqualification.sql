-- V4.42: x19a/x19b/x19c post-qualification closure of rotational solid/FSI chain
-- (2026-09-17). Records local qualification results; no new runtime physics.
PRAGMA foreign_keys=ON;

UPDATE milestones
SET status='QUALIFIED',
    confidence='A',
    notes=COALESCE(notes,'') ||
      ' FINAL QUALIFICATION 2026-09-17: planar prescribed Lagrangian Couette, late window steps 5000..15000 over 11 dumps. Bounceback relative RMSE=0.0379074 and shape R2=0.984009; specular relative RMSE=0.598073. This closes x19a as the planar tangential momentum-transfer gate. It does not by itself claim curved-wall torque accuracy.'
WHERE object_id='milestone:0493x19a';

UPDATE milestones
SET status='QUALIFIED_WITH_DOCUMENTED_TORQUE_BIAS',
    confidence='A',
    notes=COALESCE(notes,'') ||
      ' FINAL QUALIFICATION 2026-09-17: the x19b-fix3 17-stage angular-momentum audit closes telescopically at relRMS=1.804e-16 and reproduces the independent x17 wall accounting at relRMS=4.022e-14, excluding an uninstrumented angular-momentum channel in the measured timestep. Matched four-seed src-q6 Taylor-Green calibration gives nu=2.3313138152e-4, std=1.0569841665e-5, SEM=5.2849208326e-6, CV=0.045339; all fits PASS with R2 about 0.9981. High-SNR x19b-fix4 at Omega=0.20 gives effective Ri=0.199976991, Ro=0.349989344, rho2D=786521.317, tangential Couette half-difference T_C=29.9952367 +/-0.752329 block SEM versus matched-TG theory 27.3626194, relative difference +9.62122%. Common tangential half-sum=-3.20952218 +/-1.82092. Velocity profile relRMSE=0.0325029, R2=0.985311, gain=0.976747, radial/Ui=0.0180787. Curved prescribed-wall hydrodynamics are therefore qualified with an explicit approximately 10% torque bias.'
WHERE object_id='milestone:0493x19b';

UPDATE milestones
SET status='QUALIFIED_WITH_DOCUMENTED_TORQUE_BIAS',
    confidence='A',
    notes=COALESCE(notes,'') ||
      ' FINAL LOCAL RESULT 2026-09-17: T_C=29.9952367 +/-0.752329 block SEM against matched-TG 27.3626194 (+9.62122%); common half-sum=-3.20952218 +/-1.82092; profile relRMSE=0.0325029, R2=0.985311, gain=0.976747, radial/Ui=0.0180787. This is the quantitative prescribed curved-wall reference used by x19c.'
WHERE object_id='milestone:0493x19b-fix4';

UPDATE milestones
SET status='QUALIFIED',
    confidence='A',
    notes=COALESCE(notes,'') ||
      ' FINAL END-TO-END QUALIFICATION 2026-09-17 over free-rotor steps 500..5000 (4501 rows): I=1976.51919; discrete mechanics closure relRMS=8.007e-15, maxAbs=2.753e-14; independent wall cross-check relRMS=0. Hydro torque=-23.5995409 +/-0.528601 block SEM versus prescribed x19b reference -23.3998141 +/-1.92345, relative difference -0.85354%, z=-0.100125. External torque=23.3998141 and net torque=-0.199726735 +/-0.528601, compatible with zero. Mean Omega=0.192093421 +/-0.000948921 versus target 0.2 +/-0.0164399 reference SEM, relative error -3.95329%, z=-0.48014; first/last Omega=0.193184329/0.191002027 and omegaSlope/step=-8.889e-07. Late fluid profile relRMSE=0.036046, R2=0.981934, gain=0.956627, radial/Ui=0.0182496. All mechanics, omega, hydro, stationary and profile gates PASS. This qualifies the bidirectional rigid-solid rotational FSI loop from kinetic wall impulse through generalized torque and rigid-body integration back to wall velocity. Scope does not extend this analytic qualification to free translation, contact/collision mechanics or multi-solid interactions.'
WHERE object_id='milestone:0493x19c';

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19a','OPERATOR_VALIDATION',
  'Info/docs/CURATION_0493X19_POSTQUALIFICATION_V4_42.md','A',
  'Final local x19a planar Couette qualification: bounceback relRMSE 0.0379074, shape R2 0.984009; specular relRMSE 0.598073.'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19b-fix4','OPERATOR_VALIDATION',
  'Info/docs/CURATION_0493X19_POSTQUALIFICATION_V4_42.md','A',
  'Final local x19b high-SNR annular Couette qualification against matched four-seed TG viscosity; +9.62122% torque bias explicitly retained.'
);

INSERT INTO evidence(object_id,evidence_type,path,confidence,notes)
VALUES(
  'milestone:0493x19c','OPERATOR_VALIDATION',
  'Info/docs/CURATION_0493X19_POSTQUALIFICATION_V4_42.md','A',
  'Final local x19c free-rotor end-to-end qualification: mechanics and wall accounting close at roundoff, hydrodynamic load reproduces prescribed x19b reference, and all automated gates PASS.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'milestone:0493x19b-fix4','QUALIFIES','milestone:0493x19b','A',
  'Matched-TG high-SNR annular Couette run closes the prescribed curved-wall x19b qualification while retaining the measured +9.6% torque bias.'
);

INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
VALUES(
  'milestone:0493x19c','QUALIFIES','milestone:0493x19b-fix4','A',
  'The free rotor reproduces the independently measured prescribed-run hydrodynamic generalized load while closing rigid-body mechanics and wall action-reaction at roundoff.'
);
