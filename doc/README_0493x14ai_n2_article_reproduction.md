# 0493x14ai-fix1 — reproduction article de la goutte oscillante diphasique n=2

Ce paquet ne reconstruit pas la physique x14ai-fix1. Il appelle le **runner historique exact**
déjà présent dans le dépôt :

`./scripts/run_0493x14ai_oscillating_drop_n2_device_closure.sh`

et vérifie avant exécution les empreintes archivées dans la base de référence du projet :

- runner : `acdf7bc0c829d26241539b7230bd4694f6ccf137295312f84a993bdf235fd45a`
- analyseur historique : `3ff2a7b9cae62d2bde4d11323c0f3b1ac0be1a299c762ef5736b77defc7fcc74`

Le run minimal est **le run historique de qualification** : seed `493180`, `2000` pas,
`dt=0.002`, soit `0<t<=4`. Il ne faut pas le raccourcir : le résultat archivé
`Gomega=0.9798833`, `beta=0.1694319`, `R2=0.997111` est précisément mesuré sur cette fenêtre.

Le wrapper n'impose aucun flag de physique x14. Ces flags restent sous l'autorité du runner
historique. Après calcul, le wrapper exige en plus le marqueur runtime :

`deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target`

afin d'éviter qu'un run exécuté avec une autre fermeture soit pris pour la validation x14ai-fix1.

## Installation

Depuis la racine du dépôt, copier les fichiers du ZIP en conservant l'arborescence :

- `scripts/run_0493x14ai_n2_article_reproduction.sh`
- `matlab/analyze_0493x14ai_n2_article.m`

Aucune compilation n'est demandée.

## Run minimal

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
chmod +x scripts/run_0493x14ai_n2_article_reproduction.sh
bash scripts/run_0493x14ai_n2_article_reproduction.sh
```

Le résultat demandé est placé sous :

`runs/0493x14ai_n2_article_reproduction_seed493180`

Le fichier `article_reproduction_provenance.txt` enregistre le HEAD Git courant, le hash du
binaire effectivement exécuté, les hashes du runner et de l'analyseur historiques et le marqueur
runtime de fermeture.

## Figures article

Depuis `matlab/` :

```matlab
analyze_0493x14ai_n2_article('../runs/0493x14ai_n2_article_reproduction_seed493180')
```

L'analyseur de figure **ne refit pas omega, beta, R2 ou Gomega**. Ces nombres sont lus dans
le rapport produit par l'analyseur historique. Il utilise les diagnostics bruts seulement pour
dessiner :

1. la réponse du mode n=2 et le fit historique ;
2. la dérive de quantité de mouvement totale liquide+gaz.

Il produit aussi les traces CSV, un résumé CSV et une ligne LaTeX afin que les figures restent
auditables.
