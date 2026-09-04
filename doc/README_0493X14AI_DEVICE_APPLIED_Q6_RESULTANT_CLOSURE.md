# 0493x14ai — fermeture conservative par résultante Q6 réellement appliquée

## Objet

x14af a fermé le bilan global de la goutte diphasique à l'arrondi numérique :

```text
Delta P_tot = J_Q6(applied,B1/RT0) - J_thermo(x14ad)
```

Le défaut de translation n=1 restant ne vient donc ni du scatter x14v (x14ae : zéro perte terminale), ni d'une inversion de la réflexion gaz x14l. Il vient du fait que x14ad impose comme résultante thermodynamique une quadrature de pression construite sur la géométrie Q6/x10n, alors que le liquide reçoit finalement une impulsion légèrement différente après le chemin discret CG -> corrections de faces/cellules -> B1/RT0 -> particules.

x14ai teste la fermeture minimale suivante :

```text
F_target = J_Q6(applied,B1/RT0) / dt
M lambda = F_target - F_local(x14ad)
Delta p_s* = Delta p_s(local,x14ad) + m_s . lambda
```

La loi locale x14ad, les normales x10n, x6g, x10o/CIC/Q2/x10p/q/x10u/x10v/x12a et la réflexion x14l ne sont pas modifiés. Seule la cible du mode résultant n=1 de la projection x14ad change.

Pour une composante liquide fermée et isolée des frontières Q6 externes, on obtient alors globalement

```text
J_liquid(interface) = J_Q6 + J_raw - J_thermo = J_raw
```

c'est-à-dire que la translation nette interfaciale est portée par l'impulsion cinétique réellement échangée avec le gaz, tandis que la distribution locale de pression reste celle de x14ad.

## Limite physique volontaire

Ce jalon est un candidat de production uniquement pour une composante liquide fermée qui ne touche ni paroi, ni inlet/outlet, ni autre frontière externe Q6. Ne pas l'étendre sans qualification à un ménisque attaché, une nappe en contact solide, ou un liquide dont le support Q6 touche une ouverture : `J_Q6(applied)` peut alors contenir une réaction extérieure physique qu'il ne faut pas compenser par l'interface gaz-liquide.

Le gate est OFF par défaut :

```bash
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
```

Il exige x14ad local-face gauge projection, x10o/CIC, B1/RT0, et x14z désactivé.

## Implémentation et contrat de coût

Le patch ajoute uniquement un buffer device de deux doubles :

```text
kineticAppliedQ6Resultant0493x14ai[2]  = 16 octets
```

Il est remis à zéro dans le kernel x10o déjà lancé avant B1. Dans B1, chaque thread accumule la même quantité `m*dv` que le diagnostic x14af. En mode x14ai sans diagnostic x14af, la réduction utilise :

- warp shuffles ;
- un seul rendez-vous `__syncthreads()` par bloc ;
- 2 doubles de shared memory par warp (128 octets pour le bloc actuel de 256 threads) ;
- deux `atomicAdd(double)` par bloc vers les deux scalaires device.

La fermeture consomme ces deux scalaires directement dans le kernel x14v prepare déjà existant. Le scratch historique x14ad reste exactement à 7 doubles.

Contrat structurel :

```text
+16 octets persistants
0 nouveau kernel
0 nouvelle passe particulaire
0 nouvelle passe cellule
0 transfert device -> host par step
0 second CG
0 buffer O(Np)
0 buffer O(Ncell)
```

Le coût restant doit néanmoins être mesuré : lecture de masse et accumulation `m*dv` dans B1, réduction warp/bloc, puis jusqu'à deux atomiques par bloc. Le package fournit donc un A/B apparié dédié.

## Installation

Depuis la racine du dépôt :

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x14ai_device_applied_q6_resultant_closure.zip -d .

python3 tools/apply_0493x14ai_device_applied_q6_resultant_closure.py

git diff --check
git diff --stat

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

L'installateur attend le jalon source x14af et est idempotent. Aucun fichier `livevis_control.kv` n'est modifié.

## Mesure du coût — A/B apparié

Lancer d'abord :

```bash
bash scripts/run_0493x14ai_cost_ab.sh
```

Valeurs par défaut :

```text
warm-up ON exclu : 100 steps
mesure : 3 paires OFF/ON
400 steps par run mesuré
ordre : OFF/ON, ON/OFF, OFF/ON
même seed et mêmes paramètres physiques
LiveVis OFF
recorder OFF
x14af/x14ae diagnostics OFF
analyse/tar du benchmark OFF pendant le chronométrage
```

Le temps utilisé est le temps du **binaire seulement**, déjà mesuré par `/usr/bin/time` dans le runner x14ah ; génération de l'état, analyse Python et compression ne sont donc pas comptées. Un échantillon `nvidia-smi` est conservé avant/après chaque run pour détecter une variation évidente de température, P-state ou fréquence GPU.

Sorties :

```text
runs/0493x14ai_cost_ab_seed493191/timing_0493x14ai.csv
runs/0493x14ai_cost_ab_seed493191/timing_summary_0493x14ai.json
runs/0493x14ai_cost_ab_seed493191/gpu_state_0493x14ai.csv
```

L'analyseur fournit notamment :

```text
OFF/ON median secondsPerStep
pairedMedianDeltaMicrosecondsPerStep
pairedMedianOverheadPercent
pairedMadPercent
runToRunNoiseProxyPercent
```

Verdict automatique :

```text
COST_NEGLIGIBLE_LE_2PCT
COST_ACCEPTABLE_2_TO_5PCT
COST_SIGNIFICANT_GT_5PCT
COST_NOT_RESOLVED_RUN_TO_RUN_NOISE
```

Si le coût n'est pas résolu par rapport au bruit, ne pas multiplier immédiatement les seeds physiques : refaire seulement le timing avec une fenêtre plus longue, par exemple :

```bash
TIMING_STEPS=800 TIMING_REPS=3 bash scripts/run_0493x14ai_cost_ab.sh
```

## Validation physique 1 — goutte oscillante n=2

Le wrapper de développement (préfixe `run_`, pas `run_ok_`) appelle le benchmark historique x14x sans le renommer :

```bash
bash scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh
```

Premier contrôle : fréquence/forme non régressées et disparition forte du mode de translation. Le recorder LiveVis est activé par défaut pour ce run de validation ; il est désactivé dans le timing A/B.

## Validation physique 2 — traînée dynamique x14ah

Le benchmark corrigé x14ah est fourni sous le nom de développement :

```bash
bash scripts/run_0493x14ai_drag_device_closure.sh
```

Il utilise un canal périodique en x, parois solides en y, un profil gazeux Poiseuille initial transitoire, sans inlet/outlet ni force volumique. La goutte initialement centrée doit continuer à migrer vers l'aval sous la vraie traînée gazeuse ; le mode transverse parasite observé avec x14ad doit être fortement réduit, sans annuler la traînée.

Le runner de base correspondant est désormais :

```text
scripts/run_0493x14ah_drop_gas_transient_poiseuille_drag.sh
```

Le préfixe `run_ok_*` reste réservé aux scripts historiques de démonstration/référence.

## Fichiers du package

```text
tools/apply_0493x14ai_device_applied_q6_resultant_closure.py
scripts/run_0493x14ah_drop_gas_transient_poiseuille_drag.sh
scripts/generate_0493x14ah_drop_gas_transient_poiseuille.py
scripts/analyze_0493x14ah_drop_gas_transient_poiseuille.py
scripts/run_0493x14ai_cost_ab.sh
scripts/analyze_0493x14ai_cost_ab.py
scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh
scripts/run_0493x14ai_drag_device_closure.sh
```
