# Clés de contrôle et métadonnées de sortie

> Clés qui ne sont pas des paramètres solveur `.kv` : contrôles externes (par exemple LiveVis) et clés de métadonnées de sortie.

## CONTROL

| Nom | Type | Défaut | Rôle |
|---|---|---|---|
| `livevis_control.kv:alpha` | double [0,1] | 0.08 historique si absent; 1.0 recommandé pour bascule immédiate | Contrôle le mélange temporel entre le champ courant scalar et le champ affiché displayScalar. |
| `livevis_control.kv:clip` | double; <=0 active comportement auto/default selon renderer | initialisé depuis LIVE_VIS_CLIP | Change à chaud l’échelle de saturation/clip du champ affiché. |
| `livevis_control.kv:colormap` | blue_red \| gray \| thermal | initialisé depuis LIVE_VIS_COLORMAP | Change à chaud le colormap utilisé pour convertir le champ scalaire en RGBA. |
| `livevis_control.kv:field` | ux \| uy \| vx \| vy \| speed \| density \| mass \| N \| n \| count \| population \| particle_count \| cell_count \| vorticity \| omega \| curl \| chi \| topo_chi \| alpha \| darcy_alpha \| darcy_power \| darcy \| brinkman_power \| curvature \| kappa \| curvature_x9b \| kappa_x9b \| curvature_p1 \| kappa_p1 \| curvature_x9c \| kappa_x9c \| curvature_p3 \| kappa_p3 \| alpha_x6c \| phase_alpha \| phase_alpha_x6c \| liquid_fraction_x6c | initialisé depuis LIVE_VIS_FIELD/SRC_LIVE_VIS_FIELD | Change à chaud le champ scalaire affiché. |
| `livevis_control.kv:filterMode` | none \| ema | none | Choisit le mode de filtrage temporel du recorder. |
| `livevis_control.kv:filterSampleEvery` | entier >= 1 | initialisé depuis SRC_FILTERED_FIELD_SAMPLE_EVERY/MPCD_FILTERED_FIELD_SAMPLE_EVERY ou 1 | Cadence d’échantillonnage interne des champs conservatifs. |
| `livevis_control.kv:filterTau` | double >= 0 | initialisé depuis SRC_FILTERED_FIELD_TAU/MPCD_FILTERED_FIELD_TAU ou 0.0 | Temps caractéristique de l’EMA du recorder. |
| `livevis_control.kv:gain` | double > 0 | initialisé depuis LIVE_VIS_GAIN | Change à chaud le gain multiplicatif de visualisation. |
| `livevis_control.kv:liveEvery` | entier >= 1 | initialisé depuis SRC_LIVE_VIS_EVERY/MPCD_LIVE_VIS_EVERY; défaut code 10 si absent | Cadence de production des frames livevis. Sert aussi de cadence par défaut des dumps filtrés quand recordEvery est absent ou <=0. |
| `livevis_control.kv:liveGridNx` | entier >= 16 | initialisé depuis SRC_LIVE_VIS_NX/MPCD_LIVE_VIS_NX ou 300 | Change la résolution X de la grille livevis/recording pendant la preview. |
| `livevis_control.kv:liveGridNy` | entier >= 16 | initialisé depuis SRC_LIVE_VIS_NY/MPCD_LIVE_VIS_NY ou 80 | Change la résolution Y de la grille livevis/recording pendant la preview. |
| `livevis_control.kv:particleTypeFilter` | entier | -1 | Filtre les particules avant accumulation livevis: rho/N/ux/uy/speed/vorticity, quiver CPU, et dumps filtrés 0432. |
| `livevis_control.kv:quiverMinSpeed` | double >= 0 | 0 | Change à chaud le seuil minimal de vitesse pour dessiner les segments. |
| `livevis_control.kv:quiverNx` | entier >= 1 | 60 | Change à chaud le nombre de colonnes de la grille quiver. |
| `livevis_control.kv:quiverNy` | entier >= 1 | 32 | Change à chaud le nombre de lignes de la grille quiver. |
| `livevis_control.kv:quiverScale` | double | -1 | Change à chaud le gain manuel des segments vitesse. |
| `livevis_control.kv:quiverSmoothPasses` | entier; -1 ou >=0 | -1 | Change à chaud le lissage des vecteurs quiver. |
| `livevis_control.kv:recordEnable` | booléen/truthy | false | Déclenche le démarrage/arrêt d’une session de dumps filtrés. |
| `livevis_control.kv:recordEvery` | entier; absent ou <=0 suit liveEvery; >0 override expert | suit liveEvery | Cadence d’écriture des fichiers de champs filtrés; par défaut alignée sur la cadence livevis runtime. |
| `livevis_control.kv:recordFields` | liste CSV de champs | current | Sélectionne les champs écrits en .f32. |
| `livevis_control.kv:recordFormat` | f32 \| float32 | f32 | Format des dumps de champs. |
| `livevis_control.kv:recordSession` | chaîne | session_<startStep> | Nomme le sous-dossier de session sous outputDir/recordings/. |
| `livevis_control.kv:recordStride` | entier >= 1 | absent | Override expert relatif à l’affichage: enregistre une frame affichée sur N. |
| `livevis_control.kv:smoothPasses` | entier >= 0 | initialisé depuis LIVE_VIS_SMOOTH_PASSES | Change à chaud le nombre de passes de lissage du champ affiché. |

## OUTPUT

| Nom | Type | Défaut | Rôle |
|---|---|---|---|
| `recordings/manifest.kv:particleTypeFilter` | entier | valeur verrouillée au démarrage/relock de session | Documente dans le manifest.kv la population effectivement utilisée pour les dumps .f32. |
| `recordings/manifest.kv:recordEverySource` | liveEvery \| override | calculé à l’ouverture de session | Trace dans manifest.kv l’origine de la cadence effective d’enregistrement. |
