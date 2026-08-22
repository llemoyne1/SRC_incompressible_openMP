# Mise à jour projet 0493x11c — tension superficielle + surface libre cinétique

Cette livraison consolide le rapport jusqu'à x9r avec les cycles x10q/x11c et met à jour les deux inventaires CSV.
La source x8u/x7q fournie avec la demande est conservée comme historique; la base documentaire x9r, déjà plus récente, a été utilisée pour ne pas perdre les ajouts capillaires x9.

## Rapport

Fichier: `rapport_mpcd_incompressible_complete_0493x11c_surface_tension_kinetic.tex`

Ajouts principaux:
- séparation explicite entre saut de Laplace Q6-g-f et rétention cinétique des particules;
- algorithme final x10o+x10p+x10q: polyligne alpha=0.5, vitesse normale Q6/RT0, enveloppe `delta=min(3 dt sqrt(kBT/m),0.75h)`, collision segment mobile, recouvrement initial et fallback 7x7 rare;
- absence volontaire de B8, réaction globale, merge/resampling de cohésion et scellement global;
- sémantique d'évaporation retenue via `phaseInterfaceKineticReflectionFraction`: r=1 qualifié; r<1 = transmission stochastique préparée mais non thermodynamiquement calibrée;
- limites explicites: pas de Hertz-Knudsen, chaleur latente, pression de vapeur, condensation réciproque ni couplage gaz complet;
- validation Young-Laplace appariée: pente contrainte 0.9587044 sur `sigma*<kappa>` (21 paires, 12 baselines sigma=0), fit libre 1.0310109;
- validation d'ondes capillaires: pente `omega_fit^2/omega_theory^2=0.98842059`, R2 moyen 0.99664384;
- qualification morphologique des vidéos dripping à sigma 650/1500/2250.

## Inventaires

- `src_mpcd_params_inventory_consolidated_0493x11c_surface_tension_kinetic.csv`: base x9r + `phaseInterfaceKineticReflectionFraction` et `phaseInterfaceEvaporationTargetType`, plus remarques x11 sur sigma/cutoff/sélecteurs/mouillage.
- `src_mpcd_env_flags_inventory_consolidated_0493x11c_surface_tension_kinetic.csv`: base x9r + alias runners d'évaporation, flags x10j..x10p utiles, gate x11c sigma=0. x10q est documenté comme comportement source sans flag indépendant.

## Vidéos examinées

- `drip_mass_650.avi`: 1000x700, 30 fps, 299 frames, 9.967 s.
- `drip_mass_1500_gainx100.avi`: 1000x700, 30 fps, 300 frames, 10.000 s.
- `drip_mass_2250.avi`: 1000x700, 30 fps, 500 frames, 16.667 s.

Interprétation qualitative retenue: sigma=650 produit un ligament beaucoup plus long; sigma=1500 montre clairement croissance pendante, pincement/détachement et impact; sigma=2250 conserve plus longtemps une géométrie compacte/arrondie. Les durées n'étant pas identiques, ces vidéos ne sont pas utilisées comme mesure quantitative de fréquence.
