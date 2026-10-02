# Curation V4.47 — réparation du jalon 0493x19d

Date : 2026-09-20

## Objet

Cette curation est exclusivement documentaire. Elle ne modifie ni le solveur, ni les runners,
ni les paramètres physiques, ni les résultats de simulation. Elle corrige l'absence de `x19d`
comme jalon autonome dans `/Info`.

## Vérification du patch primaire et du snapshot

Le package primaire `patch_0493x19d_hotpath_perf.zip` contient :

- `src/src_mpcd_base.cpp` ;
- `Info/curations/0043_0493x19d_hotpath_diagnostic_cleanup.sql` ;
- `Info/docs/CURATION_0493X19D_HOTPATH_DIAGNOSTIC_CLEANUP_V4_43.md`.

Ces trois fichiers sont bit-à-bit identiques à ceux du snapshot du dépôt du 20 septembre 2026.
SHA-256 vérifiés :

- `src/src_mpcd_base.cpp` : `4e3b345f437d010f8296ccea569480bb84aefadb31e6fb28b0ef44941660f4d1` ;
- curation 0043 : `d5de7cb34afe1cd09faf143892a02057b668baed9f1a6dcce9213cd7b1605e95` ;
- note V4.43 : `487bdea7b8d8f72a545f7ec0c0dc2d812656454ae18158e8b94c47e2c79a75f5`.

Le contenu source confirme les deux changements décrits par V4.43 : chemin désactivé du
`FullAngularAudit0493x19bFix3` sans allocation/copie inutile et retour immédiat des overloads
`record_cuda_resident_profile_0266()` lorsque le profiling résident est désactivé.

## Frontière x19 / x20

Le snapshot contient comme curations de fin de série :

- 0033 : x19a ;
- **0034 : absent du snapshot** ;
- 0035 : x19a-fix2 ;
- 0036 : x19b ;
- 0037 : x19b-fix1 ;
- 0038 : x19b-fix2 ;
- 0039 : x19b-fix3 ;
- 0040 : x19b-fix4 ;
- 0041 : x19c ;
- 0042 : post-qualification x19a/x19b/x19c ;
- 0043 : x19d ;
- 0044 : x20a ;
- 0045 : x20b ;
- 0046 : x20c–x21e.

L'absence de 0034 est conservée telle quelle : V4.47 ne reconstruit pas rétrospectivement une
curation inexistante et ne modifie pas l'historique antérieur à la frontière x19d.

La recherche dans les noms de fichiers et le contenu utile du snapshot ne trouve aucun `x19e` à
`x19z`. La recherche indépendante effectuée dans le dépôt de travail confirme également que le
dernier patch x19 est `x19d`, puis que la séquence passe à x20. En conséquence, aucun `x19s`
ni autre identité x19 intermédiaire n'est créé.

## Défaut documentaire de V4.43

`0043_0493x19d_hotpath_diagnostic_cleanup.sql` est correct sur le fond, mais ne crée pas
`milestone:0493x19d`. Il ajoute uniquement une note et une `PERFORMANCE_EVIDENCE` à
`milestone:0493x19b-fix3`. Après reconstruction de la base sans V4.47, `x19d` apparaît donc
seulement dans le texte des notes, pas comme entrée autonome de `jalons.md`,
`jalons_par_nature.md` ou `csv/jalons.csv`.

## Correction V4.47

V4.47 crée le jalon autonome `0493x19d` avec :

- nature : `OPTIMIZATION` ;
- domaine : `CORE` ;
- statut : `INTEGRATED_SOURCE_NO_TIMING_CLAIM` ;
- confiance : `A` ;
- date : 2026-09-18 ;
- preuve primaire : note V4.43 ;
- relation `OPTIMIZES` vers `x19b-fix3`.

Le choix `OPTIMIZATION / CORE` reflète mieux le contenu réel du patch que
`DIAGNOSTIC / PERFORMANCE` : x19d n'ajoute pas un diagnostic scientifique, il retire du coût
du chemin chaud lorsque des diagnostics déjà existants sont désactivés, y compris dans les
profileurs CUDA résidents génériques.

Aucun gain temporel quantitatif n'est promu : la note V4.43 exige explicitement un benchmark
CUDA dédié pour une telle revendication.
