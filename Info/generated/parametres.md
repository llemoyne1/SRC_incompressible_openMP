# Paramètres canoniques SRC_GPU-SURF

> Une fiche correspond à un **concept canonique**. Les différentes clés `.kv`, champs C++ et alias sont regroupés sous cette fiche.

| Paramètre | Type | Défaut | Catégorie | Statut |
|---|---|---|---|---|
| `bcBottom` | enum string | periodic | Conditions limites | existant catalogue 0292 \| canonique \| alias accepté |
| `bcLeft` | enum string | periodic | Conditions limites | existant catalogue 0292 \| canonique \| alias accepté |
| `bcRight` | enum string | periodic | Conditions limites | existant catalogue 0292 \| canonique \| alias accepté |
| `bcTop` | enum string | periodic | Conditions limites | existant catalogue 0292 \| canonique \| alias accepté |
| `bcX` | enum string | (non stocké) | Conditions limites | existant catalogue 0292 \| canonique |
| `bcY` | enum string | (non stocké) | Conditions limites | existant catalogue 0292 \| canonique |
| `betaEOS` | double | 0.05 | Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b | ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q |
| `bodyAccelerationX` | double | 0.0 | Forçage et contrôle d’écoulement | existant catalogue 0292 \| canonique \| alias accepté |
| `bodyAccelerationY` | double | 0.0 | Forçage et contrôle d’écoulement | existant catalogue 0292 \| canonique \| alias accepté |
| `bottomOpenXMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `bottomOpenXMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `closedCapacityInletMassFluxEnable` | booléen | false | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityInletMassFluxMultiplier` | double | 1.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityMassGuardDisableOnOverfill` | booléen | true | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityMassRemapEta` | double | 0.005 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityMassRemapPower` | double | 2.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityQ6Eta` | double | 0.005 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityQ6Power` | double | 2.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityReferenceCellMass` | double | 0.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityReferenceParticleMass` | double | 1.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityResponseEnable` | booléen | false | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialBaseK` | double | 0.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| groupe dynamique |
| `closedCapacityVirialEta` | double | 0.005 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialGain` | double | 20.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialKickEnable` | booléen | false | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialKickStrength` | double | 1.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialMomentumCorrectionEnable` | booléen | true | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `closedCapacityVirialPower` | double | 2.0 | Réponse capacité fermée / viriel | existant catalogue 0292 \| canonique |
| `cudaResamplingChiFilterEnable` | booléen | true | CUDA resampling — filtre Darcy/chi | ajout filtre chi; recensé 0490p |
| `cudaResamplingChiMin` | double | 0.5 | CUDA resampling — filtre Darcy/chi | ajout filtre chi; recensé 0490p |
| `cudaResamplingEmptyRefillEnable` | booléen | false | CUDA resampling — refill cellules vides 0319 | ajout 0319; recensé 0490p |
| `cudaResamplingEmptyRefillGamma` | entier | 0 | CUDA resampling — refill cellules vides 0319 | ajout 0319; recensé 0490p |
| `cudaResamplingEmptyRefillMemoryMaxAge` | entier | 1000 | CUDA resampling — refill cellules vides 0319 | ajout 0319; recensé 0490p |
| `cudaResamplingEmptyRefillReference` | chaîne | ntarget | CUDA resampling — refill cellules vides 0319 | ajout 0319; recensé 0490p |
| `cudaResamplingEmptyRefillSpeciesCompositionEnable` | booléen | false | Multi-espèces — refill | ajout 0490a–0490p |
| `cudaResamplingEmptyRefillTargetFraction` | double | 0.5 | CUDA resampling — refill cellules vides 0319 | ajout 0319; recensé 0490p |
| `darcyBoxXMax` | double | 0.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyBoxXMin` | double | 0.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyBoxYMax` | double | 0.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyBoxYMin` | double | 0.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `DarcyBrinkmanConfig.alphaMax` | double | variable : 80, 8000, 800000 selon script | Darcy/Brinkman — interpolation alpha | ajout 0343; complété 0425/0426 |
| `DarcyBrinkmanConfig.alphaMin` | double | 0.0 | Darcy/Brinkman — interpolation alpha | ajout 0343 |
| `DarcyBrinkmanConfig.chiFile` | chemin fichier |  | Darcy/Brinkman — champ chi | ajout 0345 |
| `DarcyBrinkmanConfig.chiFileFormat` | chaîne | float32 | Darcy/Brinkman — champ chi | ajout 0345 |
| `DarcyBrinkmanConfig.chiMode` | chaîne | analytic | Darcy/Brinkman — champ chi | ajout 0345 |
| `DarcyBrinkmanConfig.costEvery` | entier | summaryEvery | Darcy/Brinkman — diagnostics | ajout 0343 |
| `DarcyBrinkmanConfig.costFilename` | nom fichier | darcy_cost_0343.csv | Darcy/Brinkman — diagnostics | ajout 0343 |
| `DarcyBrinkmanConfig.darcyChiNx` | entier | Nx | Darcy/Brinkman — champ chi | ajout 0345 |
| `DarcyBrinkmanConfig.darcyChiNy` | entier | Ny | Darcy/Brinkman — champ chi | ajout 0345 |
| `DarcyBrinkmanConfig.enabled` | booléen | false | Darcy/Brinkman — activation | ajout 0343; complété 0426 |
| `DarcyBrinkmanConfig.forcingMode` | chaîne | mean ou mean_outward_bath | Darcy/Brinkman — mode de forcing | ajout 0418-0420 |
| `DarcyBrinkmanConfig.initialDeactivateBelowChi` | double | -1 ou 0.05 selon script | Darcy/Brinkman — état initial chi | ajout 0418 |
| `DarcyBrinkmanConfig.q` | double | 0.1 | Darcy/Brinkman — interpolation alpha | ajout 0343 |
| `DarcyBrinkmanConfig.threadsPerBlock` | entier | 256 | Darcy/Brinkman — CUDA | ajout 0343 |
| `DarcyBrinkmanConfig.uSolidX` | double | 0.0 | Darcy/Brinkman — vitesse solide | ajout 0343 |
| `DarcyBrinkmanConfig.uSolidY` | double | 0.0 | Darcy/Brinkman — vitesse solide | ajout 0343 |
| `darcyBrinkmanEnable` | booléen | false | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyBrinkmanForcingMode` | chaîne | mean | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpEnable` | booléen | false ou true selon script | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpGamma` | entier/double | -1 | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpLayers` | entier | 1 | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpMass` | double | 1.0 | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpMode` | chaîne | interface_band | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpStrength` | double | 0.25 ou 1.0 selon script | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `DarcyChiCollisionVpConfig.darcyChiCollisionVpThreshold` | double | 0.5 | Darcy/Brinkman — chiVP collision | ajout 0422; complété 0424/0425 |
| `darcyChiCollisionVpEnable` | booléen | false | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpGamma` | double | -1.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpLayers` | entier | 1 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpMass` | double | 1.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpMode` | chaîne | interface_band | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpStrength` | double | 1.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyChiCollisionVpThreshold` | double | 0.5 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyCircleCx` | double | 0.5 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyCircleCy` | double | 0.5 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyCircleR` | double | 0.1 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyInitialDeactivateBelowChi` | double | -1.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyInterfaceWidth` | double | 0.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `darcyUniformChi` | double | 1.0 | Darcy/chiVP — géométrie et aliases | ajout 0343/0418–0426; complété inventaire 0490p |
| `dt` | double | 1.0e-3 | Temps et collision SRC | existant catalogue 0292 \| canonique |
| `dumpRoleFilter` | all\|fluid \| chaîne | all dans le cœur; fluid dans scripts visuels \| all | Dumps et post-traitement \| Sorties compactes — aliases rôle | ajout 0314 \| alias accepté; complété inventaire 0490p |
| `dumpStateEvery` | entier | 0 | I/O et exécution | existant catalogue 0292 \| canonique |
| `fluidXMax0` | double | -1.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `fluidXMaxVelocity` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `fluidXMin0` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `fluidXMinVelocity` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `fluidYMax0` | double | -1.0 | Domaine actif mobile | existant catalogue 0292 \| canonique \| alias accepté |
| `fluidYMaxVelocity` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique \| alias accepté |
| `fluidYMin0` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `fluidYMinVelocity` | double | 0.0 | Domaine actif mobile | existant catalogue 0292 \| canonique |
| `gridShiftEnable` | booléen | true | Temps et collision SRC | existant catalogue 0292 \| canonique |
| `immersedSolidCx` | double | 0.5 | Solide immergé — cercle | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidCy` | double | 0.5 | Solide immergé — cercle | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidEnable` | booléen | false | Solide immergé | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidFractionSamples` | entier | 4 | Solide immergé | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidOmega` | double | 0.0 | Solide immergé — mouvement | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidR` | double | 0.1 | Solide immergé — cercle | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidShape` | enum string | circle | Solide immergé | existant catalogue 0292 \| canonique |
| `immersedSolidVx` | double | 0.0 | Solide immergé — mouvement | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidVy` | double | 0.0 | Solide immergé — mouvement | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidWallUx` | double | 0.0 | Solide immergé — mouvement | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidWallUy` | double | 0.0 | Solide immergé — mouvement | existant catalogue 0292 \| alias accepté \| canonique |
| `immersedSolidXMax` | double | 0.25 | Solide immergé — rectangle | existant catalogue 0292 \| canonique |
| `immersedSolidXMin` | double | 0.0 | Solide immergé — rectangle | existant catalogue 0292 \| canonique |
| `immersedSolidYMax` | double | 0.50 | Solide immergé — rectangle | existant catalogue 0292 \| canonique |
| `immersedSolidYMin` | double | 0.0 | Solide immergé — rectangle | existant catalogue 0292 \| canonique |
| `inletBottomXMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `inletBottomXMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `inletHardCellThermalRescale` | booléen | true | Entrées/sorties — réservoir dur | existant catalogue 0292 \| canonique |
| `inletHardCellVelocityMean` | booléen | true | Entrées/sorties — réservoir dur | existant catalogue 0292 \| canonique |
| `inletInjectionMode` | enum string | cuda_recycle | Entrées/sorties — injection | existant catalogue 0292 \| canonique |
| `inletKBT` | double | -1.0 | Entrées/sorties — injection | existant catalogue 0292 \| canonique |
| `inletLeftYMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `inletLeftYMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `inletRandomizeTangential` | booléen | true | Entrées/sorties — injection | existant catalogue 0292 \| alias accepté \| canonique |
| `inletReinjectBackflow` | booléen | true | Entrées/sorties — injection | existant catalogue 0292 \| canonique \| alias accepté |
| `inletReservoirCells` | entier | 1 | Entrées/sorties — réservoir dur | existant catalogue 0292 \| alias accepté \| canonique |
| `inletReservoirMode` | enum string | recycle | Entrées/sorties — réservoir dur | existant catalogue 0292 \| canonique |
| `inletSlabCells` | double | 1.0 | Entrées/sorties — injection | existant catalogue 0292 \| alias accepté \| canonique |
| `inletTargetOccupancy` | entier | 0 | Entrées/sorties — réservoir dur | existant catalogue 0292 \| alias accepté \| canonique |
| `inletThermalNoise` | double | 1.0 | Entrées/sorties — injection | existant catalogue 0292 \| canonique |
| `inletUx` | double | (non stocké) | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique \| alias accepté |
| `inletUxBottom` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUxLeft` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUxRight` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUxTop` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUy` | double | (non stocké) | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique \| alias accepté |
| `inletUyBottom` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUyLeft` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUyRight` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletUyTop` | double | 0.0 | Entrées/sorties — vitesse | existant catalogue 0292 \| canonique |
| `inletVelocityRampEnable` | booléen | false | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocityRampEndTime` | double | 0.0 | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocityRampFinalFactor` | double | 1.0 | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocityRampInitialFactor` | double | 0.0 | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocityRampProfile` | enum string | linear | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocityRampStartTime` | double | 0.0 | Entrées/sorties — rampe | existant catalogue 0292 \| alias accepté \| canonique |
| `inletVelocitySpatialProfile` | enum string | uniform | Entrées/sorties — profil spatial | existant catalogue 0292 \| étendu 0493x8k entrée segmentée locale \| alias accepté \| canonique |
| `inletVelocityWallTaperCells` | double | 2.0 | Entrées/sorties — profil spatial | existant catalogue 0292 \| canonique \| alias accepté |
| `inputState` | chemin | (obligatoire) | I/O et exécution | existant catalogue 0292 \| canonique |
| `ioApertureEnable` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `kBT` | double | 0.0 | Thermostat | existant catalogue 0292 \| canonique |
| `keepMeanFlowEnable` | booléen | false | Forçage et contrôle d’écoulement | existant catalogue 0292 \| alias accepté \| canonique |
| `kVirial` | double | 0.10666666666666667 | Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b | ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q |
| `leftOpenYMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `leftOpenYMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `Lx` | double | 1.0 | Domaine et grille | existant catalogue 0292 \| canonique |
| `Ly` | double | 1.0 | Domaine et grille | existant catalogue 0292 \| canonique |
| `nSteps` | entier | 1000 | Temps et collision SRC | existant catalogue 0292 \| canonique |
| `numThreads` | entier | 0 | I/O et exécution | existant catalogue 0292 \| canonique |
| `Nx` | entier | 32 | Domaine et grille | existant catalogue 0292 \| canonique |
| `Ny` | entier | 32 | Domaine et grille | existant catalogue 0292 \| canonique |
| `openBoundaryApertureEnable` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `openBoundaryOutletFeedbackGain` | double | 0.0 | Entrées/sorties — sortie Q6 | existant catalogue 0292 \| canonique \| alias accepté |
| `openBoundaryOutletForcedLayerCells` | entier | 1 | Entrées/sorties — modes outlet \| Entrées/sorties — aliases forced outlet | existant catalogue 0292 \| canonique \| alias accepté; complété inventaire 0490p |
| `openBoundaryOutletForcedMassFlux` | double | 0.0 | Entrées/sorties — modes outlet \| Entrées/sorties — aliases forced outlet | existant catalogue 0292 \| canonique \| alias accepté; complété inventaire 0490p |
| `openBoundaryOutletForcedMassPerStep` | double | 0.0 | Entrées/sorties — modes outlet \| Entrées/sorties — aliases forced outlet | existant catalogue 0292 \| canonique \| alias accepté; complété inventaire 0490p |
| `openBoundaryOutletForcedParticleFlux` | double | 0.0 | Entrées/sorties — modes outlet \| Entrées/sorties — aliases forced outlet | existant catalogue 0292 \| canonique \| alias accepté; complété inventaire 0490p |
| `openBoundaryOutletForcedParticlesPerStep` | entier | 0 | Entrées/sorties — modes outlet \| Entrées/sorties — aliases forced outlet | existant catalogue 0292 \| canonique \| alias accepté; complété inventaire 0490p |
| `openBoundaryOutletHybridBlend` | double | 0.0 | Entrées/sorties — sortie Q6 | existant catalogue 0292 \| canonique \| alias accepté |
| `openBoundaryOutletMode` | enum string | balanced_flux historique Q6; utiliser explicitement neumann/equilibrium_flux/forced_flux pour SRC classic 0291+ \| balanced_flux historique Q6; expliciter neumann pour SRC classic | Entrées/sorties — modes outlet | existant catalogue 0292 \| sémantique Neumann mise à jour 0493x8r-x8t \| canonique \| alias accepté |
| `openBoundarySegmentCount` | entier | 0 | Entrées/sorties — segments | existant catalogue 0292 \| canonique |
| `openBoundarySegmentK` | record | (aucun) | Entrées/sorties — segments | existant catalogue 0292 \| groupe dynamique |
| `openBoundarySegments` | vecteur interne | (sans valeur stockée) | Paramètres recensés après 0436b | alias accepté; complété inventaire 0490p |
| `OpenBoundarySegments.segment[0]` | chaîne structurée | face mode sMin sMax ux uy type mass | Inlet/outlet segmenté | ajout 0249b; documenté 0426 |
| `OpenBoundarySegments.segment[1]` | chaîne structurée | face mode sMin sMax ux uy type mass | Inlet/outlet segmenté | ajout 0249b; documenté 0426 |
| `openBoundarySegmentsEnable` | booléen | false | Entrées/sorties — segments | existant catalogue 0292 \| canonique |
| `outletRightYMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `outletRightYMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `outletTopXMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `outletTopXMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `outputDir` | chemin | run_base | I/O et exécution | existant catalogue 0292 \| canonique |
| `phaseInterfaceASelector` | string canonique | family:liquid | Q6-G-F — sélection de phases | 0493x9g actif; x14k autorise paire liquide/gaz bilatérale sous gardes stricts \| alias accepté \| ajout 0493x9g |
| `phaseInterfaceBSelector` | string canonique | family:gas | Q6-G-F — sélection de phases | 0493x9g actif; x14k autorise B=type:gaz lorsque phaseInterfaceKineticBilateralRelocation=true \| alias accepté \| ajout 0493x9g; wall opérationnel géométriquement x9h |
| `phaseInterfaceContactAngleDegrees` | double fini | -1.0 | Q6-G-F — mouillage | 0493x9i/x9m actif; x12 splash/JFM=90°, calibrateurs capillaires=-1 \| alias accepté \| ajout 0493x9i; fermeture statique x9m qualifiée |
| `phaseInterfaceEvaporationTargetType` | entier / identifiant de type particulaire | -1 (SimulationParams et runners x12) | Q6-G-F — interface cinétique / évaporation | 0493x9t actif; production x12=-1; transfert r<1 non qualifié thermodynamiquement |
| `phaseInterfaceKineticBilateralRelocation` | booléen | false | Q6-G-F — interface cinétique liquide/gaz x14 | ajout 0493x14k; actif dans la chaîne liquide/gaz x14 \| ajout 0493x14k |
| `phaseInterfaceKineticReflectionFraction` | double fini | 0.0 (SimulationParams); runners x12 production fixent 1.0 | Q6-G-F — interface cinétique / évaporation | 0493x9t actif; production x12 r=1; x14k bilatéral liquide/gaz exige r=1 |
| `projectionAllowUnmaskedImmersedSolid` | booléen | false | Projection Q6 / solide immergé | existant catalogue 0292 \| canonique |
| `projectionBackend` | enum string | cpu | Projection Q6 — backend | existant catalogue 0292 \| alias accepté \| canonique |
| `projectionEnable` | booléen | false | Projection Q6 / elliptique | existant catalogue 0292 \| canonique |
| `projectionImmersedSolidCloseCutFaces` | booléen | true | Projection Q6 / solide immergé | existant catalogue 0292 \| canonique |
| `projectionImmersedSolidFluidFractionThreshold` | double | 0.5 | Projection Q6 / solide immergé | existant catalogue 0292 \| canonique |
| `projectionImmersedSolidMaskEnable` | booléen | false | Projection Q6 / solide immergé | existant catalogue 0292 \| canonique |
| `projectionMaxIterations` | entier | 300 | Projection Q6 / elliptique | existant catalogue 0292 \| canonique |
| `projectionMomentumCorrectionEnable` | booléen | true | Projection Q6 / elliptique | existant catalogue 0292 \| canonique |
| `projectionOperator` | enum string | periodic_fv_cg | Projection Q6 / elliptique | existant catalogue 0292 \| canonique |
| `projectionTolerance` | double | 1.0e-10 | Projection Q6 / elliptique | existant catalogue 0292 \| canonique |
| `q6DensityRelaxationBeta` | double | 0.0 | Projection Q6-g-f / restauration de densité | ajout 0493x7c; entrée legacy conservée; production x7q utilise tau_rho |
| `q6DensityRelaxationCompressionGateEnable` | booléen | false | Projection Q6-g-f / restauration de densité signée | ajout 0493x7d-v2; qualifié signed1/x7q |
| `q6DensityRelaxationCompressionThresholdFill` | double | 0.0 | Projection Q6-g-f / restauration de densité signée | ajout 0493x7d-v2; qualifié signed1/x7q |
| `q6DensityRelaxationTime` | double | 0.0 | Projection Q6-g-f / restauration de densité | ajout 0493x7d; entrée physique recommandée; qualifiée signed1/x7q |
| `q6DensityRelaxationTractionGain` | double | 0.0 | Projection Q6-g-f / restauration de densité signée | ajout 0493x7d-v2-signed1; qualifié x7q |
| `q6DensityRelaxationTractionThresholdFill` | double | 0.0 | Projection Q6-g-f / restauration de densité signée | ajout 0493x7d-v2-signed1; qualifié x7q |
| `q6ForceProjectionMode` | enum string | legacy | Projection Q6 / séquencement du forçage | ajout 0493x3; étendu x4; chemin Q6-g-f qualifié jusqu’à 0493x7q |
| `q6PressureOutletDeflationEnable` | booléen | true | Q6-G-F — pressure outlet conditioning | ajout 0414d; actif par défaut |
| `q6ProjectionStrength` | double | 1.0 | Projection Q6 / elliptique | existant catalogue 0292 \| alias accepté \| canonique |
| `randomRotationSign` | booléen | true | Temps et collision SRC | existant catalogue 0292 \| canonique |
| `resamplingActiveFluidFractionThreshold` | double | 0.5 | Resampling pondéré — masque wet | existant catalogue 0292 \| canonique |
| `resamplingEnable` | booléen | false | Resampling pondéré — switches | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingExtractionEnable` | booléen | false | Resampling pondéré — switches | existant catalogue 0292 \| canonique |
| `resamplingInsertionEnable` | booléen | false | Resampling pondéré — switches | existant catalogue 0292 \| canonique |
| `resamplingLatentActivationEnable` | booléen | false | Resampling pondéré — latent | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingLatentActivationMaxPerCell` | entier | 1 | Resampling pondéré — latent | existant catalogue 0292 \| canonique |
| `resamplingLatentActivationParticleMass` | double | 0.0 | Resampling pondéré — latent | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingMassGuardEnable` | booléen | false | Resampling pondéré — masse | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingMassRenormalizationPeriod` | entier | 1 | Resampling pondéré — masse | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingParticleMassMax` | double | 4.0 | Resampling pondéré — masse | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingParticleMassMin` | double | 0.25 | Resampling pondéré — masse | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPoorCellMassFraction` | double | 0.5 | Resampling pondéré — seuils pauvre/riche | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingPopulationMaxExtractionsPerCell` | entier | 64 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationMaxExtractionsPerStep` | entier | 200000 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationMaxSplitsPerCell` | entier | 16 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationMaxSplitsPerStep` | entier | 200000 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationNMax` | entier | 0 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationNMaxFraction` | double | 1.30 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationNMin` | entier | 0 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationNMinFraction` | double | 0.70 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingPopulationNTarget` | entier | 0 | Resampling pondéré — population | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingRemapEnable` | booléen | false | Resampling pondéré — switches | existant catalogue 0292 \| canonique |
| `resamplingRichCellMassFraction` | double | 1.5 | Resampling pondéré — seuils pauvre/riche | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingTargetCellMass` | double | 0.0 | Resampling pondéré — cible | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingThermalRenormalizationEnable` | booléen | false | Resampling pondéré — switches | existant catalogue 0292 \| alias accepté \| canonique |
| `resamplingWetCellMassThreshold` | double | 0.0 | Resampling pondéré — masque wet | existant catalogue 0292 \| canonique \| alias accepté |
| `resamplingWetMaskMode` | enum string | active_domain | Resampling pondéré — masque wet | existant catalogue 0292 \| canonique |
| `rightOpenYMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `rightOpenYMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `rngSeed` | uint64 | 12345 | Temps et collision SRC | existant catalogue 0292 \| canonique |
| `rotationAngle` | double | 2.0943951023931953 rad | Temps et collision SRC | existant catalogue 0292 \| alias accepté \| canonique |
| `speciesCellCudaComparisonFilename` | chaîne | species_cell_cuda_equivalence_0490h.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCellCudaComparisonTolerance` | double | 1.0e-11 | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCellCudaDepositEnable` | booléen | false | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCellCudaThreadsPerBlock` | entier | 256 | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCellDiagnosticsEnable` | booléen | false | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCellDiagnosticsFilename` | chaîne | species_cell_runtime_0490b.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCount` | entier | 0 | Multi-espèces — registre | ajout 0490a–0490p |
| `speciesCudaResidentFastPathDiagnosticsFilename` | chaîne | cuda_species_resident_fast_path_0490m.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesCudaResidentMaintenanceDiagnosticsFilename` | chaîne | cuda_species_resident_maintenance_0490n.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesDefinitions` | déclaration structurée \| vecteur interne | (aucune) \| (sans valeur stockée) | Multi-espèces — registre | ajout 0490a–0490p |
| `speciesDefinitions[K].resamplingEnable` | booléen | true pour chaque déclaration | Multi-espèces — registre | famille dynamique existante, explicitée dans l’inventaire x14 |
| `speciesDefinitions[K].thermostatTargetKBT` | double | négatif => hérite de thermostatTargetKBT puis kBT | Thermostat — multi-espèces x14 | ajout 0493x14a; famille dynamique K=0…speciesCount-1 |
| `speciesDiagnosticsEnable` | booléen | false | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesDiagnosticsFilename` | chaîne | species_runtime_0490a.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesMassClosureCudaComparisonTolerance` | double | 1.0e-11 | Multi-espèces — fermeture de masse | ajout 0490a–0490p |
| `speciesMassClosureCudaDiagnosticsFilename` | chaîne | cuda_species_mass_closure_0490i.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `speciesQ6AlphaEpsilon` | double | 1.0e-14 | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 |
| `speciesQ6ComparisonTolerance` | double | 1.0e-11 | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 |
| `speciesQ6Enable` | booléen | false | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 |
| `speciesQ6FallbackMode` | enum string | common | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 |
| `speciesQ6MinOccupancyFraction` | double | 0.5 | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–w8 puis Q6-g-f jusqu’à 0493x7q |
| `speciesQ6Mode` | enum string | common | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 puis 0493x5a–0493x6g |
| `speciesQ6Sensitivity` | double | 0.0 | Multi-espèces — projection Q6 | ajout 0491; étendu 0493w5–0493w8 |
| `speciesRegistryEnable` | booléen | false | Multi-espèces — registre | ajout 0490a–0490p |
| `speciesRequireRegisteredTypes` | booléen | false | Multi-espèces — registre | ajout 0490a–0490p |
| `speciesResamplingCudaResidentDepositsEnable` | booléen | false | Multi-espèces — chemin CUDA résident | ajout 0490a–0490p |
| `speciesResamplingCudaResidentFastPathEnable` | booléen | false | Multi-espèces — chemin CUDA résident | ajout 0490a–0490p |
| `speciesResamplingCudaResidentMaintenanceStrict` | booléen | false | Multi-espèces — chemin CUDA résident | ajout 0490a–0490p |
| `speciesResamplingCudaResidentPoolEnable` | booléen | false | Multi-espèces — chemin CUDA résident | ajout 0490a–0490p |
| `speciesResamplingCudaResidentValidationEnable` | booléen | false | Multi-espèces — chemin CUDA résident | ajout 0490a–0490p |
| `speciesResamplingMassClosureCudaEnable` | booléen | false | Multi-espèces — fermeture de masse | ajout 0490a–0490p |
| `speciesResamplingMassClosureEnable` | booléen | false | Multi-espèces — fermeture de masse | ajout 0490a–0490p |
| `speciesResamplingPopulationGuardCudaEnable` | booléen | false | Multi-espèces — garde de population | ajout 0490a–0490p |
| `speciesResamplingPopulationGuardEnable` | booléen | false | Multi-espèces — garde de population | ajout 0490a–0490p |
| `speciesResamplingTransferCudaEnable` | booléen | false | Multi-espèces — transferts donneur/receveur | ajout 0490a–0490p |
| `speciesResamplingTransferEnable` | booléen | false | Multi-espèces — transferts donneur/receveur | ajout 0490a–0490p |
| `speciesThermostatEnable` | booléen | false | Thermostat — multi-espèces x14 | ajout 0493x14a; actif dans la chaîne liquide/gaz x14 |
| `speciesTransferCudaComparisonTolerance` | double | 1.0e-11 | Multi-espèces — transferts donneur/receveur | ajout 0490a–0490p |
| `speciesTransferCudaDiagnosticsFilename` | chaîne | cuda_species_transfer_plan_0490k.csv | Multi-espèces — dépôt et diagnostics | ajout 0490a–0490p |
| `srcClassicCudaModeEnable` | booléen | false | CUDA — mode SRC classic | existant catalogue 0292 \| alias accepté \| canonique |
| `StateInit.initialInactiveSlots` | entier | 0 ou fonction de gamma*Nx*Ny | État particulaire / pool inactif | documenté 0426 |
| `summaryEvery` | entier | 10 | I/O et exécution | existant catalogue 0292 \| canonique |
| `summaryRoleFilter` | all\|fluid \| chaîne | all dans le cœur; fluid dans scripts visuels \| all | Summaries runtime \| Sorties compactes — aliases rôle | ajout 0314 \| alias accepté; complété inventaire 0490p |
| `surfaceTensionMinRadiusCells` | double fini >= 0 | 0.0 | Q6-G-F — tension superficielle / interface | 0493x9r actif; choix de campagne x12 (JFM/x12yl=4, x12cal=3) \| alias parser accepté; choix de campagne x12 |
| `surfaceTensionSigma` | double fini >= 0 | 0.0 | Q6-G-F — tension superficielle / interface | 0493x9d actif; calibration mécanique x12yl + calibration dynamique séparée x12cal; utilisé JFM x12d \| alias parser accepté de surfaceTensionSigma; actif |
| `targetMeanUx` | double | 0.0 | Forçage et contrôle d’écoulement | existant catalogue 0292 \| alias accepté \| canonique |
| `targetMeanUy` | double | 0.0 | Forçage et contrôle d’écoulement | existant catalogue 0292 \| alias accepté \| canonique |
| `taylorGreenForcingAmplitude` | double | 0.0 | Forçage Taylor–Green | existant catalogue 0292 \| canonique \| alias accepté |
| `taylorGreenForcingEnable` | booléen | false | Forçage Taylor–Green | existant catalogue 0292 \| canonique \| alias accepté |
| `taylorGreenForcingModeX` | entier | 1 | Forçage Taylor–Green | existant catalogue 0292 \| canonique \| alias accepté |
| `taylorGreenForcingModeY` | entier | 1 | Forçage Taylor–Green | existant catalogue 0292 \| canonique \| alias accepté |
| `thermostatEnable` | booléen | false | Thermostat | existant catalogue 0292 \| canonique |
| `thermostatEpsilon` | double | 1.0e-30 | Thermostat | existant catalogue 0292 \| canonique |
| `thermostatEvery` | entier | 1 | Thermostat | existant catalogue 0292 \| canonique |
| `thermostatMinParticles` | entier | 3 | Thermostat | existant catalogue 0292 \| canonique |
| `thermostatMode` | enum string | cell_relative_rescale | Thermostat | existant catalogue 0292 \| canonique |
| `thermostatTargetKBT` | double | -1.0 | Thermostat | existant catalogue 0292 \| canonique |
| `TopoBenchmarkConfig.topoBenchmarkDragLiftEnable` | booléen | true | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkEnable` | booléen | true | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkEvery` | entier | darcyCostEvery | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkFilename` | nom fichier | topo_benchmark_0348.csv | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkFlowDirX` | double | 1.0 | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkFlowDirY` | double | 0.0 | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkForceEnable` | booléen | true | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkLiftDirX` | double | 0.0 | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `TopoBenchmarkConfig.topoBenchmarkLiftDirY` | double | 1.0 | Darcy/Brinkman — benchmark topo | ajout 0348a/0348b |
| `topOpenXMax` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `topOpenXMin` | clé supprimée | (non applicable) | Clés supprimées — migration vers segments 0143 | supprimé 0143; rejet explicite; recensé 0490p |
| `virialDensityKickEnable` | booléen | false | Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b | ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q |
| `virialMomentumCorrectionEnable` | booléen | true | Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b | ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q |
| `wallAccommodation` | double | 1.0 | Parois | existant catalogue 0292 \| canonique |
| `wallKBT` | double | -1.0 | Parois | existant catalogue 0292 \| canonique |
| `wallThermalNoise` | double | 1.0 | Parois | existant catalogue 0292 \| canonique |
| `wallVpEnable` | booléen | false | Parois | existant catalogue 0292 \| canonique |
| `wallVpGamma` | double | 0.0 | Parois | existant catalogue 0292 \| canonique |
| `wallVpKBT` | double | -1.0 | Parois | existant catalogue 0292 \| canonique |
| `wallVpMass` | double | 1.0 | Parois | existant catalogue 0292 \| canonique |
| `wallVpMode` | enum string | thermal | Parois | existant catalogue 0292 \| canonique |
| `wallVpUxBottom` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUxLeft` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUxRight` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUxTop` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUyBottom` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUyLeft` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUyRight` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |
| `wallVpUyTop` | double | 0.0 | Parois — vitesses | existant catalogue 0292 \| alias accepté \| canonique |

## Fiches détaillées

### `bcBottom`

- **Type :** enum string
- **Défaut :** `periodic`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bcBottom`, `boundaryBottom`
- **Champ(s) C++ :** `bcBottom`
- **Autres alias :** `boundaryBottom`

Mode de condition limite sur la face basse.

**Remarques.** Les périodiques doivent être appariés bas/haut.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bcLeft`

- **Type :** enum string
- **Défaut :** `periodic`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bcLeft`, `boundaryLeft`
- **Champ(s) C++ :** `bcLeft`
- **Autres alias :** `boundaryLeft`

Mode de condition limite sur la face gauche.

**Remarques.** Les périodiques doivent être appariés gauche/droite.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bcRight`

- **Type :** enum string
- **Défaut :** `periodic`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bcRight`, `boundaryRight`
- **Champ(s) C++ :** `bcRight`
- **Autres alias :** `boundaryRight`

Mode de condition limite sur la face droite.

**Remarques.** Les périodiques doivent être appariés gauche/droite.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bcTop`

- **Type :** enum string
- **Défaut :** `periodic`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bcTop`, `boundaryTop`
- **Champ(s) C++ :** `bcTop`
- **Autres alias :** `boundaryTop`

Mode de condition limite sur la face haute.

**Remarques.** Les périodiques doivent être appariés bas/haut.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bcX`

- **Type :** enum string
- **Défaut :** `(non stocké)`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `bcX`
- **Champ(s) C++ :** `bcX`

Définit simultanément les modes gauche et droit.

**Remarques.** Alias de paire; appliqué à bcLeft et bcRight, puis les clés par face peuvent surcharger.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bcY`

- **Type :** enum string
- **Défaut :** `(non stocké)`
- **Contraintes / valeurs :** periodic; solid; specular; bounceback; inlet/input; outlet/output/open
- **Catégorie :** Conditions limites
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `bcY`
- **Champ(s) C++ :** `bcY`

Définit simultanément les modes bas et haut.

**Remarques.** Alias de paire; appliqué à bcBottom et bcTop, puis les clés par face peuvent surcharger.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `betaEOS`

- **Type :** double
- **Défaut :** `0.05`
- **Contraintes / valeurs :** fini >=0
- **Catégorie :** Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b
- **Statut :** ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q
- **Clé(s) `.kv` :** `betaEOS`
- **Champ(s) C++ :** `betaEOS`
- **Autres alias :** `virialBeta`

Gain sans dimension de la fermeture EOS virielle continuum.

**Remarques.** Paramètre 0493x7b, désactivé physiquement tant que virialDensityKickEnable=false.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `bodyAccelerationX`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Forçage et contrôle d’écoulement
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bodyAccelerationX`, `bodyForceX`
- **Champ(s) C++ :** `bodyAccelerationX`
- **Autres alias :** `bodyForceX`

Accélération volumique uniforme appliquée en x avant streaming.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bodyAccelerationY`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Forçage et contrôle d’écoulement
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `bodyAccelerationY`, `bodyForceY`
- **Champ(s) C++ :** `bodyAccelerationY`
- **Autres alias :** `bodyForceY`

Accélération volumique uniforme appliquée en y avant streaming.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `bottomOpenXMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `bottomOpenXMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `bottomOpenXMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `bottomOpenXMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `closedCapacityInletMassFluxEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityInletMassFluxEnable`
- **Champ(s) C++ :** `closedCapacityInletMassFluxEnable`

Active une loi de flux de masse d’entrée pilotée par capacité.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityInletMassFluxMultiplier`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityInletMassFluxMultiplier`
- **Champ(s) C++ :** `closedCapacityInletMassFluxMultiplier`

Multiplicateur du flux de masse inlet piloté par capacité.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityMassGuardDisableOnOverfill`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityMassGuardDisableOnOverfill`
- **Champ(s) C++ :** `closedCapacityMassGuardDisableOnOverfill`

Désactive le mass guard lorsque l’overfill est détecté.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityMassRemapEta`

- **Type :** double
- **Défaut :** `0.005`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityMassRemapEta`
- **Champ(s) C++ :** `closedCapacityMassRemapEta`

Paramètre eta d’atténuation du remap de masse en surcapacité.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityMassRemapPower`

- **Type :** double
- **Défaut :** `2.0`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityMassRemapPower`
- **Champ(s) C++ :** `closedCapacityMassRemapPower`

Puissance de la loi d’atténuation du remap de masse.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityQ6Eta`

- **Type :** double
- **Défaut :** `0.005`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityQ6Eta`
- **Champ(s) C++ :** `closedCapacityQ6Eta`

Paramètre eta de réduction de la projection Q6 en surcapacité.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityQ6Power`

- **Type :** double
- **Défaut :** `2.0`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityQ6Power`
- **Champ(s) C++ :** `closedCapacityQ6Power`

Puissance de la loi de réduction Q6.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityReferenceCellMass`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0; 0 => inférer
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityReferenceCellMass`
- **Champ(s) C++ :** `closedCapacityReferenceCellMass`

Masse de référence par cellule fluide.

**Remarques.** Si réponse active, il faut pouvoir inférer via ce champ, resamplingTargetCellMass ou inletTargetOccupancy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityReferenceParticleMass`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityReferenceParticleMass`
- **Champ(s) C++ :** `closedCapacityReferenceParticleMass`

Masse particulaire de référence.

**Remarques.** Utilisé pour inférer la masse cellule depuis inletTargetOccupancy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityResponseEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityResponseEnable`
- **Champ(s) C++ :** `closedCapacityResponseEnable`

Active la réponse à la surcapacité/overfill en domaine fermé.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialBaseK`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | groupe dynamique
- **Clé(s) `.kv` :** `closedCapacityVirialBaseK`
- **Champ(s) C++ :** `closedCapacityVirialBaseK`

Raideur virielle de base.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialEta`

- **Type :** double
- **Défaut :** `0.005`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialEta`
- **Champ(s) C++ :** `closedCapacityVirialEta`

Paramètre eta de la loi virielle.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialGain`

- **Type :** double
- **Défaut :** `20.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialGain`
- **Champ(s) C++ :** `closedCapacityVirialGain`

Gain de la composante virielle pilotée par l’overfill.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialKickEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialKickEnable`
- **Champ(s) C++ :** `closedCapacityVirialKickEnable`

Active le kick viriel faible lié à la surcapacité.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialKickStrength`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialKickStrength`
- **Champ(s) C++ :** `closedCapacityVirialKickStrength`

Intensité multiplicative du kick viriel.

**Remarques.** Si réponse active et kick viriel actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialMomentumCorrectionEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialMomentumCorrectionEnable`
- **Champ(s) C++ :** `closedCapacityVirialMomentumCorrectionEnable`

Corrige globalement le moment après kick viriel.

**Remarques.** Si réponse active et kick viriel actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `closedCapacityVirialPower`

- **Type :** double
- **Défaut :** `2.0`
- **Contraintes / valeurs :** >0
- **Catégorie :** Réponse capacité fermée / viriel
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `closedCapacityVirialPower`
- **Champ(s) C++ :** `closedCapacityVirialPower`

Puissance de la loi virielle.

**Remarques.** Si réponse active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingChiFilterEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** CUDA resampling — filtre Darcy/chi
- **Statut :** ajout filtre chi; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingChiFilterEnable`, `cudaResamplingDarcyChiFilterEnable`
- **Champ(s) C++ :** `cudaResamplingChiFilterEnable`
- **Autres alias :** `cudaResamplingChiFilterEnable`, `cudaResamplingDarcyChiFilterEnable`

Exclut les cellules Darcy de chi faible des mutations/reconditionnements/refills. | Alias accepté de cudaResamplingChiFilterEnable.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_mass_recondition_0296.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingChiMin`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** fini; typiquement dans [0,1].
- **Catégorie :** CUDA resampling — filtre Darcy/chi
- **Statut :** ajout filtre chi; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingChiMin`, `cudaResamplingDarcyChiMin`
- **Champ(s) C++ :** `cudaResamplingChiMin`
- **Autres alias :** `cudaResamplingChiMin`, `cudaResamplingDarcyChiMin`

Seuil minimal de chi pour autoriser le resampling CUDA. | Alias accepté de cudaResamplingChiMin.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_mass_recondition_0296.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** CUDA resampling — refill cellules vides 0319
- **Statut :** ajout 0319; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillEnable`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillEnable`

Active le refill CUDA des cellules humides vides depuis la mémoire cellulaire.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillGamma`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** entier; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** CUDA resampling — refill cellules vides 0319
- **Statut :** ajout 0319; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillGamma`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillGamma`

Valeur gamma explicite pour la cible de refill; 0 utilise les fallbacks.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillMemoryMaxAge`

- **Type :** entier
- **Défaut :** `1000`
- **Contraintes / valeurs :** >=0.
- **Catégorie :** CUDA resampling — refill cellules vides 0319
- **Statut :** ajout 0319; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillMemoryMaxAge`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillMemoryMaxAge`

Âge maximal en pas de la mémoire cellulaire utilisée pour le refill.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillReference`

- **Type :** chaîne
- **Défaut :** `ntarget`
- **Contraintes / valeurs :** ntarget | gamma.
- **Catégorie :** CUDA resampling — refill cellules vides 0319
- **Statut :** ajout 0319; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillReference`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillReference`

Choisit la référence de refill: ntarget ou gamma.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillSpeciesCompositionEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — refill
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillSpeciesCompositionEnable`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillSpeciesCompositionEnable`

Mémorise et restaure la composition multi-espèces des cellules temporairement vides.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490F_MIXED_SPECIES_REFILL.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `cudaResamplingEmptyRefillTargetFraction`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** >0.
- **Catégorie :** CUDA resampling — refill cellules vides 0319
- **Statut :** ajout 0319; recensé 0490p
- **Clé(s) `.kv` :** `cudaResamplingEmptyRefillTargetFraction`
- **Champ(s) C++ :** `cudaResamplingEmptyRefillTargetFraction`

Fraction de la population de référence utilisée comme cible de refill.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_resampling_population_guard_0297.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyBoxXMax`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyBoxXMax`
- **Champ(s) C++ :** `darcyBoxXMax`

Borne x maximale de la boîte Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyBoxXMin`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyBoxXMin`
- **Champ(s) C++ :** `darcyBoxXMin`

Borne x minimale de la boîte Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyBoxYMax`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyBoxYMax`
- **Champ(s) C++ :** `darcyBoxYMax`

Borne y maximale de la boîte Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyBoxYMin`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyBoxYMin`
- **Champ(s) C++ :** `darcyBoxYMin`

Borne y minimale de la boîte Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `DarcyBrinkmanConfig.alphaMax`

- **Type :** double
- **Défaut :** `variable : 80, 8000, 800000 selon script`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Darcy/Brinkman — interpolation alpha
- **Statut :** ajout 0343; complété 0425/0426
- **Clé(s) `.kv` :** `darcyAlphaMax`
- **Autres alias :** `ALPHA`, `DARCY_ALPHA_MAX`

Valeur maximale de résistance dans les zones chi≈0.

**Remarques.** 0425 backward step validé avec alphaMax=8e5 dans mean_outward_bath+chiVP après fastflags.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.alphaMin`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Darcy/Brinkman — interpolation alpha
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyAlphaMin`
- **Autres alias :** `ALPHA_MIN`, `DARCY_ALPHA_MIN`

Valeur minimale de la résistance alpha dans le fluide libre.

**Remarques.** Typiquement 0 pour ne pas freiner le fluide chi=1.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.chiFile`

- **Type :** chemin fichier
- **Défaut :** `-`
- **Contraintes / valeurs :** fichier .f32/.png selon script; doit correspondre à darcyChiNx/Ny
- **Catégorie :** Darcy/Brinkman — champ chi
- **Statut :** ajout 0345
- **Clé(s) `.kv` :** `darcyChiFile`
- **Autres alias :** `CHI_FILE`, `DARCY_CHI_FILE`

Chemin du champ chi externe utilisé par le solveur.

**Remarques.** Convention : chi=1 fluide libre, chi=0 solide/poreux.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.chiFileFormat`

- **Type :** chaîne
- **Défaut :** `float32`
- **Contraintes / valeurs :** float32; autres formats selon lecteurs disponibles
- **Catégorie :** Darcy/Brinkman — champ chi
- **Statut :** ajout 0345
- **Clé(s) `.kv` :** `darcyChiFileFormat`
- **Autres alias :** `CHI_FILE_FORMAT`, `DARCY_CHI_FILE_FORMAT`

Format de stockage du champ chi externe.

**Remarques.** Les scripts de démonstration utilisent majoritairement float32 row-major.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.chiMode`

- **Type :** chaîne
- **Défaut :** `analytic`
- **Contraintes / valeurs :** analytic|file
- **Catégorie :** Darcy/Brinkman — champ chi
- **Statut :** ajout 0345
- **Clé(s) `.kv` :** `darcyChiMode`

Sélectionne un chi analytique ou un champ chi externe lu depuis fichier.

**Remarques.** Le mode file est la voie recommandée pour géométries arbitraires et optimisation externe.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.costEvery`

- **Type :** entier
- **Défaut :** `summaryEvery`
- **Contraintes / valeurs :** >=1; grande valeur pour quasi-désactiver la cadence
- **Catégorie :** Darcy/Brinkman — diagnostics
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyCostEvery`
- **Autres alias :** `DARCY_COST_EVERY`

Cadence d’écriture du fichier darcy_cost_0343.csv.

**Remarques.** L’ablation 0425 a montré que ce n’était pas le poste dominant du ralentissement.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.costFilename`

- **Type :** nom fichier
- **Défaut :** `darcy_cost_0343.csv`
- **Contraintes / valeurs :** chemin relatif outputDir
- **Catégorie :** Darcy/Brinkman — diagnostics
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyCostFilename`

Nom du CSV de diagnostics Darcy : puissance, fuite solide, moyenne chi/alpha, etc.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.darcyChiNx`

- **Type :** entier
- **Défaut :** `Nx`
- **Contraintes / valeurs :** >0; doit correspondre à la grille
- **Catégorie :** Darcy/Brinkman — champ chi
- **Statut :** ajout 0345
- **Clé(s) `.kv` :** `darcyChiNx`

Dimension x du champ chi externe.

**Remarques.** Doit rester cohérente avec la grille de simulation.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.darcyChiNy`

- **Type :** entier
- **Défaut :** `Ny`
- **Contraintes / valeurs :** >0; doit correspondre à la grille
- **Catégorie :** Darcy/Brinkman — champ chi
- **Statut :** ajout 0345
- **Clé(s) `.kv` :** `darcyChiNy`

Dimension y du champ chi externe.

**Remarques.** Doit rester cohérente avec la grille de simulation.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.enabled`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Darcy/Brinkman — activation
- **Statut :** ajout 0343; complété 0426
- **Clé(s) `.kv` :** `darcyBrinkmanEnable`

Active le module de pénalisation Darcy--Brinkman piloté par chi.

**Remarques.** Le test darcyOff 0425/0426 a montré que le coût lent observé venait des flags CUDA, pas de ce booléen seul.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.forcingMode`

- **Type :** chaîne
- **Défaut :** `mean ou mean_outward_bath`
- **Contraintes / valeurs :** mean|outward_bath|mean_outward_bath selon build
- **Catégorie :** Darcy/Brinkman — mode de forcing
- **Statut :** ajout 0418-0420
- **Clé(s) `.kv` :** `darcyBrinkmanForcingMode`
- **Autres alias :** `DARCY_BRINKMAN_FORCING_MODE`

Sélectionne le schéma de kick : moyenne cellulaire, bain orienté par grad chi, ou combinaison.

**Remarques.** Le mode mean_outward_bath est le candidat solide-aware retenu pour backward step.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.initialDeactivateBelowChi`

- **Type :** double
- **Défaut :** `-1 ou 0.05 selon script`
- **Contraintes / valeurs :** <0 désactive; sinon seuil chi
- **Catégorie :** Darcy/Brinkman — état initial chi
- **Statut :** ajout 0418
- **Clé(s) `.kv` :** `darcyInitialDeactivateBelowChi`
- **Autres alias :** `DARCY_INITIAL_DEACTIVATE_BELOW_CHI`

Désactive initialement les particules situées dans les cellules de chi inférieur au seuil.

**Remarques.** Valeur 0.05 retenue pour backward step afin d’éviter une masse fluide initiale dans le solide.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.q`

- **Type :** double
- **Défaut :** `0.1`
- **Contraintes / valeurs :** >0
- **Catégorie :** Darcy/Brinkman — interpolation alpha
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyQ`
- **Autres alias :** `DARCY_Q`

Paramètre de raideur de l’interpolation Borrvall--Petersson alpha(chi).

**Remarques.** Plus petit q accentue la transition solide/fluide.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.threadsPerBlock`

- **Type :** entier
- **Défaut :** `256`
- **Contraintes / valeurs :** multiple raisonnable de warp
- **Catégorie :** Darcy/Brinkman — CUDA
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyThreadsPerBlock`
- **Autres alias :** `DARCY_THREADS_PER_BLOCK`

Taille de bloc CUDA utilisée par les kernels Darcy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.uSolidX`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** réel
- **Catégorie :** Darcy/Brinkman — vitesse solide
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyUSolidX`
- **Autres alias :** `DARCY_USOLID_X`

Composante x de la vitesse cible solide vers laquelle le frein Darcy relaxe.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyBrinkmanConfig.uSolidY`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** réel
- **Catégorie :** Darcy/Brinkman — vitesse solide
- **Statut :** ajout 0343
- **Clé(s) `.kv` :** `darcyUSolidY`
- **Autres alias :** `DARCY_USOLID_Y`

Composante y de la vitesse cible solide vers laquelle le frein Darcy relaxe.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `darcyBrinkmanEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `topoDarcyEnable`
- **Autres alias :** `darcyBrinkmanEnable`

Alias de darcyBrinkmanEnable.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyBrinkmanForcingMode`

- **Type :** chaîne
- **Défaut :** `mean`
- **Contraintes / valeurs :** -
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyForcingMode`
- **Autres alias :** `darcyBrinkmanForcingMode`
- **Variables runner qui écrivent ce paramètre :** `DARCY_BRINKMAN_FORCING_MODE`

Alias de darcyBrinkmanForcingMode.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpEnable`

- **Type :** booléen
- **Défaut :** `false ou true selon script`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpEnable`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_ENABLE`

Active les moments virtuels de collision dérivés de chi.

**Remarques.** Pas de particules persistantes : contribution effective au centre de masse de collision.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpGamma`

- **Type :** entier/double
- **Défaut :** `-1`
- **Contraintes / valeurs :** -1 hérite gamma nominal; sinon valeur explicite
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpGamma`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_GAMMA`

Occupation virtuelle de référence pour chiVP.

**Remarques.** -1 utilisé dans les scripts pour rester cohérent avec GAMMA.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpLayers`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** >=1
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpLayers`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_LAYERS`

Nombre de couches d’interface prises en compte.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpMass`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >0
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpMass`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_MASS`

Masse unitaire virtuelle utilisée dans le moment effectif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpMode`

- **Type :** chaîne
- **Défaut :** `interface_band`
- **Contraintes / valeurs :** interface_band
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpMode`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_MODE`

Sélectionne la zone chi utilisée pour les moments virtuels.

**Remarques.** Mode nominal : bande d’interface.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpStrength`

- **Type :** double
- **Défaut :** `0.25 ou 1.0 selon script`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpStrength`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_STRENGTH`

Gain relatif de la contribution chiVP.

**Remarques.** 0.25 retenu après sweep Von Karman filtré et backward step 0425.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `DarcyChiCollisionVpConfig.darcyChiCollisionVpThreshold`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** 0..1
- **Catégorie :** Darcy/Brinkman — chiVP collision
- **Statut :** ajout 0422; complété 0424/0425
- **Clé(s) `.kv` :** `darcyChiCollisionVpThreshold`
- **Autres alias :** `DARCY_CHI_COLLISION_VP_THRESHOLD`

Seuil chi pour détecter l’interface virtuelle.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `darcyChiCollisionVpEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpEnable`, `topoChiCollisionVpEnable`
- **Autres alias :** `darcyChiCollisionVpEnable`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_ENABLE`

Alias accepté de darcyChiCollisionVpEnable.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpGamma`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpGamma`, `topoChiCollisionVpGamma`
- **Autres alias :** `darcyChiCollisionVpGamma`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_GAMMA`

Alias accepté de darcyChiCollisionVpGamma.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpLayers`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** entier; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpLayers`, `topoChiCollisionVpLayers`
- **Autres alias :** `darcyChiCollisionVpLayers`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_LAYERS`

Alias accepté de darcyChiCollisionVpLayers.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpMass`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpMass`, `topoChiCollisionVpMass`
- **Autres alias :** `darcyChiCollisionVpMass`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_MASS`

Alias accepté de darcyChiCollisionVpMass.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpMode`

- **Type :** chaîne
- **Défaut :** `interface_band`
- **Contraintes / valeurs :** -
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpMode`, `topoChiCollisionVpMode`
- **Autres alias :** `darcyChiCollisionVpMode`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_MODE`

Alias accepté de darcyChiCollisionVpMode.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpStrength`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpStrength`, `topoChiCollisionVpStrength`
- **Autres alias :** `darcyChiCollisionVpStrength`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_STRENGTH`

Alias accepté de darcyChiCollisionVpStrength.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyChiCollisionVpThreshold`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCollisionVpThreshold`, `topoChiCollisionVpThreshold`
- **Autres alias :** `darcyChiCollisionVpThreshold`
- **Variables runner qui écrivent ce paramètre :** `DARCY_CHI_COLLISION_VP_THRESHOLD`

Alias accepté de darcyChiCollisionVpThreshold.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyCircleCx`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCircleCx`
- **Champ(s) C++ :** `darcyCircleCx`

Coordonnée x du centre du cercle/cylindre Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyCircleCy`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCircleCy`
- **Champ(s) C++ :** `darcyCircleCy`

Coordonnée y du centre du cercle/cylindre Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyCircleR`

- **Type :** double
- **Défaut :** `0.1`
- **Contraintes / valeurs :** >0 pour le mode circle/cylinder.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyCircleR`
- **Champ(s) C++ :** `darcyCircleR`

Rayon du cercle/cylindre Darcy analytique.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyInitialDeactivateBelowChi`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyDeactivateInitialBelowChi`
- **Autres alias :** `darcyInitialDeactivateBelowChi`
- **Variables runner qui écrivent ce paramètre :** `DARCY_INITIAL_DEACTIVATE_BELOW_CHI`

Alias de darcyInitialDeactivateBelowChi.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyInterfaceWidth`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyInterfaceWidth`
- **Champ(s) C++ :** `darcyInterfaceWidth`

Largeur de lissage de l’interface analytique chi.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `darcyUniformChi`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Darcy/chiVP — géométrie et aliases
- **Statut :** ajout 0343/0418–0426; complété inventaire 0490p
- **Clé(s) `.kv` :** `darcyUniformChi`
- **Champ(s) C++ :** `darcyUniformChi`

Valeur uniforme de chi lorsque darcyChiMode=uniform.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `dt`

- **Type :** double
- **Défaut :** `1.0e-3`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `dt`
- **Champ(s) C++ :** `dt`

Pas de temps MPCD/SRD.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `dumpRoleFilter`

- **Type :** all|fluid | chaîne
- **Défaut :** `all dans le cœur; fluid dans scripts visuels | all`
- **Contraintes / valeurs :** -
- **Catégorie :** Dumps et post-traitement | Sorties compactes — aliases rôle
- **Statut :** ajout 0314 | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `dumpParticleRoleFilter`
- **Autres alias :** `dumpRoleFilter`
- **Variables runner qui écrivent ce paramètre :** `DUMP_ROLE_FILTER`, `INACTIVE_SLOTS`

Contrôle si les dumps .smpcd écrivent tous les slots ou seulement les particules Fluid. | Alias de dumpRoleFilter.

**Remarques.** fluid accélère visualisation/post-traitement mais ne doit pas être utilisé pour un restart complet. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `dumpStateEvery`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** entier >= 0; 0 désactive les dumps périodiques
- **Catégorie :** I/O et exécution
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `dumpStateEvery`
- **Champ(s) C++ :** `dumpStateEvery`

Cadence d’écriture des états .smpcd pour post-traitement.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidXMax0`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** -1 hérite de Lx; sinon > fluidXMin0 et <= Lx
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidXMax0`
- **Champ(s) C++ :** `fluidXMax0`

Borne x maximale initiale du domaine fluide actif.

**Remarques.** Si une frontière x est périodique, le domaine x doit être complet et statique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidXMaxVelocity`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidXMaxVelocity`
- **Champ(s) C++ :** `fluidXMaxVelocity`

Vitesse imposée de la borne x maximale du domaine actif.

**Remarques.** Incompatible avec une paire périodique x si non nul.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidXMin0`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0, dans [0,Lx]
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidXMin0`
- **Champ(s) C++ :** `fluidXMin0`

Borne x minimale initiale du domaine fluide actif.

**Remarques.** Le domaine actif doit rester inclus dans la boîte numérique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidXMinVelocity`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidXMinVelocity`
- **Champ(s) C++ :** `fluidXMinVelocity`

Vitesse imposée de la borne x minimale du domaine actif.

**Remarques.** Incompatible avec une paire périodique x si non nul.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidYMax0`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** -1 hérite de Ly; sinon > fluidYMin0 et <= Ly
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `fluidYMax0`, `fluidYTop0`
- **Champ(s) C++ :** `fluidYMax0`
- **Autres alias :** `fluidYTop0`

Borne y maximale initiale du domaine fluide actif.

**Remarques.** Si une frontière y est périodique, le domaine y doit être complet et statique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidYMaxVelocity`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `fluidYMaxVelocity`, `fluidYTopVelocity`
- **Champ(s) C++ :** `fluidYMaxVelocity`
- **Autres alias :** `fluidYTopVelocity`

Vitesse imposée de la borne y maximale du domaine actif.

**Remarques.** Incompatible avec une paire périodique y si non nul.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidYMin0`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0, dans [0,Ly]
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidYMin0`
- **Champ(s) C++ :** `fluidYMin0`

Borne y minimale initiale du domaine fluide actif.

**Remarques.** Le domaine actif doit rester inclus dans la boîte numérique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `fluidYMinVelocity`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Domaine actif mobile
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `fluidYMinVelocity`
- **Champ(s) C++ :** `fluidYMinVelocity`

Vitesse imposée de la borne y minimale du domaine actif.

**Remarques.** Incompatible avec une paire périodique y si non nul.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `gridShiftEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `gridShiftEnable`
- **Champ(s) C++ :** `gridShiftEnable`

Active le décalage aléatoire de grille avant collision.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidCx`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — cercle
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidCx`, `immersedCircleCx`
- **Champ(s) C++ :** `immersedSolidCx`
- **Autres alias :** `immersedCircleCx`

Abscisse initiale du centre du cercle.

**Remarques.** Le cercle doit rester dans le domaine actif au début et à la fin.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidCy`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — cercle
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidCy`, `immersedCircleCy`
- **Champ(s) C++ :** `immersedSolidCy`
- **Autres alias :** `immersedCircleCy`

Ordonnée initiale du centre du cercle.

**Remarques.** Le cercle doit rester dans le domaine actif au début et à la fin.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Solide immergé
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidEnable`, `immersedCircleEnable`
- **Champ(s) C++ :** `immersedSolidEnable`
- **Autres alias :** `immersedCircleEnable`

Active un solide immergé analytique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidFractionSamples`

- **Type :** entier
- **Défaut :** `4`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Solide immergé
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidFractionSamples`, `immersedCircleFractionSamples`
- **Champ(s) C++ :** `immersedSolidFractionSamples`
- **Autres alias :** `immersedCircleFractionSamples`

Nombre d’échantillons pour estimer la fraction fluide/solide des cellules.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidOmega`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — mouvement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidOmega`, `immersedCircleOmega`
- **Champ(s) C++ :** `immersedSolidOmega`
- **Autres alias :** `immersedCircleOmega`

Vitesse angulaire du cercle, positive antihoraire.

**Remarques.** Implémenté seulement pour le cercle; rectangle exige Omega=0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidR`

- **Type :** double
- **Défaut :** `0.1`
- **Contraintes / valeurs :** > 0 si shape=circle/disk/disc
- **Catégorie :** Solide immergé — cercle
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidR`, `immersedCircleR`
- **Champ(s) C++ :** `immersedSolidR`
- **Autres alias :** `immersedCircleR`

Rayon du cercle immergé.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidShape`

- **Type :** enum string
- **Défaut :** `circle`
- **Contraintes / valeurs :** circle; disk; disc; rectangle; rect; box; step
- **Catégorie :** Solide immergé
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `immersedSolidShape`
- **Champ(s) C++ :** `immersedSolidShape`

Forme du solide immergé.

**Remarques.** immersedCircleEnable sans shape force circle.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidVx`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — mouvement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidVx`, `immersedCircleVx`
- **Champ(s) C++ :** `immersedSolidVx`
- **Autres alias :** `immersedCircleVx`

Vitesse de translation du solide en x.

**Remarques.** Q6 avec masque immergé impose actuellement Vx=Vy=Omega=0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidVy`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — mouvement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidVy`, `immersedCircleVy`
- **Champ(s) C++ :** `immersedSolidVy`
- **Autres alias :** `immersedCircleVy`

Vitesse de translation du solide en y.

**Remarques.** Q6 avec masque immergé impose actuellement Vx=Vy=Omega=0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidWallUx`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — mouvement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidWallUx`, `immersedCircleWallUx`
- **Champ(s) C++ :** `immersedSolidWallUx`
- **Autres alias :** `immersedCircleWallUx`

Offset uniforme de vitesse de paroi du solide en x.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidWallUy`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — mouvement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `immersedSolidWallUy`, `immersedCircleWallUy`
- **Champ(s) C++ :** `immersedSolidWallUy`
- **Autres alias :** `immersedCircleWallUy`

Offset uniforme de vitesse de paroi du solide en y.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidXMax`

- **Type :** double
- **Défaut :** `0.25`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — rectangle
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `immersedSolidXMax`
- **Champ(s) C++ :** `immersedSolidXMax`

Borne x maximale du rectangle.

**Remarques.** Rectangle: XMax>XMin; doit rester dans le domaine actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidXMin`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — rectangle
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `immersedSolidXMin`
- **Champ(s) C++ :** `immersedSolidXMin`

Borne x minimale du rectangle.

**Remarques.** Rectangle: XMax>XMin; doit rester dans le domaine actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidYMax`

- **Type :** double
- **Défaut :** `0.50`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — rectangle
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `immersedSolidYMax`
- **Champ(s) C++ :** `immersedSolidYMax`

Borne y maximale du rectangle.

**Remarques.** Rectangle: YMax>YMin; doit rester dans le domaine actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `immersedSolidYMin`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Solide immergé — rectangle
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `immersedSolidYMin`
- **Champ(s) C++ :** `immersedSolidYMin`

Borne y minimale du rectangle.

**Remarques.** Rectangle: YMax>YMin; doit rester dans le domaine actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletBottomXMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `inletBottomXMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `inletBottomXMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `inletBottomXMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `inletHardCellThermalRescale`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — réservoir dur
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletHardCellThermalRescale`
- **Champ(s) C++ :** `inletHardCellThermalRescale`

Rescale les fluctuations thermiques de la cellule d’entrée.

**Remarques.** Mode hard_cell_density.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletHardCellVelocityMean`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — réservoir dur
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletHardCellVelocityMean`
- **Champ(s) C++ :** `inletHardCellVelocityMean`

Recentre les vitesses injectées pour imposer exactement la moyenne de cellule.

**Remarques.** Mode hard_cell_density.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletInjectionMode`

- **Type :** enum string
- **Défaut :** `cuda_recycle`
- **Contraintes / valeurs :** cuda_recycle; thin_slab; hard_cell_density; hard_density; hard; cell_density
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletInjectionMode`
- **Champ(s) C++ :** `inletInjectionMode`

Mode historique de réinjection/recyclage des particules à l’entrée.

**Remarques.** Validé seulement si une frontière inlet/outlet est présente.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletKBT`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** négatif => hérite de kBT; sinon >0 recommandé
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletKBT`
- **Champ(s) C++ :** `inletKBT`

Température cinétique imposée aux particules injectées.

**Remarques.** Si inletThermalNoise>0 et inletKBT<0, kBT doit être >0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletLeftYMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `inletLeftYMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `inletLeftYMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `inletLeftYMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `inletRandomizeTangential`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletRandomizeTangential`, `injectRandomY`, `inletRandomizeTransverse`, `inletRandomizeY`
- **Champ(s) C++ :** `inletRandomizeTangential`
- **Autres alias :** `injectRandomY`, `inletRandomizeTransverse`, `inletRandomizeY`

Randomise la coordonnée tangentielle des particules injectées.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletReinjectBackflow`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `inletReinjectBackflow`, `reinjectBackflow`
- **Champ(s) C++ :** `inletReinjectBackflow`
- **Autres alias :** `reinjectBackflow`

Réinjecte les particules traversant une entrée dans le mauvais sens au lieu de les laisser sortir.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletReservoirCells`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** > 0 si hard_cell_density
- **Catégorie :** Entrées/sorties — réservoir dur
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletReservoirCells`, `inletDensityCells`
- **Champ(s) C++ :** `inletReservoirCells`
- **Autres alias :** `inletDensityCells`

Épaisseur du réservoir d’entrée en nombre de cellules.

**Remarques.** Utilisé par le mode hard_cell_density.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletReservoirMode`

- **Type :** enum string
- **Défaut :** `recycle`
- **Contraintes / valeurs :** recycle; cuda_recycle; thin_slab; hard_cell_density; hard_density; hard; cell_density; default
- **Catégorie :** Entrées/sorties — réservoir dur
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletReservoirMode`
- **Champ(s) C++ :** `inletReservoirMode`

Mode de réservoir d’entrée; les alias cuda_recycle/thin_slab sont normalisés vers recycle.

**Remarques.** hard_cell_density exige inletReservoirCells>0 et inletTargetOccupancy>0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletSlabCells`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletSlabCells`, `inletInjectionSlabCells`
- **Champ(s) C++ :** `inletSlabCells`
- **Autres alias :** `inletInjectionSlabCells`

Épaisseur de la dalle d’injection en nombre de cellules locales.

**Remarques.** Utilisé dans les modes de recyclage/injection en slab.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletTargetOccupancy`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** > 0 si hard_cell_density
- **Catégorie :** Entrées/sorties — réservoir dur
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletTargetOccupancy`, `inletGamma`, `inletTargetN`
- **Champ(s) C++ :** `inletTargetOccupancy`
- **Autres alias :** `inletGamma`, `inletTargetN`

Nombre cible de particules par cellule de réservoir dur.

**Remarques.** Souvent choisi égal à gamma.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletThermalNoise`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >= 0
- **Catégorie :** Entrées/sorties — injection
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletThermalNoise`
- **Champ(s) C++ :** `inletThermalNoise`

Amplitude du bruit thermique Maxwellien ajouté à l’inlet; 0 donne une vitesse déterministe.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUx`

- **Type :** double
- **Défaut :** `(non stocké)`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `inletUx`, `inletVelocityX`
- **Champ(s) C++ :** `inletUx`
- **Autres alias :** `inletVelocityX`

Alias global pour la composante x de vitesse d’entrée.

**Remarques.** Applique la même valeur à inletUxLeft/Right/Bottom/Top.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUxBottom`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUxBottom`
- **Champ(s) C++ :** `inletUxBottom`

Composante x de la vitesse prescrite sur l’entrée bottom.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUxLeft`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUxLeft`
- **Champ(s) C++ :** `inletUxLeft`

Composante x de la vitesse prescrite sur l’entrée left.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUxRight`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUxRight`
- **Champ(s) C++ :** `inletUxRight`

Composante x de la vitesse prescrite sur l’entrée right.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUxTop`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUxTop`
- **Champ(s) C++ :** `inletUxTop`

Composante x de la vitesse prescrite sur l’entrée top.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUy`

- **Type :** double
- **Défaut :** `(non stocké)`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `inletUy`, `inletVelocityY`
- **Champ(s) C++ :** `inletUy`
- **Autres alias :** `inletVelocityY`

Alias global pour la composante y de vitesse d’entrée.

**Remarques.** Applique la même valeur à inletUyLeft/Right/Bottom/Top.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUyBottom`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUyBottom`
- **Champ(s) C++ :** `inletUyBottom`

Composante y de la vitesse prescrite sur l’entrée bottom.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUyLeft`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUyLeft`
- **Champ(s) C++ :** `inletUyLeft`

Composante y de la vitesse prescrite sur l’entrée left.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUyRight`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUyRight`
- **Champ(s) C++ :** `inletUyRight`

Composante y de la vitesse prescrite sur l’entrée right.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletUyTop`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — vitesse
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inletUyTop`
- **Champ(s) C++ :** `inletUyTop`

Composante y de la vitesse prescrite sur l’entrée top.

**Remarques.** Utilisé par les faces inlet et les segments d’inlet selon le cas.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampEnable`, `inletRampEnable`
- **Champ(s) C++ :** `inletVelocityRampEnable`
- **Autres alias :** `inletRampEnable`

Active une rampe temporelle multiplicative sur les vitesses/flux d’entrée.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampEndTime`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampEndTime`, `inletRampEndTime`
- **Champ(s) C++ :** `inletVelocityRampEndTime`
- **Autres alias :** `inletRampEndTime`

Temps de fin de la rampe d’entrée.

**Remarques.** Si rampe active, EndTime >= StartTime.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampFinalFactor`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampFinalFactor`, `inletRampFinalFactor`
- **Champ(s) C++ :** `inletVelocityRampFinalFactor`
- **Autres alias :** `inletRampFinalFactor`

Facteur multiplicatif final de vitesse/flux d’entrée.

**Remarques.** Si rampe active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampInitialFactor`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampInitialFactor`, `inletRampInitialFactor`
- **Champ(s) C++ :** `inletVelocityRampInitialFactor`
- **Autres alias :** `inletRampInitialFactor`

Facteur multiplicatif initial de vitesse/flux d’entrée.

**Remarques.** Si rampe active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampProfile`

- **Type :** enum string
- **Défaut :** `linear`
- **Contraintes / valeurs :** linear; smoothstep
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampProfile`, `inletRampProfile`
- **Champ(s) C++ :** `inletVelocityRampProfile`
- **Autres alias :** `inletRampProfile`

Loi d’interpolation temporelle de la rampe.

**Remarques.** Si rampe active.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocityRampStartTime`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Entrées/sorties — rampe
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocityRampStartTime`, `inletRampStartTime`
- **Champ(s) C++ :** `inletVelocityRampStartTime`
- **Autres alias :** `inletRampStartTime`

Temps de début de la rampe d’entrée.

**Remarques.** Si rampe active, EndTime >= StartTime.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inletVelocitySpatialProfile`

- **Type :** enum string
- **Défaut :** `uniform`
- **Contraintes / valeurs :** uniform; poiseuille_y; poiseuille_y_mean; poiseuille_y_max; flat_taper_y; flat_taper_y_mean
- **Catégorie :** Entrées/sorties — profil spatial
- **Statut :** existant catalogue 0292 | étendu 0493x8k entrée segmentée locale | alias accepté | canonique
- **Clé(s) `.kv` :** `inletVelocitySpatialProfile`, `inletProfile`, `inletSpatialProfile`, `openBoundaryVelocityProfile`
- **Champ(s) C++ :** `inletVelocitySpatialProfile`
- **Autres alias :** `inletProfile`, `inletSpatialProfile`, `openBoundaryVelocityProfile`

Profil spatial de vitesse/flux imposé sur les entrées.

**Remarques.** Les tirets sont normalisés en underscores. | 0493x8k: pour une ouverture segmentée, poiseuille_y_max/poiseuille_y_mean sont évalués dans la coordonnée locale du segment; la vitesse normale est nulle aux extrémités et le même profil alimente injection particulaire et flux Q6-G-F.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x8k_segmented_local_poiseuille.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `inletVelocityWallTaperCells`

- **Type :** double
- **Défaut :** `2.0`
- **Contraintes / valeurs :** >= 0
- **Catégorie :** Entrées/sorties — profil spatial
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `inletVelocityWallTaperCells`, `inletWallTaperCells`, `openBoundaryVelocityWallTaperCells`
- **Champ(s) C++ :** `inletVelocityWallTaperCells`
- **Autres alias :** `inletWallTaperCells`, `openBoundaryVelocityWallTaperCells`

Largeur du lissage/taper près des murs, exprimée en cellules.

**Remarques.** Utilisé par les profils flat_taper_y.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `inputState`

- **Type :** chemin
- **Défaut :** `(obligatoire)`
- **Contraintes / valeurs :** chaîne non vide
- **Catégorie :** I/O et exécution
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `inputState`
- **Champ(s) C++ :** `inputState`
- **Variables runner qui écrivent ce paramètre :** `INPUT_STATE`

Fichier d’état initial .smpcd lu par l’exécutable.

**Remarques.** Toujours obligatoire.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `ioApertureEnable`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `ioApertureEnable`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `kBT`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0 usuel; doit être >0 quand hérité par thermostat/paroi/inlet bruité
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `kBT`
- **Champ(s) C++ :** `kBT`

Température cinétique globale de référence.

**Remarques.** Référence thermique globale.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `keepMeanFlowEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Forçage et contrôle d’écoulement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `keepMeanFlowEnable`, `keepMeanFlow`
- **Champ(s) C++ :** `keepMeanFlowEnable`
- **Autres alias :** `keepMeanFlow`

Active un correcteur global de vitesse moyenne après SRC/Q6/thermostat.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `kVirial`

- **Type :** double
- **Défaut :** `0.10666666666666667`
- **Contraintes / valeurs :** fini >=0
- **Catégorie :** Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b
- **Statut :** ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q
- **Clé(s) `.kv` :** `kVirial`
- **Champ(s) C++ :** `kVirial`
- **Autres alias :** `Kvirial`

Module continuum du terme de pression/accélération virielle associé au défaut de remplissage.

**Remarques.** Grandeur physique à ne pas rescaler avec Nx/Ny lors d’un raffinement à domaine physique fixé.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `leftOpenYMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `leftOpenYMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `leftOpenYMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `leftOpenYMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `Lx`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Domaine et grille
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `Lx`
- **Champ(s) C++ :** `Lx`

Longueur du domaine numérique en x.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `Ly`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Domaine et grille
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `Ly`
- **Champ(s) C++ :** `Ly`

Longueur du domaine numérique en y.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `nSteps`

- **Type :** entier
- **Défaut :** `1000`
- **Contraintes / valeurs :** >= 0
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `nSteps`
- **Champ(s) C++ :** `nSteps`

Nombre de pas de temps simulés.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `numThreads`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** entier >= 0; 0 laisse OpenMP décider
- **Catégorie :** I/O et exécution
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `numThreads`
- **Champ(s) C++ :** `numThreads`

Force omp_set_num_threads(numThreads).

**Remarques.** Pris en compte seulement si le binaire est compilé avec OpenMP.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `Nx`

- **Type :** entier
- **Défaut :** `32`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Domaine et grille
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `Nx`
- **Champ(s) C++ :** `Nx`
- **Variables runner qui écrivent ce paramètre :** `NX`

Nombre de cellules MPCD/projection en x.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `Ny`

- **Type :** entier
- **Défaut :** `32`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Domaine et grille
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `Ny`
- **Champ(s) C++ :** `Ny`
- **Variables runner qui écrivent ce paramètre :** `NY`

Nombre de cellules MPCD/projection en y.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryApertureEnable`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `openBoundaryApertureEnable`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `openBoundaryOutletFeedbackGain`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Entrées/sorties — sortie Q6
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `openBoundaryOutletFeedbackGain`, `openBoundaryOutletMassFeedbackGain`, `openOutletFeedbackGain`, `outletFeedbackGain`
- **Champ(s) C++ :** `openBoundaryOutletFeedbackGain`
- **Autres alias :** `openBoundaryOutletMassFeedbackGain`, `openOutletFeedbackGain`, `outletFeedbackGain`

Gain du feedback global outlet-only sur le déséquilibre de flux.

**Remarques.** Utilisé uniquement en mode hybrid/neumann_feedback/hybrid_feedback.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletForcedLayerCells`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** >= 1 | entier; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Entrées/sorties — modes outlet | Entrées/sorties — aliases forced outlet
- **Statut :** existant catalogue 0292 | canonique | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `openBoundaryOutletForcedLayerCells`, `openOutletForcedLayerCells`, `outletForcedLayerCells`, `outletSuctionLayerCells`
- **Champ(s) C++ :** `openBoundaryOutletForcedLayerCells`
- **Autres alias :** `openBoundaryOutletForcedLayerCells`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_FORCED_LAYER_CELLS`

Épaisseur de la zone d’extraction forcée, en nombre de cellules à partir de la face outlet. | Alias accepté de openBoundaryOutletForcedLayerCells.

**Remarques.** Utilisé en forced_flux/equilibrium_flux pour sélectionner l’épaisseur de couche outlet où la masse/les particules peuvent être extraites. Les scripts de démo peuvent choisir 3 par défaut. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletForcedMassFlux`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0; unités masse / temps simulation | nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Entrées/sorties — modes outlet | Entrées/sorties — aliases forced outlet
- **Statut :** existant catalogue 0292 | canonique | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `openBoundaryOutletForcedMassFlux`, `openOutletForcedMassFlux`, `outletForcedMassFlux`, `outletSuctionMassFlux`
- **Champ(s) C++ :** `openBoundaryOutletForcedMassFlux`
- **Autres alias :** `openBoundaryOutletForcedMassFlux`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_FORCED_MASS_FLUX`

Flux de masse sortant imposé par l’utilisateur, découplé du flux inlet. | Alias accepté de openBoundaryOutletForcedMassFlux.

**Remarques.** Utilisé si openBoundaryOutletMode=forced_flux et aucun flux particulaire prioritaire n’est donné. Masse extraite par step = flux * dt. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletForcedMassPerStep`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0; masse / step | nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Entrées/sorties — modes outlet | Entrées/sorties — aliases forced outlet
- **Statut :** existant catalogue 0292 | canonique | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `openBoundaryOutletForcedMassPerStep`, `openOutletForcedMassPerStep`, `outletForcedMassPerStep`, `outletSuctionMassPerStep`
- **Champ(s) C++ :** `openBoundaryOutletForcedMassPerStep`
- **Autres alias :** `openBoundaryOutletForcedMassPerStep`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_FORCED_MASS_PER_STEP`

Masse cible à extraire à chaque step dans la couche outlet. | Alias accepté de openBoundaryOutletForcedMassPerStep.

**Remarques.** Utilisé si openBoundaryOutletMode=forced_flux et si aucun flux particulaire prioritaire n’est donné. Prioritaire sur openBoundaryOutletForcedMassFlux pour la masse. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletForcedParticleFlux`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0; particules / temps simulation | nombre réel fini; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Entrées/sorties — modes outlet | Entrées/sorties — aliases forced outlet
- **Statut :** existant catalogue 0292 | canonique | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `openBoundaryOutletForcedParticleFlux`, `openOutletForcedParticleFlux`, `outletForcedParticleFlux`, `outletSuctionParticleFlux`
- **Champ(s) C++ :** `openBoundaryOutletForcedParticleFlux`
- **Autres alias :** `openBoundaryOutletForcedParticleFlux`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_FORCED_PARTICLE_FLUX`

Flux particulaire sortant imposé par l’utilisateur, découplé du flux inlet. | Alias accepté de openBoundaryOutletForcedParticleFlux.

**Remarques.** Utilisé si openBoundaryOutletMode=forced_flux. Nombre extrait par step = flux * dt, arrondi selon l’implémentation. Les paramètres particulaires sont prioritaires sur les paramètres massiques. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletForcedParticlesPerStep`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** >= 0; particules / step | entier; contraintes détaillées vérifiées par validate_simulation_params.
- **Catégorie :** Entrées/sorties — modes outlet | Entrées/sorties — aliases forced outlet
- **Statut :** existant catalogue 0292 | canonique | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `openBoundaryOutletForcedParticlesPerStep`, `openOutletForcedParticlesPerStep`, `outletForcedParticlesPerStep`, `outletSuctionParticlesPerStep`
- **Champ(s) C++ :** `openBoundaryOutletForcedParticlesPerStep`
- **Autres alias :** `openBoundaryOutletForcedParticlesPerStep`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_FORCED_PARTICLES_PER_STEP`

Nombre cible de particules à extraire à chaque step dans la couche outlet. | Alias accepté de openBoundaryOutletForcedParticlesPerStep.

**Remarques.** Utilisé si openBoundaryOutletMode=forced_flux. Prioritaire sur openBoundaryOutletForcedParticleFlux et sur les paramètres massiques. 0 désactive l’extraction forcée si aucun autre flux positif n’est donné. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletHybridBlend`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Entrées/sorties — sortie Q6
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `openBoundaryOutletHybridBlend`, `openOutletHybridBlend`, `outletHybridBlend`
- **Champ(s) C++ :** `openBoundaryOutletHybridBlend`
- **Autres alias :** `openOutletHybridBlend`, `outletHybridBlend`

Mélange entre profil local Neumann et profil équilibré.

**Remarques.** Utilisé uniquement en mode hybrid; pour sorties segmentées hybrid, doit rester 0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundaryOutletMode`

- **Type :** enum string
- **Défaut :** `balanced_flux historique Q6; utiliser explicitement neumann/equilibrium_flux/forced_flux pour SRC classic 0291+ | balanced_flux historique Q6; expliciter neumann pour SRC classic`
- **Contraintes / valeurs :** SRC classic 0291+: neumann; equilibrium_flux; forced_flux. Q6/open-boundary historique: balanced_flux; prescribed_flux; balanced; prescribed; dirichlet; neumann; free; zero_gradient; zero_normal_gradient; hybrid; neumann_feedback; hybrid_feedback. | SRC classic 0291+: neumann; equilibrium_flux; forced_flux. Q6 historique: balanced_flux; prescribed_flux; balanced; prescribed; dirichlet; free; zero_gradient; zero_normal_gradient; hybrid; neumann_feedback; hybrid_feedback.
- **Catégorie :** Entrées/sorties — modes outlet
- **Statut :** existant catalogue 0292 | sémantique Neumann mise à jour 0493x8r-x8t | canonique | alias accepté
- **Clé(s) `.kv` :** `openBoundaryOutletMode`, `openOutletBoundaryMode`, `outletBoundaryMode`, `q6q9OutletBoundaryMode`
- **Champ(s) C++ :** `openBoundaryOutletMode`
- **Autres alias :** `openOutletBoundaryMode`, `outletBoundaryMode`, `q6q9OutletBoundaryMode`
- **Variables runner qui écrivent ce paramètre :** `OUTLET_MODE`

Choisit le régime de sortie: sortie passive, extraction équilibrée ou extraction forcée utilisateur pour SRC classic; conserve aussi les politiques Q6 open-boundary historiques. | Régime outlet: sortie passive, extraction équilibrée ou extraction forcée; conserve les modes Q6 historiques.

**Remarques.** SRC classic CUDA 0291+: appliqué aux outlets full-face et segmentés. forced_flux est indépendant de l’inlet et nécessite un paramètre openBoundaryOutletForced* positif. equilibrium_flux tente une extraction équilibrante couplée au gain net du step. neumann laisse sortir passivement. Les modes Q6 historiques restent disponibles pour la projection open-boundary. | 0493x8r-x8t: neumann sur Q6-G-F est une sortie pression passive: vitesse prédicteur extrapolée à gradient normal nul, phi=0 à la face ouverte, correction finale de flux libre; le chemin particulaire reconstruit un bain cinétique local côté sortie.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_classic_src_io_resident_0263.cu`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `openBoundarySegmentCount`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** 0 si désactivé; 1..16 si activé
- **Catégorie :** Entrées/sorties — segments
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `openBoundarySegmentCount`
- **Champ(s) C++ :** `openBoundarySegmentCount`

Nombre de segments ouverts définis.

**Remarques.** Limite codée: 16 segments.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundarySegmentK`

- **Type :** record
- **Défaut :** `(aucun)`
- **Contraintes / valeurs :** face mode sMin sMax ux uy type mass; face={left,right,bottom,top}; mode=inlet/input/outlet/output/open; 0<=sMin<sMax<=1; mass>0
- **Catégorie :** Entrées/sorties — segments
- **Statut :** existant catalogue 0292 | groupe dynamique
- **Clé(s) `.kv` :** `openBoundarySegmentK`
- **Champ(s) C++ :** `openBoundarySegmentK`
- **Autres alias :** `openBoundarySegment0 ... openBoundarySegment{N-1}`

Déclaration d’un segment relatif sur une face solide/specular/bounceback.

**Remarques.** N=openBoundarySegmentCount. Les segments d’une même face ne doivent pas se chevaucher.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `openBoundarySegments`

- **Type :** vecteur interne
- **Défaut :** `(sans valeur stockée)`
- **Contraintes / valeurs :** -
- **Catégorie :** Paramètres recensés après 0436b
- **Statut :** alias accepté; complété inventaire 0490p
- **Champ(s) C++ :** `openBoundarySegments`

Champ canonique interne de SimulationParams utilisé par le parseur et le backend courant.

**Remarques.** Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `OpenBoundarySegments.segment[0]`

- **Type :** chaîne structurée
- **Défaut :** `face mode sMin sMax ux uy type mass`
- **Contraintes / valeurs :** face in {left,right,top,bottom}; mode inlet/outlet
- **Catégorie :** Inlet/outlet segmenté
- **Statut :** ajout 0249b; documenté 0426
- **Clé(s) `.kv` :** `openBoundarySegment0`

Définit le premier segment ouvert en coordonnées relatives de face.

**Remarques.** Utilisé dans LR segments et backward step Darcy pour éviter l’injection dans chi-solide.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `OpenBoundarySegments.segment[1]`

- **Type :** chaîne structurée
- **Défaut :** `face mode sMin sMax ux uy type mass`
- **Contraintes / valeurs :** face in {left,right,top,bottom}; mode inlet/outlet
- **Catégorie :** Inlet/outlet segmenté
- **Statut :** ajout 0249b; documenté 0426
- **Clé(s) `.kv` :** `openBoundarySegment1`

Définit le second segment ouvert en coordonnées relatives de face.

**Remarques.** Utilisé dans LR segments et backward step Darcy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `openBoundarySegmentsEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Entrées/sorties — segments
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `openBoundarySegmentsEnable`
- **Champ(s) C++ :** `openBoundarySegmentsEnable`

Active les segments compacts inlet/outlet sur des faces autrement wall-like.

**Remarques.** Si true, openBoundarySegmentCount>0 et chaque openBoundarySegmentK requis.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `outletRightYMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `outletRightYMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `outletRightYMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `outletRightYMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `outletTopXMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `outletTopXMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `outletTopXMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `outletTopXMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `outputDir`

- **Type :** chemin
- **Défaut :** `run_base`
- **Contraintes / valeurs :** chaîne non vide
- **Catégorie :** I/O et exécution
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `outputDir`
- **Champ(s) C++ :** `outputDir`

Répertoire de sortie du run: summaries, dumps et fichiers associés.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `phaseInterfaceASelector`

- **Type :** string canonique
- **Défaut :** `family:liquid`
- **Contraintes / valeurs :** family:liquid | family:gas | family:dispersed | family:unspecified | type:<uint32> | vacuum | wall; A ne peut pas être vacuum/wall; A/B ne doivent pas se recouvrir; en x14k bilatéral A doit être type:<id> et correspondre exactement à une espèce liquide projetée | wall; A ne peut pas être vacuum/wall; A/B ne doivent pas se recouvrir
- **Catégorie :** Q6-G-F — sélection de phases
- **Statut :** 0493x9g actif; x14k autorise paire liquide/gaz bilatérale sous gardes stricts | alias accepté | ajout 0493x9g
- **Clé(s) `.kv` :** `phaseInterfaceASelector`, `capillaryPhaseASelector`
- **Champ(s) C++ :** `phaseInterfaceASelector`
- **Autres alias :** `capillaryPhaseASelector`

Sélectionne la phase A: côté alpha>=0.5, référence de masse, orientation A->B et espèce(s) projetée(s).

**Remarques.** Défaut struct family:liquid. Avec réflexion cinétique >0, la validation exige exactement une espèce A projetée. Les runners x12/JFM écrivent phaseInterfaceASelector=type:$LIQUID_TYPE. | 0493x14k: le mode bilatéral exige des sélecteurs explicites type:<id> pour A et B; A est le liquide projeté unique. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1. | Alias de phaseInterfaceASelector. 0493x9g: phase A doit sélectionner des espèces enregistrées avec masse de référence positive.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9g` — Sélecteurs de phases A/B
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `phaseInterfaceBSelector`

- **Type :** string canonique
- **Défaut :** `family:gas`
- **Contraintes / valeurs :** family:liquid | family:gas | family:dispersed | family:unspecified | type:<uint32> | vacuum | wall; A/B ne doivent pas se recouvrir; avec réflexion cinétique et bilateral=false B reste vacuum; avec bilateral=true B doit être type:<id>, espèce gaz unique non projetée | wall; A ne peut pas être vacuum/wall; A/B ne doivent pas se recouvrir
- **Catégorie :** Q6-G-F — sélection de phases
- **Statut :** 0493x9g actif; x14k autorise B=type:gaz lorsque phaseInterfaceKineticBilateralRelocation=true | alias accepté | ajout 0493x9g; wall opérationnel géométriquement x9h
- **Clé(s) `.kv` :** `phaseInterfaceBSelector`, `capillaryPhaseBSelector`
- **Champ(s) C++ :** `phaseInterfaceBSelector`
- **Autres alias :** `capillaryPhaseBSelector`

Sélectionne le côté extérieur B de l’interface; peut fournir la pression gaz x6g, être vacuum, ou demander le provider géométrique wall.

**Remarques.** Défaut struct family:gas. La garde historique x9t B=vacuum reste vraie lorsque la réflexion cinétique est active et phaseInterfaceKineticBilateralRelocation=false. x14k lève explicitement cette restriction pour une espèce gaz B unique non projetée, avec r=1 et sélecteurs type:<id>. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1. | Alias de phaseInterfaceBSelector. 0493x9g/x9h: B=vacuum est opérationnel sans particules gaz. B=wall est géométrie seule et ne doit pas être utilisé comme paire capillaire de mouillage; le mur est alors un troisième objet.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g
- `ASSOCIATED_WITH` → `x6g` — Pression gazeuse interfaciale
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9g` — Sélecteurs de phases A/B
- `ASSOCIATED_WITH` → `x9h` — Géométrie de paroi pour mouillage
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `phaseInterfaceContactAngleDegrees`

- **Type :** double fini
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** -1 désactive; sinon [0,180] degrés; x9m qualifié seulement pour 0<theta<180
- **Catégorie :** Q6-G-F — mouillage
- **Statut :** 0493x9i/x9m actif; x12 splash/JFM=90°, calibrateurs capillaires=-1 | alias accepté | ajout 0493x9i; fermeture statique x9m qualifiée
- **Clé(s) `.kv` :** `phaseInterfaceContactAngleDegrees`, `capillaryContactAngleDegrees`, `contactAngleDegrees`
- **Champ(s) C++ :** `phaseInterfaceContactAngleDegrees`
- **Autres alias :** `capillaryContactAngleDegrees`, `contactAngleDegrees`

Prescrit l’angle de contact mesuré à travers A, avec nAB·nWall=-cos(thetaA).

**Remarques.** Défaut struct -1 (désactivé). Les splash/JFM x12 utilisent 90° avec x9m off-support; x12cal et x12yl désactivent le mouillage pour les calibrations capillaires. | Alias de phaseInterfaceContactAngleDegrees. x9i introduit le contrat. x9m est la fermeture statique préférée actuelle via ancre hors support; dynamique de ligne triple non encore quantitativement qualifiée. La garde actuelle exige surfaceTensionSigma>0 lorsqu’un angle est actif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12cal_capillary_calibrator.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique capillaire
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique de sigma
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9m` — Fermeture statique de mouillage
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `phaseInterfaceEvaporationTargetType`

- **Type :** entier / identifiant de type particulaire
- **Défaut :** `-1 (SimulationParams et runners x12)`
- **Contraintes / valeurs :** >=-1; si >=0 avec réflexion active: type enregistré, non projeté et distinct de A; incompatible avec phaseInterfaceKineticBilateralRelocation=true
- **Catégorie :** Q6-G-F — interface cinétique / évaporation
- **Statut :** 0493x9t actif; production x12=-1; transfert r<1 non qualifié thermodynamiquement
- **Clé(s) `.kv` :** `phaseInterfaceEvaporationTargetType`
- **Champ(s) C++ :** `phaseInterfaceEvaporationTargetType`
- **Autres alias :** `EVAPORATION_TARGET_TYPE (alias runner)`, `evaporationTargetType (alias parser)`
- **Variables runner qui écrivent ce paramètre :** `EVAPORATION_TARGET_TYPE`

Type cible optionnel associé aux particules transmises par la loi cinétique lorsque r<1.

**Remarques.** Avec r=1 dans la chaîne x12, ce paramètre n'entraîne aucun changement de phase. Le chemin >=0 appartient au mécanisme historique r<1 et ne constitue pas une loi d'évaporation/condensation thermodynamiquement qualifiée. | Audit commit 7655b81: alias parser présent et couvert; aucune clé canonique supplémentaire requise. | 0493x14k: le couplage bilatéral liquide/gaz courant interdit phaseInterfaceEvaporationTargetType>=0. | Audit commit 7655b81: aliases parser kineticReflectionFraction/evaporationTargetType présents et couverts; aucune clé canonique supplémentaire requise.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `phaseInterfaceKineticBilateralRelocation`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** si true: r=1; phaseInterfaceEvaporationTargetType<0; A et B explicites type:<id>; A=espèce liquide projetée unique; B=espèce gaz unique non projetée | mêmes gardes que la clé params
- **Catégorie :** Q6-G-F — interface cinétique liquide/gaz x14
- **Statut :** ajout 0493x14k; actif dans la chaîne liquide/gaz x14 | ajout 0493x14k
- **Clé(s) `.kv` :** `phaseInterfaceKineticBilateralRelocation`
- **Champ(s) C++ :** `phaseInterfaceKineticBilateralRelocation`
- **Variables runner qui écrivent ce paramètre :** `MPCD_X14L_GAS_SPECULAR_REFLECTION`, `PHASE_INTERFACE_KINETIC_BILATERAL_RELOCATION`

Étend la relocalisation positionnelle x10u à une paire liquide/gaz explicite avec sens de phase inversé pour B. | Champ SimulationParams du gate bilatéral x14k.

**Remarques.** Ne modifie à lui seul ni vitesse, ni masse, ni type. false conserve exactement la garde liquide/vide historique. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1. | Défaut false pour préserver le chemin liquide/vide.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10u` — Relocalisation one-for-one
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g

### `phaseInterfaceKineticReflectionFraction`

- **Type :** double fini
- **Défaut :** `0.0 (SimulationParams); runners x12 production fixent 1.0`
- **Contraintes / valeurs :** [0,1]; si >0: speciesQ6Enable, speciesQ6Mode=free_surface_masked, q6ForceProjectionMode=prestream_single_fused, exactement une espèce A projetée; B=vacuum sauf si phaseInterfaceKineticBilateralRelocation=true; en bilatéral r doit valoir 1
- **Catégorie :** Q6-G-F — interface cinétique / évaporation
- **Statut :** 0493x9t actif; production x12 r=1; x14k bilatéral liquide/gaz exige r=1
- **Clé(s) `.kv` :** `phaseInterfaceKineticReflectionFraction`
- **Champ(s) C++ :** `phaseInterfaceKineticReflectionFraction`
- **Autres alias :** `KINETIC_REFLECTION_FRACTION (alias runner)`, `kineticReflectionFraction (alias parser)`
- **Variables runner qui écrivent ce paramètre :** `KINETIC_REFLECTION_FRACTION`

Probabilité de réfléchir une tentative de franchissement sortante relative g=(v-uGamma)·n>0; 1-r ouvre la voie de transmission/évaporation.

**Remarques.** Correction importante: le défaut du struct est 0.0, pas 1.0. x10o et la chaîne CIC/Q2/x10u/x10v/x12a ne deviennent actifs que dans le chemin cinétique Q6 free_surface_masked; x10o exige en plus r>=1. La production x12 verrouille r=1. | Audit commit 7655b81: alias parser présent et couvert; aucune clé canonique supplémentaire requise. | 0493x14k: B explicite gaz est autorisé uniquement via le gate bilatéral; ce chemin impose r=1 et interdit une cible d’évaporation active. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1. | Audit commit 7655b81: aliases parser kineticReflectionFraction/evaporationTargetType présents et couverts; aucune clé canonique supplémentaire requise.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x10o` — Paroi thermique / enveloppe locale
- `ASSOCIATED_WITH` → `x10u` — Relocalisation one-for-one
- `ASSOCIATED_WITH` → `x10v` — Swap local full-vector
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local petites structures
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14k` — Géométrie cinétique bilatérale
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `projectionAllowUnmaskedImmersedSolid`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Projection Q6 / solide immergé
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionAllowUnmaskedImmersedSolid`
- **Champ(s) C++ :** `projectionAllowUnmaskedImmersedSolid`

Autorise explicitement Q6 avec solide immergé non masqué.

**Remarques.** À réserver aux tests/debug.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionBackend`

- **Type :** enum string
- **Défaut :** `cpu`
- **Contraintes / valeurs :** cpu; auto; cuda
- **Catégorie :** Projection Q6 — backend
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `projectionBackend`, `gpuProjectionBackend`, `q6ProjectionBackend`
- **Champ(s) C++ :** `projectionBackend`
- **Autres alias :** `gpuProjectionBackend`, `q6ProjectionBackend`
- **Variables runner qui écrivent ce paramètre :** `MPCD_CUDA_Q6_RESIDENT_0400`

Sélection expérimentale du backend de projection Q6. | Sélectionne le backend de projection Q6; hors SRC classic full CUDA.

**Remarques.** Concerne seulement projectionEnable=true. Dans le jalon 0286, Q6 CUDA reste un chantier séparé: les cas SRC classic full CUDA doivent garder projectionEnable=false.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_backend.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionEnable`
- **Champ(s) C++ :** `projectionEnable`
- **Variables runner qui écrivent ce paramètre :** `MPCD_CUDA_Q6_RESIDENT_0400`, `SPECIES_Q6_ENABLE`

Active la projection incompressible Q6.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionImmersedSolidCloseCutFaces`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Projection Q6 / solide immergé
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionImmersedSolidCloseCutFaces`
- **Champ(s) C++ :** `projectionImmersedSolidCloseCutFaces`

Ferme les faces coupées par le solide immergé dans la projection.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionImmersedSolidFluidFractionThreshold`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Projection Q6 / solide immergé
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionImmersedSolidFluidFractionThreshold`
- **Champ(s) C++ :** `projectionImmersedSolidFluidFractionThreshold`

Seuil de fraction fluide pour classer/masquer les cellules solides.

**Remarques.** Si projectionEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionImmersedSolidMaskEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Projection Q6 / solide immergé
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionImmersedSolidMaskEnable`
- **Champ(s) C++ :** `projectionImmersedSolidMaskEnable`

Active le masque solide immergé dans la projection.

**Remarques.** Q6 + immersedSolidEnable exige true, sauf debug explicite.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionMaxIterations`

- **Type :** entier
- **Défaut :** `300`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionMaxIterations`
- **Champ(s) C++ :** `projectionMaxIterations`

Nombre maximal d’itérations CG.

**Remarques.** Si projectionEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionMomentumCorrectionEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionMomentumCorrectionEnable`
- **Champ(s) C++ :** `projectionMomentumCorrectionEnable`
- **Variables runner qui écrivent ce paramètre :** `PROJECTION_MOMENTUM_CORRECTION_ENABLE`

Active la correction globale de quantité de mouvement après projection.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionOperator`

- **Type :** enum string
- **Défaut :** `periodic_fv_cg`
- **Contraintes / valeurs :** periodic_fv_cg; channel_fv_cg; auto_fv_cg; elliptic_fv_cg
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionOperator`
- **Champ(s) C++ :** `projectionOperator`

Opérateur elliptique/div-grad utilisé par la projection.

**Remarques.** Si projectionEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `projectionTolerance`

- **Type :** double
- **Défaut :** `1.0e-10`
- **Contraintes / valeurs :** >0
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `projectionTolerance`
- **Champ(s) C++ :** `projectionTolerance`
- **Variables runner qui écrivent ce paramètre :** `PROJECTION_TOLERANCE`

Tolérance relative/numérique du solveur de projection.

**Remarques.** Défaut canonique SimulationParams=1.0e-10. La campagne finale x7q/x7i TG/Poiseuille/bend/IO et le dam-break de non-régression utilisent 1.0e-5; le CG x7j respecte ce même critère sans réduction host à chaque itération.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Qualification multi-conditions-limites
- `ASSOCIATED_WITH` → `x7j` — CG coopératif CUDA résident
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationBeta`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini dans [0,1]; si >0, q6DensityRelaxationTime doit être 0
- **Catégorie :** Projection Q6-g-f / restauration de densité
- **Statut :** ajout 0493x7c; entrée legacy conservée; production x7q utilise tau_rho
- **Clé(s) `.kv` :** `q6DensityRelaxationBeta`
- **Champ(s) C++ :** `q6DensityRelaxationBeta`
- **Autres alias :** `densityRelaxationBeta`
- **Variables runner qui écrivent ce paramètre :** `Q6_DENSITY_RELAXATION_BETA`

Coefficient de relaxation de densité par pas; impose div(u_proj)=beta*(rawFill-1)/dt dans le bulk liquide.

**Remarques.** Entrée par pas conservée pour ablation/compatibilité. La chaîne signed1/x7q utilise q6DensityRelaxationTime=0.25 et beta=0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X7C_Q6_DENSITY_RELAXATION_RHS.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5a_partial_liquid_free_surface.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x5b_liquid_gas_free_surface_dam_break.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationCompressionGateEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** si true: q6DensityRelaxationCompressionThresholdFill>0 et restauration de densité active
- **Catégorie :** Projection Q6-g-f / restauration de densité signée
- **Statut :** ajout 0493x7d-v2; qualifié signed1/x7q
- **Clé(s) `.kv` :** `q6DensityRelaxationCompressionGateEnable`
- **Champ(s) C++ :** `q6DensityRelaxationCompressionGateEnable`
- **Autres alias :** `densityRelaxationCompressionGateEnable`

Active l’admission cohérente de la branche positive: cellule et au moins un voisin de face au-dessus du seuil.

**Remarques.** Le gate ne soustrait pas le seuil après admission: le défaut complet rawFill-1 alimente la cible. Profil final x7i: true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7i` — Qualification multi-conditions-limites
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationCompressionThresholdFill`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini >=0; doit être >0 si compression gate actif
- **Catégorie :** Projection Q6-g-f / restauration de densité signée
- **Statut :** ajout 0493x7d-v2; qualifié signed1/x7q
- **Clé(s) `.kv` :** `q6DensityRelaxationCompressionThresholdFill`
- **Champ(s) C++ :** `q6DensityRelaxationCompressionThresholdFill`
- **Autres alias :** `densityRelaxationCompressionThresholdFill`

Seuil du défaut positif de remplissage utilisé par le gate cohérent de compression.

**Remarques.** Les runners expriment le seuil en particules et écrivent thresholdParticles/gamma. Profil final: 3/gamma, soit 0.15 à gamma=20 et 0.30 à gamma=10.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationTime`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini >=0; si >0, q6DensityRelaxationBeta doit être 0 et betaEffectif=dt/tau doit rester dans [0,1]
- **Catégorie :** Projection Q6-g-f / restauration de densité
- **Statut :** ajout 0493x7d; entrée physique recommandée; qualifiée signed1/x7q
- **Clé(s) `.kv` :** `q6DensityRelaxationTime`
- **Champ(s) C++ :** `q6DensityRelaxationTime`
- **Autres alias :** `densityRelaxationTau`, `densityRelaxationTime`
- **Variables runner qui écrivent ce paramètre :** `Q6_DENSITY_RELAXATION_TIME`, `Q6_GF_DENSITY_RELAXATION_TIME`

Constante de temps physique tau_rho de restauration de densité; impose div(u_proj)=(rawFill-1)/tau_rho dans le bulk liquide.

**Remarques.** Valeur de production qualifiée tau_rho=0.25. Avec le gate signé, la cible n’est appliquée qu’aux structures de défaut cohérentes; 0 désactive la restauration. Requiert CUDA Q6 actif; incompatible avec q6DensityRelaxationBeta>0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x7i_q6_g_f_physical_qualification.sh`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7d` — Relaxation de densité dans le RHS
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationTractionGain`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini >=0; si >0: tractionThresholdFill>0, compression gate actif et restauration de densité active
- **Catégorie :** Projection Q6-g-f / restauration de densité signée
- **Statut :** ajout 0493x7d-v2-signed1; qualifié x7q
- **Clé(s) `.kv` :** `q6DensityRelaxationTractionGain`
- **Champ(s) C++ :** `q6DensityRelaxationTractionGain`
- **Autres alias :** `densityRelaxationTractionGain`
- **Variables runner qui écrivent ce paramètre :** `Q6_GF_DENSITY_TRACTION_GAIN`

Multiplie la cible négative admise par le gate de traction; 0 est un no-op exact de cette branche.

**Remarques.** Profil signed1/x7q qualifié: 1.0.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6DensityRelaxationTractionThresholdFill`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini >=0; doit être >0 si q6DensityRelaxationTractionGain>0
- **Catégorie :** Projection Q6-g-f / restauration de densité signée
- **Statut :** ajout 0493x7d-v2-signed1; qualifié x7q
- **Clé(s) `.kv` :** `q6DensityRelaxationTractionThresholdFill`
- **Champ(s) C++ :** `q6DensityRelaxationTractionThresholdFill`
- **Autres alias :** `densityRelaxationTractionThresholdFill`

Seuil en valeur absolue du défaut négatif pour la branche cohérente de traction/déplétion.

**Remarques.** Profil final: 6/gamma, soit 0.30 à gamma=20 et 0.60 à gamma=10.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/src_mpcd_run_common_0434.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6ForceProjectionMode`

- **Type :** enum string
- **Défaut :** `legacy`
- **Contraintes / valeurs :** legacy; prestream; prestream_single; prestream_single_fused.
- **Catégorie :** Projection Q6 / séquencement du forçage
- **Statut :** ajout 0493x3; étendu x4; chemin Q6-g-f qualifié jusqu’à 0493x7q
- **Clé(s) `.kv` :** `q6ForceProjectionMode`
- **Champ(s) C++ :** `q6ForceProjectionMode`
- **Variables runner qui écrivent ce paramètre :** `KINETIC_REFLECTION_FRACTION`, `Q6_FORCE_PROJECTION_MODE`

Choisit l’ordre force/Q6/streaming; prestream_single_fused projette la vitesse tentative incluant la force avant transport avec un seul solveur Q6 et fusion CUDA.

**Remarques.** legacy conserve l’ordre historique. prestream_single_fused est le chemin Q6-g-f qualifié sur TG, Poiseuille, bend/IO et dam-break; il inclut les sources déterministes (body/TG et, x7g, Darcy moyen) dans la vitesse tentative avant projection.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493X3_Q6_FORCE_PRESTREAM_TEST.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X4A_Q6_FORCE_SINGLE_SOLVE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X4B_Q6_FORCE_CUDA_FUSION.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X7D_DENSITY_RELAXATION_TIME_GRID_REFINEMENT.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X7E_X6G_X7D_COMBINATION.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/src_mpcd_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x3` — Q6-g force-aware - preuve de concept
- `ASSOCIATED_WITH` → `x7g` — Darcy avant projection
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `q6PressureOutletDeflationEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Q6-G-F — pressure outlet conditioning
- **Statut :** ajout 0414d; actif par défaut
- **Clé(s) `.kv` :** `q6PressureOutletDeflationEnable`
- **Autres alias :** `pressureOutletDeflationEnable`
- **Variables runner qui écrivent ce paramètre :** `Q6_PRESSURE_OUTLET_DEFLATION_ENABLE`

Active/désactive uniquement la déflation exacte x8s des modes lents des pressure outlets compatibles, sans changer x8r/x8t.

**Remarques.** Switch d’ablation runtime; géométrie partielle non séparable désactive automatiquement la déflation spécialisée.

**Jalons associés :**
- `ASSOCIATED_WITH` → `x8r` — Outlet pression Neumann
- `ASSOCIATED_WITH` → `x8s` — Déflation des modes lents du CG
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen

### `q6ProjectionStrength`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Projection Q6 / elliptique
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `q6ProjectionStrength`, `projectionStrength`
- **Champ(s) C++ :** `q6ProjectionStrength`
- **Autres alias :** `projectionStrength`

Sous-relaxation de la correction fluide-fluide Q6.

**Remarques.** Si projectionEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `randomRotationSign`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `randomRotationSign`
- **Champ(s) C++ :** `randomRotationSign`

Active le signe aléatoire de la rotation collisionnelle.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingActiveFluidFractionThreshold`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Resampling pondéré — masque wet
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingActiveFluidFractionThreshold`
- **Champ(s) C++ :** `resamplingActiveFluidFractionThreshold`

Seuil de fraction fluide active pour considérer une cellule éligible.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — switches
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingEnable`, `weightedResamplingEnable`
- **Champ(s) C++ :** `resamplingEnable`
- **Autres alias :** `weightedResamplingEnable`

Switch maître de toutes les opérations de rôle/changement de population.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingExtractionEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — switches
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingExtractionEnable`
- **Champ(s) C++ :** `resamplingExtractionEnable`

Active l’extraction Fluid -> Inactive depuis cellules riches.

**Remarques.** Si insertion=true, extraction doit être true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingInsertionEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — switches
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingInsertionEnable`
- **Champ(s) C++ :** `resamplingInsertionEnable`

Active l’insertion Inactive -> Fluid vers cellules pauvres.

**Remarques.** Exige resamplingExtractionEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingLatentActivationEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — latent
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingLatentActivationEnable`, `resamplingLatentToFluidEnable`
- **Champ(s) C++ :** `resamplingLatentActivationEnable`
- **Autres alias :** `resamplingLatentToFluidEnable`

Active la conversion Latent -> Fluid pour remplir les cellules pauvres/vides.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingLatentActivationMaxPerCell`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** >0 si activation latente active
- **Catégorie :** Resampling pondéré — latent
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingLatentActivationMaxPerCell`
- **Champ(s) C++ :** `resamplingLatentActivationMaxPerCell`

Nombre maximal d’activations latentes par cellule.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingLatentActivationParticleMass`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0; 0 => targetCellMass/maxPerCell
- **Catégorie :** Resampling pondéré — latent
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingLatentActivationParticleMass`, `resamplingLatentParticleMass`
- **Champ(s) C++ :** `resamplingLatentActivationParticleMass`
- **Autres alias :** `resamplingLatentParticleMass`

Masse attribuée aux particules activées depuis latent.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingMassGuardEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — masse
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingMassGuardEnable`, `resamplingMassSafetyEnable`
- **Champ(s) C++ :** `resamplingMassGuardEnable`
- **Autres alias :** `resamplingMassSafetyEnable`

Active le garde de bornes de masse particulaire.

**Remarques.** Exige resamplingRemapEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingMassRenormalizationPeriod`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** >=0; 0 désactive remap/guard de masse
- **Catégorie :** Resampling pondéré — masse
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingMassRenormalizationPeriod`, `resamplingMassRemapPeriod`, `resamplingMassRenormalisationPeriod`, `resamplingRemapPeriod`
- **Champ(s) C++ :** `resamplingMassRenormalizationPeriod`
- **Autres alias :** `resamplingMassRemapPeriod`, `resamplingMassRenormalisationPeriod`, `resamplingRemapPeriod`

Période K de renormalisation/remap de masse.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingParticleMassMax`

- **Type :** double
- **Défaut :** `4.0`
- **Contraintes / valeurs :** > resamplingParticleMassMin
- **Catégorie :** Resampling pondéré — masse
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingParticleMassMax`, `resamplingMassMax`
- **Champ(s) C++ :** `resamplingParticleMassMax`
- **Autres alias :** `resamplingMassMax`

Borne supérieure de masse particulaire.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingParticleMassMin`

- **Type :** double
- **Défaut :** `0.25`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — masse
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingParticleMassMin`, `resamplingMassMin`
- **Champ(s) C++ :** `resamplingParticleMassMin`
- **Autres alias :** `resamplingMassMin`

Borne inférieure de masse particulaire.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPoorCellMassFraction`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — seuils pauvre/riche
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingPoorCellMassFraction`, `resamplingPoorMassFraction`
- **Champ(s) C++ :** `resamplingPoorCellMassFraction`
- **Autres alias :** `resamplingPoorMassFraction`

Fraction de masse cible sous laquelle une cellule est pauvre.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationMaxExtractionsPerCell`

- **Type :** entier
- **Défaut :** `64`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationMaxExtractionsPerCell`, `resamplingNMaxExtractionsPerCell`
- **Champ(s) C++ :** `resamplingPopulationMaxExtractionsPerCell`
- **Autres alias :** `resamplingNMaxExtractionsPerCell`

Limite d’extractions par cellule et par step.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationMaxExtractionsPerStep`

- **Type :** entier
- **Défaut :** `200000`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationMaxExtractionsPerStep`, `resamplingNMaxExtractionsPerStep`
- **Champ(s) C++ :** `resamplingPopulationMaxExtractionsPerStep`
- **Autres alias :** `resamplingNMaxExtractionsPerStep`

Limite globale d’extractions par step.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationMaxSplitsPerCell`

- **Type :** entier
- **Défaut :** `16`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationMaxSplitsPerCell`, `resamplingNMaxSplitsPerCell`
- **Champ(s) C++ :** `resamplingPopulationMaxSplitsPerCell`
- **Autres alias :** `resamplingNMaxSplitsPerCell`

Limite de splits par cellule et par step.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationMaxSplitsPerStep`

- **Type :** entier
- **Défaut :** `200000`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationMaxSplitsPerStep`, `resamplingNMaxSplitsPerStep`
- **Champ(s) C++ :** `resamplingPopulationMaxSplitsPerStep`
- **Autres alias :** `resamplingNMaxSplitsPerStep`

Limite globale de splits par step.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationNMax`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** >=0; 0 avec les deux autres bornes => inférence
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationNMax`, `resamplingNMax`
- **Champ(s) C++ :** `resamplingPopulationNMax`
- **Autres alias :** `resamplingNMax`

Borne haute de population par cellule.

**Remarques.** Si explicite, NMin<NTarget<NMax.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationNMaxFraction`

- **Type :** double
- **Défaut :** `1.30`
- **Contraintes / valeurs :** >=1
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationNMaxFraction`, `resamplingNMaxFraction`
- **Champ(s) C++ :** `resamplingPopulationNMaxFraction`
- **Autres alias :** `resamplingNMaxFraction`

Fraction utilisée pour inférer NMax.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationNMin`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** >=0; 0 avec les deux autres bornes => inférence
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationNMin`, `resamplingNMin`
- **Champ(s) C++ :** `resamplingPopulationNMin`
- **Autres alias :** `resamplingNMin`

Borne basse de population par cellule.

**Remarques.** Si explicite, NMin<NTarget<NMax.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationNMinFraction`

- **Type :** double
- **Défaut :** `0.70`
- **Contraintes / valeurs :** (0,1]
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationNMinFraction`, `resamplingNMinFraction`
- **Champ(s) C++ :** `resamplingPopulationNMinFraction`
- **Autres alias :** `resamplingNMinFraction`

Fraction utilisée pour inférer NMin.

**Remarques.** Si resamplingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingPopulationNTarget`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** >=0; 0 avec les deux autres bornes => inférence
- **Catégorie :** Resampling pondéré — population
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingPopulationNTarget`, `resamplingNTarget`
- **Champ(s) C++ :** `resamplingPopulationNTarget`
- **Autres alias :** `resamplingNTarget`

Population cible par cellule.

**Remarques.** Si explicite, NMin<NTarget<NMax.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingRemapEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — switches
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingRemapEnable`
- **Champ(s) C++ :** `resamplingRemapEnable`

Active le remap/renormalisation locale de masse.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingRichCellMassFraction`

- **Type :** double
- **Défaut :** `1.5`
- **Contraintes / valeurs :** > resamplingPoorCellMassFraction
- **Catégorie :** Resampling pondéré — seuils pauvre/riche
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingRichCellMassFraction`, `resamplingRichMassFraction`
- **Champ(s) C++ :** `resamplingRichCellMassFraction`
- **Autres alias :** `resamplingRichMassFraction`

Fraction de masse cible au-dessus de laquelle une cellule est riche.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingTargetCellMass`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0; 0 => infère la masse moyenne courante
- **Catégorie :** Resampling pondéré — cible
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingTargetCellMass`, `weightedResamplingTargetCellMass`
- **Champ(s) C++ :** `resamplingTargetCellMass`
- **Autres alias :** `weightedResamplingTargetCellMass`

Masse cible par cellule pour diagnostics/remap resampling.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingThermalRenormalizationEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Resampling pondéré — switches
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `resamplingThermalRenormalizationEnable`, `resamplingThermalRenormalisationEnable`
- **Champ(s) C++ :** `resamplingThermalRenormalizationEnable`
- **Autres alias :** `resamplingThermalRenormalisationEnable`

Active la correction thermique liée au resampling.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingWetCellMassThreshold`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0
- **Catégorie :** Resampling pondéré — masque wet
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `resamplingWetCellMassThreshold`, `resamplingWetMassThreshold`
- **Champ(s) C++ :** `resamplingWetCellMassThreshold`
- **Autres alias :** `resamplingWetMassThreshold`

Seuil de masse minimale d’une cellule wet.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `resamplingWetMaskMode`

- **Type :** enum string
- **Défaut :** `active_domain`
- **Contraintes / valeurs :** active_domain; occupied
- **Catégorie :** Resampling pondéré — masque wet
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `resamplingWetMaskMode`
- **Champ(s) C++ :** `resamplingWetMaskMode`

Définition des cellules wet/actives pour le resampling.

**Remarques.** Les tirets sont normalisés en underscores.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `rightOpenYMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `rightOpenYMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `rightOpenYMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `rightOpenYMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `rngSeed`

- **Type :** uint64
- **Défaut :** `12345`
- **Contraintes / valeurs :** entier non signé 64 bits
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `rngSeed`
- **Champ(s) C++ :** `rngSeed`

Graine de génération pseudo-aléatoire.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `rotationAngle`

- **Type :** double
- **Défaut :** `2.0943951023931953 rad`
- **Contraintes / valeurs :** réel non NaN; alphaDeg converti en radians
- **Catégorie :** Temps et collision SRC
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `rotationAngle`, `alphaDeg`
- **Champ(s) C++ :** `rotationAngle`
- **Autres alias :** `alphaDeg`

Angle de rotation SRD/MPCD.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellCudaComparisonFilename`

- **Type :** chaîne
- **Défaut :** `species_cell_cuda_equivalence_0490h.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellCudaComparisonFilename`
- **Champ(s) C++ :** `speciesCellCudaComparisonFilename`

Nom du CSV d’équivalence dépôt CPU/CUDA 0490h.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490H_CUDA_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellCudaComparisonTolerance`

- **Type :** double
- **Défaut :** `1.0e-11`
- **Contraintes / valeurs :** fini et >=0.
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellCudaComparisonTolerance`
- **Champ(s) C++ :** `speciesCellCudaComparisonTolerance`

Tolérance absolue de l’équivalence dépôt CPU/CUDA.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490H_CUDA_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellCudaDepositEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellCudaDepositEnable`
- **Champ(s) C++ :** `speciesCellCudaDepositEnable`

Active le dépôt CUDA résident N/M/P par cellule et espèce et sa comparaison de référence.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490H_CUDA_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellCudaThreadsPerBlock`

- **Type :** entier
- **Défaut :** `256`
- **Contraintes / valeurs :** 1…1024.
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellCudaThreadsPerBlock`
- **Champ(s) C++ :** `speciesCellCudaThreadsPerBlock`

Nombre de threads par bloc du dépôt CUDA par espèce.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490H_CUDA_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellDiagnosticsEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellDiagnosticsEnable`
- **Champ(s) C++ :** `speciesCellDiagnosticsEnable`
- **Variables runner qui écrivent ce paramètre :** `REQUIRE_MIXED_CELL_AT_END`

Active le dépôt CPU de référence par cellule et espèce.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490B_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCellDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `species_cell_runtime_0490b.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCellDiagnosticsFilename`
- **Champ(s) C++ :** `speciesCellDiagnosticsFilename`

Nom du CSV CPU par cellule et espèce.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490B_SPECIES_CELL_DEPOSIT.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCount`

- **Type :** entier
- **Défaut :** `0`
- **Contraintes / valeurs :** >0 lorsque le registre est actif; exactement autant de déclarations speciesK.
- **Catégorie :** Multi-espèces — registre
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCount`
- **Champ(s) C++ :** `speciesCount`

Nombre exact de déclarations species0…speciesN-1 attendues.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCudaResidentFastPathDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `cuda_species_resident_fast_path_0490m.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCudaResidentFastPathDiagnosticsFilename`
- **Champ(s) C++ :** `speciesCudaResidentFastPathDiagnosticsFilename`

Nom du CSV du fast path résident multi-espèces.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490M_CUDA_SPECIES_RESIDENT_FAST_PATH.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesCudaResidentMaintenanceDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `cuda_species_resident_maintenance_0490n.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesCudaResidentMaintenanceDiagnosticsFilename`
- **Champ(s) C++ :** `speciesCudaResidentMaintenanceDiagnosticsFilename`

Nom du CSV de maintenance résidente 0490n/0490p.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490N_CUDA_SPECIES_RESIDENT_MAINTENANCE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesDefinitions`

- **Type :** déclaration structurée | vecteur interne
- **Défaut :** `(aucune) | (sans valeur stockée)`
- **Contraintes / valeurs :** K=0…speciesCount-1; type unique uint32; phaseFamily=liquid|gas; coefficients finis. Pour independent_masked: q6StrengthDeclared dans [0,1] et referenceCellMassDeclared finie >0 pour chaque espèce.
- **Catégorie :** Multi-espèces — registre
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesK`
- **Champ(s) C++ :** `speciesDefinitions`
- **Autres alias :** `species0…speciesN-1`

Déclare une espèce: type, nom, famille de phase, coefficients Q6/fermeture et masse cellulaire de référence optionnelle. | Champ canonique interne de SimulationParams utilisé par le parseur et le backend courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | 0493w5: la masse cellulaire de référence devient obligatoire pour construire le proxy d’occupation de independent_masked. | 0493x14: chaque déclaration peut être complétée par speciesKResamplingEnable et speciesKThermostatTargetKBT; le thermostat séparé conserve la collision SRC commune et agit après collision. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

### `speciesDefinitions[K].resamplingEnable`

- **Type :** booléen
- **Défaut :** `true pour chaque déclaration`
- **Contraintes / valeurs :** K entier dans [0,speciesCount-1]
- **Catégorie :** Multi-espèces — registre
- **Statut :** famille dynamique existante, explicitée dans l’inventaire x14
- **Clé(s) `.kv` :** `speciesKResamplingEnable`
- **Autres alias :** `species0ResamplingEnable … speciesN-1ResamplingEnable`

Active/désactive le resampling pour l’espèce K.

**Remarques.** Famille dynamique déjà documentée dans le commentaire de SimulationParams mais auparavant seulement implicite dans la ligne speciesK.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesDefinitions[K].thermostatTargetKBT`

- **Type :** double
- **Défaut :** `négatif => hérite de thermostatTargetKBT puis kBT`
- **Contraintes / valeurs :** K entier dans [0,speciesCount-1]; valeur résolue finie >0 lorsque speciesThermostatEnable=true; 0 invalide
- **Catégorie :** Thermostat — multi-espèces x14
- **Statut :** ajout 0493x14a; famille dynamique K=0…speciesCount-1
- **Clé(s) `.kv` :** `speciesKThermostatTargetKBT`
- **Autres alias :** `species0ThermostatTargetKBT … speciesN-1ThermostatTargetKBT`

Cible thermique propre à l’espèce K.

**Remarques.** Clé dynamique détectée par parse_species_thermostat_target_key; ne fait pas partie du décompte des clés littérales directes du parseur. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `include/species_registry.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g

### `speciesDiagnosticsEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesDiagnosticsEnable`
- **Champ(s) C++ :** `speciesDiagnosticsEnable`
- **Variables runner qui écrivent ce paramètre :** `POSTCHECK_SPECIES_ENABLE`, `Q6_GF_SPECIES_DIAGNOSTICS_ENABLE`

Active le bilan global par espèce aux pas de summary.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `species_runtime_0490a.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesDiagnosticsFilename`
- **Champ(s) C++ :** `speciesDiagnosticsFilename`

Nom du CSV global par espèce.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesMassClosureCudaComparisonTolerance`

- **Type :** double
- **Défaut :** `1.0e-11`
- **Contraintes / valeurs :** fini et >=0.
- **Catégorie :** Multi-espèces — fermeture de masse
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesMassClosureCudaComparisonTolerance`
- **Champ(s) C++ :** `speciesMassClosureCudaComparisonTolerance`

Tolérance des comparaisons de masse cellulaire avant remap.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490I_CUDA_SPECIES_MASS_CLOSURE.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesMassClosureCudaDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `cuda_species_mass_closure_0490i.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesMassClosureCudaDiagnosticsFilename`
- **Champ(s) C++ :** `speciesMassClosureCudaDiagnosticsFilename`

Nom du CSV de fermeture de masse CUDA.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490I_CUDA_SPECIES_MASS_CLOSURE.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesQ6AlphaEpsilon`

- **Type :** double
- **Défaut :** `1.0e-14`
- **Contraintes / valeurs :** fini et >0.
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8
- **Clé(s) `.kv` :** `speciesQ6AlphaEpsilon`
- **Champ(s) C++ :** `speciesQ6AlphaEpsilon`

Seuil de dégénérescence de la moyenne de force Q6 dans le mode weighted.

**Remarques.** Utilisé avec speciesQ6FallbackMode; ne définit pas le support independent_masked.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

### `speciesQ6ComparisonTolerance`

- **Type :** double
- **Défaut :** `1.0e-11`
- **Contraintes / valeurs :** fini et >0.
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8
- **Clé(s) `.kv` :** `speciesQ6ComparisonTolerance`
- **Champ(s) C++ :** `speciesQ6ComparisonTolerance`
- **Variables runner qui écrivent ce paramètre :** `SPECIES_Q6_COMPARISON_TOLERANCE`

Tolérance des comparaisons CPU/CUDA et des contrats de qualification Q6 par espèce.

**Remarques.** Ne modifie pas le solveur physique.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

### `speciesQ6Enable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8
- **Clé(s) `.kv` :** `speciesQ6Enable`
- **Champ(s) C++ :** `speciesQ6Enable`
- **Variables runner qui écrivent ce paramètre :** `SPECIES_Q6_ENABLE`

Active la distribution ou les solveurs Q6 sensibles aux espèces.

**Remarques.** Exige speciesRegistryEnable=true et une projection Q6 active; n’active ni Q6 ni le resampling implicitement.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

### `speciesQ6FallbackMode`

- **Type :** enum string
- **Défaut :** `common`
- **Contraintes / valeurs :** common; fatal.
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8
- **Clé(s) `.kv` :** `speciesQ6FallbackMode`
- **Champ(s) C++ :** `speciesQ6FallbackMode`
- **Variables runner qui écrivent ce paramètre :** `SPECIES_Q6_FALLBACK_MODE`

Choisit le repli du mode weighted lorsque la normalisation est dégénérée.

**Remarques.** Legacy weighted uniquement; independent_masked n’utilise aucun fallback=common.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

### `speciesQ6MinOccupancyFraction`

- **Type :** double
- **Défaut :** `0.5`
- **Contraintes / valeurs :** fini dans [0,1].
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–w8 puis Q6-g-f jusqu’à 0493x7q
- **Clé(s) `.kv` :** `speciesQ6MinOccupancyFraction`
- **Champ(s) C++ :** `speciesQ6MinOccupancyFraction`
- **Variables runner qui écrivent ce paramètre :** `Q6_GF_MIN_FILL_FRACTION`, `SPECIES_Q6_MIN_FILL_FRACTION`, `SPECIES_Q6_MIN_OCCUPANCY_FRACTION`

Seuil de support des modes Q6 masqués; sens dépend du mode.

**Remarques.** independent_masked: seuil relatif d’espèce. free_surface_masked: seuil absolu liquide M_liq/M_ref. Le défaut canonique reste 0.5; le profil Q6-g-f final utilise 0.10. x7m distingue explicitement ce support numérique de l’interface alpha=0.5 et supprime l’interface fictive lorsqu’aucun gaz n’est enregistré.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X6F_PHASE_INTERFACE_STENCIL.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x5a` — free_surface_masked initial
- `ASSOCIATED_WITH` → `x7m` — Correction topologie monophase
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `speciesQ6Mode`

- **Type :** enum string
- **Défaut :** `common`
- **Contraintes / valeurs :** common; weighted; independent_masked; free_surface_masked.
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8 puis 0493x5a–0493x6g
- **Clé(s) `.kv` :** `speciesQ6Mode`
- **Champ(s) C++ :** `speciesQ6Mode`
- **Variables runner qui écrivent ce paramètre :** `KINETIC_REFLECTION_FRACTION`, `MPCD_CUDA_Q6_RESIDENT_0400`, `MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404`, `MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409`, `MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401`, `MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402`, `MPCD_CUDA_Q6_RESIDENT_STRICT_0400`, `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400`, `SPECIES_Q6_MODE`

Sélectionne l’opérateur Q6 multi-espèces / surface libre.

**Remarques.** common/weighted conservent une projection barycentrique unique; independent_masked résout un problème masqué distinct par espèce. free_surface_masked (0493x5a+) projette le liquide sur un support de remplissage absolu; le chemin actuellement qualifié requiert q6ForceProjectionMode=prestream_single_fused, une boîte fermée statique et exactement une espèce projetée. x6f/x6g séparent ensuite interface alpha=0.5, carrier et valeur de pression interfaciale.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X5A_PARTIAL_LIQUID_FREE_SURFACE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X5B_LIQUID_GAS_FREE_SURFACE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X6F_PHASE_INTERFACE_STENCIL.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493X6G_PHASE_GAS_PRESSURE.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x5a` — free_surface_masked initial
- `ASSOCIATED_WITH` → `x6f` — Stencil physique d'interface
- `ASSOCIATED_WITH` → `x6g` — Pression gazeuse interfaciale

### `speciesQ6Sensitivity`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** fini dans [0,1].
- **Catégorie :** Multi-espèces — projection Q6
- **Statut :** ajout 0491; étendu 0493w5–0493w8
- **Clé(s) `.kv` :** `speciesQ6Sensitivity`
- **Champ(s) C++ :** `speciesQ6Sensitivity`
- **Variables runner qui écrivent ce paramètre :** `SPECIES_Q6_SENSITIVITY`

Règle l’intensité de la différenciation des poids du mode weighted.

**Remarques.** Sans effet sur independent_masked; eta=0 redonne common.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0493W5_INDEPENDENT_MASKED_Q6_STAGE1.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W6_INDEPENDENT_MASKED_POSTAPPLY_DIAGNOSTIC.md`
- `DEFINED_OR_USED_IN` — `doc/README_0493W7_INDEPENDENT_MASKED_Q6_MULTIBC.md`
- `DEFINED_OR_USED_IN` — `include/q6_species_distribution_0491a.h`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/q6_species_distribution_0491a.cpp`

### `speciesRegistryEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — registre
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesRegistryEnable`
- **Champ(s) C++ :** `speciesRegistryEnable`

Active le registre reliant les valeurs de type aux espèces et familles de phase.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesRequireRegisteredTypes`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — registre
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesRequireRegisteredTypes`
- **Champ(s) C++ :** `speciesRequireRegisteredTypes`

Refuse tout type Fluid/Latent non enregistré; les slots Inactive sont exclus.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingCudaResidentDepositsEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — chemin CUDA résident
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingCudaResidentDepositsEnable`
- **Champ(s) C++ :** `speciesResamplingCudaResidentDepositsEnable`

Remplace les dépôts pondérés CPU par les dépôts résidents 0490h/0490n.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490N_CUDA_SPECIES_RESIDENT_MAINTENANCE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingCudaResidentFastPathEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — chemin CUDA résident
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingCudaResidentFastPathEnable`
- **Champ(s) C++ :** `speciesResamplingCudaResidentFastPathEnable`

Active le passage direct plan CUDA vers matérialisation et mutation résidente 0490m.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490M_CUDA_SPECIES_RESIDENT_FAST_PATH.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingCudaResidentMaintenanceStrict`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — chemin CUDA résident
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingCudaResidentMaintenanceStrict`
- **Champ(s) C++ :** `speciesResamplingCudaResidentMaintenanceStrict`

Interdit tout fallback CPU de maintenance et impose les composants résidents.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490N_CUDA_SPECIES_RESIDENT_MAINTENANCE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingCudaResidentPoolEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — chemin CUDA résident
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingCudaResidentPoolEnable`
- **Champ(s) C++ :** `speciesResamplingCudaResidentPoolEnable`

Remplace la reconstruction CPU du pool par les listes de rôles CUDA résidentes.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490N_CUDA_SPECIES_RESIDENT_MAINTENANCE.md`
- `DEFINED_OR_USED_IN` — `doc/README_0490P_DEVICE_CELL_POLICY_ZERO_CPU.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingCudaResidentValidationEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — chemin CUDA résident
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingCudaResidentValidationEnable`
- **Champ(s) C++ :** `speciesResamplingCudaResidentValidationEnable`

Active la porte stricte 0490l sans plan/opérations CPU de secours.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490A_SPECIES_REGISTRY_SCAFFOLD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingMassClosureCudaEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — fermeture de masse
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingMassClosureCudaEnable`
- **Champ(s) C++ :** `speciesResamplingMassClosureCudaEnable`

Exécute la fermeture multi-espèces sur l’état CUDA partagé.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490I_CUDA_SPECIES_MASS_CLOSURE.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingMassClosureEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — fermeture de masse
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingMassClosureEnable`
- **Champ(s) C++ :** `speciesResamplingMassClosureEnable`

Active la fermeture de masse dépendante de la composition.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490I_CUDA_SPECIES_MASS_CLOSURE.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingPopulationGuardCudaEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — garde de population
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingPopulationGuardCudaEnable`
- **Champ(s) C++ :** `speciesResamplingPopulationGuardCudaEnable`

Active la sélection d’espèce dans le garde de population CUDA 0297.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490J_CUDA_SPECIES_POPULATION_GUARD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingPopulationGuardEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — garde de population
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingPopulationGuardEnable`
- **Champ(s) C++ :** `speciesResamplingPopulationGuardEnable`

Active la sélection d’espèce du garde de population CPU.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490E_SPECIES_POPULATION_GUARD.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingTransferCudaEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — transferts donneur/receveur
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingTransferCudaEnable`
- **Champ(s) C++ :** `speciesResamplingTransferCudaEnable`

Active le plan natif CUDA de transferts contraints par type.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490K_CUDA_SPECIES_TRANSFER_PLAN.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesResamplingTransferEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true/1/yes/on ou false/0/no/off.
- **Catégorie :** Multi-espèces — transferts donneur/receveur
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesResamplingTransferEnable`
- **Champ(s) C++ :** `speciesResamplingTransferEnable`

Active le plan CPU de transferts donneur–receveur contraint par type.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490G_SPECIES_DONOR_RECEIVER_TRANSFERS.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesThermostatEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** true requiert thermostatEnable=true, registre d’espèces non vide, speciesRequireRegisteredTypes=true et une cible kBT positive finie résolue pour chaque espèce | mêmes gardes que la clé params
- **Catégorie :** Thermostat — multi-espèces x14
- **Statut :** ajout 0493x14a; actif dans la chaîne liquide/gaz x14
- **Clé(s) `.kv` :** `speciesThermostatEnable`
- **Champ(s) C++ :** `speciesThermostatEnable`
- **Variables runner qui écrivent ce paramètre :** `SPECIES_THERMOSTAT_ENABLE`

Conserve la collision SRC commune au mélange mais applique ensuite une remise à température séparée par type enregistré. | Champ SimulationParams activant le thermostat séparé par espèce.

**Remarques.** Opt-in; false préserve le chemin thermostat all-fluid historique. En CUDA résident, le workspace cellulaire est réutilisé successivement par espèce. | Audit x14ai-fix1 04/09/2026: sémantique params inchangée; aucune nouvelle clé params.kv introduite par x14y--x14ai-fix1. | Défaut false pour non-régression.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`
- `DEFINED_OR_USED_IN` — `src/thermostat.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x14ai` — Fermeture de résultante Q6 appliquée
- `ASSOCIATED_WITH` → `x14ai-fix1` — Fermeture B1 exacte post-correction périodique
- `ASSOCIATED_WITH` → `x14y` — Ablation sans soustraction p_g

### `speciesTransferCudaComparisonTolerance`

- **Type :** double
- **Défaut :** `1.0e-11`
- **Contraintes / valeurs :** fini et >=0.
- **Catégorie :** Multi-espèces — transferts donneur/receveur
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesTransferCudaComparisonTolerance`
- **Champ(s) C++ :** `speciesTransferCudaComparisonTolerance`

Tolérance de comparaison du plan CPU/CUDA.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490K_CUDA_SPECIES_TRANSFER_PLAN.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `speciesTransferCudaDiagnosticsFilename`

- **Type :** chaîne
- **Défaut :** `cuda_species_transfer_plan_0490k.csv`
- **Contraintes / valeurs :** -
- **Catégorie :** Multi-espèces — dépôt et diagnostics
- **Statut :** ajout 0490a–0490p
- **Clé(s) `.kv` :** `speciesTransferCudaDiagnosticsFilename`
- **Champ(s) C++ :** `speciesTransferCudaDiagnosticsFilename`

Nom du CSV de plan de transfert CUDA.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b. | Champ canonique ajouté/recensé depuis l’inventaire 0436b. Les vecteurs speciesDefinitions/openBoundarySegments sont construits après le premier passage du parseur.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0490K_CUDA_SPECIES_TRANSFER_PLAN.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `srcClassicCudaModeEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** CUDA — mode SRC classic
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `srcClassicCudaModeEnable`, `classicSrcCudaMode`, `classicSrcCudaModeEnable`, `classicSrcModeEnable`
- **Champ(s) C++ :** `srcClassicCudaModeEnable`
- **Autres alias :** `classicSrcCudaMode`, `classicSrcCudaModeEnable`, `classicSrcModeEnable`

Sélecteur .kv du chemin SRC/MPCD classic, séparé de la fermeture liquide. | Active le mode SRC classic complet; en CUDA 0286, le chemin classic full CUDA est la voie principale validée.

**Remarques.** Force le mode SRC classic complet: advection/streaming + shift + collision/rotation + thermostat. Court-circuite les fermetures Q6/resampling/viriel dans le driver; à utiliser pour les démos/validations classic CUDA 0275–0286.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/GPU_SRC_CLASSIC_CUDA_STATUS_0286.md`
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `StateInit.initialInactiveSlots`

- **Type :** entier
- **Défaut :** `0 ou fonction de gamma*Nx*Ny`
- **Contraintes / valeurs :** >=0
- **Catégorie :** État particulaire / pool inactif
- **Statut :** documenté 0426
- **Clé(s) `.kv` :** `initialInactiveSlots`
- **Autres alias :** `INACTIVE_SLOTS`

Réserve des slots inactifs dans l’état initial pour injection/remplissage.

**Remarques.** Particulièrement utile dans les scripts segmentés Darcy avec reservoir/inlet.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `summaryEvery`

- **Type :** entier
- **Défaut :** `10`
- **Contraintes / valeurs :** entier > 0
- **Catégorie :** I/O et exécution
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `summaryEvery`
- **Champ(s) C++ :** `summaryEvery`
- **Variables runner qui écrivent ce paramètre :** `MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS`

Cadence d’écriture de summary_runtime.csv et d’affichage de progression.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `summaryRoleFilter`

- **Type :** all|fluid | chaîne
- **Défaut :** `all dans le cœur; fluid dans scripts visuels | all`
- **Contraintes / valeurs :** -
- **Catégorie :** Summaries runtime | Sorties compactes — aliases rôle
- **Statut :** ajout 0314 | alias accepté; complété inventaire 0490p
- **Clé(s) `.kv` :** `summaryParticleRoleFilter`
- **Autres alias :** `summaryRoleFilter`
- **Variables runner qui écrivent ce paramètre :** `SUMMARY_ROLE_FILTER`

Contrôle si les summaries parcourent tous les slots ou un état compact fluide. | Alias de summaryRoleFilter.

**Remarques.** fluid réduit le coût lorsque INACTIVE_SLOTS est grand. | Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `surfaceTensionMinRadiusCells`

- **Type :** double fini >= 0
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0; 0 = no-op; valeur numérique de résolution, non constante physique universelle | >=0; 0 = no-op; recommandé actuel 3 pour les cas x9r
- **Catégorie :** Q6-G-F — tension superficielle / interface
- **Statut :** 0493x9r actif; choix de campagne x12 (JFM/x12yl=4, x12cal=3) | alias parser accepté; choix de campagne x12
- **Clé(s) `.kv` :** `surfaceTensionMinRadiusCells`, `q6GfSurfaceTensionMinRadiusCells`
- **Champ(s) C++ :** `surfaceTensionMinRadiusCells`
- **Autres alias :** `q6GfSurfaceTensionMinRadiusCells`
- **Variables runner qui écrivent ce paramètre :** `SURFACE_TENSION_MIN_RADIUS_CELLS`

Rayon minimal résolu en cellules pour la courbure utilisée uniquement dans sigma*kappa.

**Remarques.** 0493x9r: kappaLimit=1/(N_R*min(dx,dy)); le clip agit sur la courbure utilisée dans sigma*kappa, pas sur le champ brut. Le défaut struct reste 0.0. Il n'existe plus de 'choix 3' universel: x12b/x12c/x12d JFM et x12yl utilisent 4 par défaut; x12cal dynamique et certains anciens runners splash x12a utilisent 3.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12cal_capillary_calibrator.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12yl_young_laplace_calibrator.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x12a` — Refroidissement thermique local petites structures
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique capillaire
- `ASSOCIATED_WITH` → `x12d` — Benchmark JFM 524
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique de sigma
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `surfaceTensionSigma`

- **Type :** double fini >= 0
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >=0; 0 = no-op exact
- **Catégorie :** Q6-G-F — tension superficielle / interface
- **Statut :** 0493x9d actif; calibration mécanique x12yl + calibration dynamique séparée x12cal; utilisé JFM x12d | alias parser accepté de surfaceTensionSigma; actif
- **Clé(s) `.kv` :** `surfaceTensionSigma`, `q6GfSurfaceTensionSigma`
- **Champ(s) C++ :** `surfaceTensionSigma`
- **Autres alias :** `q6GfSurfaceTensionSigma`
- **Variables runner qui écrivent ce paramètre :** `SIGMA_ACTIVE`

Coefficient de tension superficielle utilisé dans le saut de Laplace p_A-p_B=sigma*kappa sur l’interface Q6-G-F.

**Remarques.** 0493x9d: saut de Laplace via phiGamma_cap=dt*sigma*kappa/rhoARef, sans force CSF/kick particulaire direct. État x12: distinguer strictement la calibration mécanique/statique x12yl (Young-Laplace apparié sigma>0/sigma=0 avec courbure mesurée) de la dispersion dynamique des ondes x12cal. Le script x12yl définit sigma_eff comme propriété mécanique scalaire; la dispersion capillaire n'est pas à replier automatiquement dans une renormalisation unique de sigma. Le benchmark JFM x12d écrit directement surfaceTensionSigma depuis SIGMA_ACTIVE. | Alias parser exact. Même physique et mêmes distinctions x12yl (mécanique/statique) vs x12cal (dynamique) que surfaceTensionSigma.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `scripts/analyze_0493x12yl_young_laplace_calibrator.py`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12cal_capillary_calibrator.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_0493x12d_jfm524_measurement_case.sh`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x12cal` — Calibrateur dynamique capillaire
- `ASSOCIATED_WITH` → `x12d` — Benchmark JFM 524
- `ASSOCIATED_WITH` → `x12yl` — Calibrateur mécanique de sigma
- `ASSOCIATED_WITH` → `x8k` — Inlet segmenté Poiseuille local
- `ASSOCIATED_WITH` → `x8t` — Relaxation densité sans mode moyen
- `ASSOCIATED_WITH` → `x9d` — Activation du saut de Laplace
- `ASSOCIATED_WITH` → `x9r` — Cutoff de petite courbure résolue

### `targetMeanUx`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Forçage et contrôle d’écoulement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `targetMeanUx`, `U0`, `meanFlowUx`
- **Champ(s) C++ :** `targetMeanUx`
- **Autres alias :** `U0`, `meanFlowUx`

Vitesse moyenne cible en x.

**Remarques.** Pris en compte si keepMeanFlowEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `targetMeanUy`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Forçage et contrôle d’écoulement
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `targetMeanUy`, `meanFlowUy`
- **Champ(s) C++ :** `targetMeanUy`
- **Autres alias :** `meanFlowUy`

Vitesse moyenne cible en y.

**Remarques.** Pris en compte si keepMeanFlowEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `taylorGreenForcingAmplitude`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0
- **Catégorie :** Forçage Taylor–Green
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `taylorGreenForcingAmplitude`, `tgForceAmplitude`, `tgForcingAmplitude`
- **Champ(s) C++ :** `taylorGreenForcingAmplitude`
- **Autres alias :** `tgForceAmplitude`, `tgForcingAmplitude`

Amplitude A du forçage Taylor–Green.

**Remarques.** Utilisé seulement si taylorGreenForcingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `taylorGreenForcingEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Forçage Taylor–Green
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `taylorGreenForcingEnable`, `tgForcingEnable`
- **Champ(s) C++ :** `taylorGreenForcingEnable`
- **Autres alias :** `tgForcingEnable`

Active un forçage corporel périodique divergence-free de type Taylor–Green.

**Remarques.** Restreint aux domaines périodiques x et y.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `taylorGreenForcingModeX`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Forçage Taylor–Green
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `taylorGreenForcingModeX`, `tgForcingModeX`
- **Champ(s) C++ :** `taylorGreenForcingModeX`
- **Autres alias :** `tgForcingModeX`

Nombre d’onde entier en x du forçage Taylor–Green.

**Remarques.** Utilisé seulement si taylorGreenForcingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `taylorGreenForcingModeY`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Forçage Taylor–Green
- **Statut :** existant catalogue 0292 | canonique | alias accepté
- **Clé(s) `.kv` :** `taylorGreenForcingModeY`, `tgForcingModeY`
- **Champ(s) C++ :** `taylorGreenForcingModeY`
- **Autres alias :** `tgForcingModeY`

Nombre d’onde entier en y du forçage Taylor–Green.

**Remarques.** Utilisé seulement si taylorGreenForcingEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `thermostatEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatEnable`
- **Champ(s) C++ :** `thermostatEnable`
- **Variables runner qui écrivent ce paramètre :** `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260`, `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE`, `THERMOSTAT_ENABLE`

Active le thermostat mass-aware par cellule. Pilote effectivement le thermostat quel que soit le backend CPU/GPU. | Active/désactive physiquement le thermostat en CPU et en GPU; 0291b empêche les flags CUDA de forcer le thermostat si false.

**Remarques.** 0291b: commutateur physique unique du thermostat. Si false, le thermostat est désactivé en CPU et en GPU; les variables CUDA ne peuvent plus forcer un thermostat fusionné. | 0493x14: speciesThermostatEnable=true requiert thermostatEnable=true; la collision reste commune, seule la remise à température est séparée par espèce.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
- `DEFINED_OR_USED_IN` — `src/src_collision.cpp`

### `thermostatEpsilon`

- **Type :** double
- **Défaut :** `1.0e-30`
- **Contraintes / valeurs :** >0 si thermostatEnable=true
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatEpsilon`
- **Champ(s) C++ :** `thermostatEpsilon`

Seuil numérique anti-division par zéro du thermostat.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `thermostatEvery`

- **Type :** entier
- **Défaut :** `1`
- **Contraintes / valeurs :** >0 si thermostatEnable=true
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatEvery`
- **Champ(s) C++ :** `thermostatEvery`

Cadence du thermostat en pas de temps.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `thermostatMinParticles`

- **Type :** entier
- **Défaut :** `3`
- **Contraintes / valeurs :** >=2 si thermostatEnable=true
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatMinParticles`
- **Champ(s) C++ :** `thermostatMinParticles`

Nombre minimal de particules d’une cellule pour thermostat.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `thermostatMode`

- **Type :** enum string
- **Défaut :** `cell_relative_rescale`
- **Contraintes / valeurs :** cell_relative_rescale
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatMode`
- **Champ(s) C++ :** `thermostatMode`

Mode de thermostat: rescale des vitesses relatives au centre de masse cellulaire.

**Remarques.** Si thermostatEnable=true.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `thermostatTargetKBT`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** négatif => hérite de kBT; sinon >0; 0 invalide si actif
- **Catégorie :** Thermostat
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `thermostatTargetKBT`
- **Champ(s) C++ :** `thermostatTargetKBT`

Température cinétique cible du thermostat.

**Remarques.** Si thermostatEnable=true et valeur négative, kBT doit être >0. | 0493x14: lorsque speciesThermostatEnable=true, les cibles speciesKThermostatTargetKBT résolues prennent le relais par type.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `TopoBenchmarkConfig.topoBenchmarkDragLiftEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkDragLiftEnable`
- **Autres alias :** `TOPO_BENCHMARK_DRAG_LIFT_ENABLE`

Active les projections drag/lift proxy.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkEnable`
- **Autres alias :** `TOPO_BENCHMARK_ENABLE`

Active le benchmark topologique optionnel.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkEvery`

- **Type :** entier
- **Défaut :** `darcyCostEvery`
- **Contraintes / valeurs :** >=1
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkEvery`
- **Autres alias :** `TOPO_BENCHMARK_EVERY`

Cadence d’écriture des observables topo.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkFilename`

- **Type :** nom fichier
- **Défaut :** `topo_benchmark_0348.csv`
- **Contraintes / valeurs :** chemin relatif outputDir
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkFilename`
- **Autres alias :** `TOPO_BENCHMARK_FILENAME`

Nom du CSV benchmark topo.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkFlowDirX`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** vecteur direction
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkFlowDirX`
- **Autres alias :** `TOPO_BENCHMARK_FLOW_DIR_X`

Composante x de la direction drag/écoulement.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkFlowDirY`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** vecteur direction
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkFlowDirY`
- **Autres alias :** `TOPO_BENCHMARK_FLOW_DIR_Y`

Composante y de la direction drag/écoulement.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkForceEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** true/false
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkForceEnable`
- **Autres alias :** `TOPO_BENCHMARK_FORCE_ENABLE`

Active les observables de force Darcy cell-based.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkLiftDirX`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** vecteur direction
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkLiftDirX`
- **Autres alias :** `TOPO_BENCHMARK_LIFT_DIR_X`

Composante x de la direction lift.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `TopoBenchmarkConfig.topoBenchmarkLiftDirY`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** vecteur direction
- **Catégorie :** Darcy/Brinkman — benchmark topo
- **Statut :** ajout 0348a/0348b
- **Clé(s) `.kv` :** `topoBenchmarkLiftDirY`
- **Autres alias :** `TOPO_BENCHMARK_LIFT_DIR_Y`

Composante y de la direction lift.

**Remarques.** Observables proxy : à interpréter comme force de pénalisation volumique, pas effort pariétal exact.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `doc/README_0426_DARCY_FASTFLAGS.md`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `DEFINED_OR_USED_IN` — `scripts/run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`

### `topOpenXMax`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `topOpenXMax`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `topOpenXMin`

- **Type :** clé supprimée
- **Défaut :** `(non applicable)`
- **Contraintes / valeurs :** Toujours rejetée; utiliser openBoundarySegmentsEnable/openBoundarySegmentCount/openBoundarySegmentK.
- **Catégorie :** Clés supprimées — migration vers segments 0143
- **Statut :** supprimé 0143; rejet explicite; recensé 0490p
- **Clé(s) `.kv` :** `topOpenXMin`

Clé params.kv lue par le parseur courant.

**Remarques.** Ligne ajoutée par comparaison exhaustive du parseur params.kv au commit 36abd23 avec l’inventaire consolidé 0436b.

### `virialDensityKickEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** si true: projection Q6 CUDA active; incompatible avec la restauration density-RHS active
- **Catégorie :** Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b
- **Statut :** ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q
- **Clé(s) `.kv` :** `virialDensityKickEnable`
- **Champ(s) C++ :** `virialDensityKickEnable`
- **Autres alias :** `virialEnable`

Active le kick de densité viriel continuum avant/avec le chemin de projection Q6.

**Remarques.** Fermeture opt-in distincte de la restauration signed1. x7q est volontairement inactif lorsque ce kick est demandé.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `virialMomentumCorrectionEnable`

- **Type :** booléen
- **Défaut :** `true`
- **Contraintes / valeurs :** booléen
- **Catégorie :** Projection Q6-g-f / fermeture virielle continuum 0493x7a–x7b
- **Statut :** ajout 0493x7a/x7b; omission d’inventaire corrigée 0493x7q
- **Clé(s) `.kv` :** `virialMomentumCorrectionEnable`
- **Champ(s) C++ :** `virialMomentumCorrectionEnable`

Active la correction globale de moment associée au kick viriel explicite.

**Remarques.** Distincte de la fermeture périodique x7q; x7q exclut le chemin virialDensityKickEnable.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/cuda_q6_resident_0400.cu`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

**Jalons associés :**
- `ASSOCIATED_WITH` → `x7q` — Fermeture exacte du moment périodique

### `wallAccommodation`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** [0,1]
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallAccommodation`
- **Champ(s) C++ :** `wallAccommodation`

Coefficient d’accommodation de paroi: 0 glissant/specular-like, 1 couplage thermique complet.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallKBT`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** négatif => hérite de kBT; sinon >0 si couplage actif
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallKBT`
- **Champ(s) C++ :** `wallKBT`
- **Variables runner qui écrivent ce paramètre :** `WALL_KBT`

Température cinétique de paroi.

**Remarques.** Si paroi active et accommodation>0, kBT doit être >0 si wallKBT/wallVpKBT sont négatifs.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallThermalNoise`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** >= 0
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallThermalNoise`
- **Champ(s) C++ :** `wallThermalNoise`

Amplitude du bruit thermique de paroi; 0 donne un couplage déterministe.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpEnable`

- **Type :** booléen
- **Défaut :** `false`
- **Contraintes / valeurs :** booléen: true/1/yes/on ou false/0/no/off
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallVpEnable`
- **Champ(s) C++ :** `wallVpEnable`

Active explicitement le couplage virtual-particle de paroi legacy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpGamma`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** >= 0; 0 infère l’occupation moyenne réelle
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallVpGamma`
- **Champ(s) C++ :** `wallVpGamma`

Population virtuelle de paroi dans une cellule de collision entièrement solide.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpKBT`

- **Type :** double
- **Défaut :** `-1.0`
- **Contraintes / valeurs :** alias legacy thermique; négatif => hérite de kBT; 0 invalide si actif
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallVpKBT`
- **Champ(s) C++ :** `wallVpKBT`

Ancien paramètre de température de paroi VP.

**Remarques.** Utilisé comme fallback si wallKBT n’est pas positif.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpMass`

- **Type :** double
- **Défaut :** `1.0`
- **Contraintes / valeurs :** > 0
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallVpMass`
- **Champ(s) C++ :** `wallVpMass`

Masse des particules virtuelles/agrégat de paroi.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpMode`

- **Type :** enum string
- **Défaut :** `thermal`
- **Contraintes / valeurs :** thermal; deterministic_thermal; stochastic_fraction
- **Catégorie :** Parois
- **Statut :** existant catalogue 0292 | canonique
- **Clé(s) `.kv` :** `wallVpMode`
- **Champ(s) C++ :** `wallVpMode`

Mode de couplage thermique de paroi; stochastic_fraction est accepté comme alias legacy.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUxBottom`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUxBottom`, `wallUxBottom`
- **Champ(s) C++ :** `wallVpUxBottom`
- **Autres alias :** `wallUxBottom`

Composante x de la vitesse de paroi sur la face bottom.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUxLeft`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUxLeft`, `wallUxLeft`
- **Champ(s) C++ :** `wallVpUxLeft`
- **Autres alias :** `wallUxLeft`

Composante x de la vitesse de paroi sur la face left.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUxRight`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUxRight`, `wallUxRight`
- **Champ(s) C++ :** `wallVpUxRight`
- **Autres alias :** `wallUxRight`

Composante x de la vitesse de paroi sur la face right.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUxTop`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUxTop`, `wallUxTop`
- **Champ(s) C++ :** `wallVpUxTop`
- **Autres alias :** `wallUxTop`

Composante x de la vitesse de paroi sur la face top.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUyBottom`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUyBottom`, `wallUyBottom`
- **Champ(s) C++ :** `wallVpUyBottom`
- **Autres alias :** `wallUyBottom`

Composante y de la vitesse de paroi sur la face bottom.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUyLeft`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUyLeft`, `wallUyLeft`
- **Champ(s) C++ :** `wallVpUyLeft`
- **Autres alias :** `wallUyLeft`

Composante y de la vitesse de paroi sur la face left.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUyRight`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUyRight`, `wallUyRight`
- **Champ(s) C++ :** `wallVpUyRight`
- **Autres alias :** `wallUyRight`

Composante y de la vitesse de paroi sur la face right.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`

### `wallVpUyTop`

- **Type :** double
- **Défaut :** `0.0`
- **Contraintes / valeurs :** nombre réel fini
- **Catégorie :** Parois — vitesses
- **Statut :** existant catalogue 0292 | alias accepté | canonique
- **Clé(s) `.kv` :** `wallVpUyTop`, `wallUyTop`
- **Champ(s) C++ :** `wallVpUyTop`
- **Autres alias :** `wallUyTop`

Composante y de la vitesse de paroi sur la face top.

**Sources / usages :**
- `DEFINED_OR_USED_IN` — `include/simulation_params.h`
- `DEFINED_OR_USED_IN` — `src/params_io_base.cpp`
