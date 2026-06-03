Nous continuons le développement C++ SRC/MPCD du dépôt `SRC_incompressible_openMP`, branche `feature/inlet-outlet`.

Contraintes impératives :

- ne jamais fournir de fichiers `.patch` ;
- fournir uniquement des archives différentielles `*_files_only.zip` contenant les fichiers modifiés/ajoutés ;
- pour toute modification de code, partir uniquement du zip ou commit explicitement fourni dans le chat courant ;
- garder le mode `classic` compressible disponible ;
- ne pas casser les validations périodique/canal existantes ;
- privilégier l'opérateur elliptique générique déjà codé ; ne pas ajouter de chemins FFT spécifiques ;
- les nouveaux fichiers Markdown doivent aller dans `doc/`, sauf `README.md` si explicitement demandé.

État validé de `feature/inlet-outlet` :

1. Les conditions inlet/outlet sont validées pour canal ouvert sans solide immergé.
2. Réglage nominal ouvert :
   - `q9OpenBoundaryExclusionCells = 0`
   - `virialOpenBoundaryExclusionCells = 0`
3. Les exclusions non nulles près de l'outlet créent une interface active/inactive qui peut se comporter comme une paroi numérique.
4. Limiteur Q9 nominal :
   - `q9CorrectionLimiterMode = thermal_soft`
   - `q9CorrectionVelocityLimiterOverThermal = 0.5`
   - donc `dU_limit = 0.025` pour `kBT = 0.0025`.
5. Seuils Q9 low-mass relatifs à gamma :
   - `q9LowMassRampStartOverGamma = 0.05`
   - `q9LowMassRampEndOverGamma = 0.40`
   - `q9MassFloorForCorrectionOverGamma = 0.40`
   - `q9MinCellMassForCorrectionOverGamma = 0.40`.
6. La rampe d'inlet est validée et doit rester appliquée de façon cohérente à l'inlet particulaire, au flux Q6 et au flux massique Q9.
7. Validations réussies :
   - full inlet/outlet + parois slip/specular + Q9+virial excl0 ;
   - full inlet/outlet + parois VP/no-slip + profil `poiseuille_y_mean` ;
   - full inlet/outlet + parois VP/no-slip + profil `flat_taper_y`, `inletVelocityWallTaperCells = 2.0`.
8. Le profil plat strict avec parois VP/no-slip est un stress test, pas un cas nominal.
9. Les apertures inlet/outlet segmentées représentent des géométries physiques de fente/buse ; ne pas les utiliser pour corriger le canal Poiseuille canonique.
10. Les cas obstacle/marche/solide immergé restent un chantier séparé : futur masque face/cellule Q9/viriel près des solides, cellules fluides adjacentes actives et flux normal solide nul, branche dédiée possible `feature/q9-immersed-solid-boundary`.

Dernier nettoyage appliqué :

- `README.md` racine actualisé pour `feature/inlet-outlet` ;
- `doc/README_0091_INLET_OUTLET_ROOT_CLEANUP.md` ajouté ;
- `doc/NEXT_CHAT_PROMPT_0091_SEGMENTED_INLET_OUTLET.md` ajouté ;
- `scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh` : labels corrigés `poiseuille` -> `tapered_flat` ;
- `scripts/run_open_channel_jet.sh` : nettoyé comme prototype physique fente/buse segmenté ;
- `scripts/run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh` : marqué legacy/stress-test, exclusions ouvertes par défaut à zéro.

Objectif du nouveau chat : développer proprement une petite suite de cas inlet/outlet segmentés physiques type fente/buse, sans toucher au cœur numérique dans un premier temps. Comparer au minimum `classic`, `q6`, `q9`, `q9_virial` sur géométries segmentées documentées, avec visualisations et diagnostics de masse/bandes/parois.
