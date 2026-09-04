# 0493x14ai-fix1 — résultante Q6 réellement appliquée après correction périodique

## Problème corrigé

Le premier run n=2 x14ai a montré une fermeture du momentum au bruit numérique pendant de longues séquences, mais deux sauts discrets de momentum restaient. L'inspection du B1 montre que la vitesse réellement ajoutée aux particules est

```text
dv_applied = dv_RT0 - C_periodic
```

alors que x14ai accumulait encore la résultante brute `sum(m*dv_RT0)` comme cible de x14v.

Le fix1 remplace donc la cible globale par

```text
J_Q6,actual = sum(m*dv_RT0) - C_periodic * M_active
```

sans modifier la sémantique historique des diagnostics x7k `partialPx/partialPy`.

## Pourquoi la correction est faite globalement

`C_periodic` est uniforme sur les particules projetées. Il est donc inutile d'ajouter deux soustractions par particule. x14ai-fix1 conserve la réduction B1 existante et, dans un seul bloc, retranche une seule fois `C_periodic*M_active` de l'accumulateur x14ai.

Coût additionnel par rapport à x14ai :

```text
0 nouveau kernel
0 nouvelle passe particulaire
0 nouvelle passe cellule
0 nouveau buffer
0 nouvel atomicAdd
au plus 2 multiplications + 2 soustractions par lancement B1
```

Le contrat de coût x14ai (+16 octets, coût mesuré non résolu à ~1 %) reste donc inchangé à la résolution pratique.

## Installation

Le dépôt doit déjà contenir x14ai.

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o 0493x14ai_fix1_post_periodic_resultant.zip -d .

python3 tools/apply_0493x14ai_fix1_post_periodic_resultant.py

git diff --check
git diff --stat

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

Au démarrage d'un run x14ai actif, le marqueur devient :

```text
deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target
```

## Validation immédiate

Ne pas lancer encore le drag. Rejouer d'abord exactement le n=2 2000 steps :

```bash
bash scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh
```

Critères :

1. pas de sauts de momentum aux alentours des événements observés dans le premier run ;
2. momentum global au niveau du bruit numérique sur toute la fenêtre ;
3. fréquence n=2 et forme non régressées par rapport au premier x14ai ;
4. translation du centre de masse toujours quasi nulle.

Si ce contrôle passe, lancer ensuite le drag x14ah avec x14ai-fix1.
