# 0493x8d — qualification indépendante de Q6-g-f par Poiseuille

Objectif : qualifier **Q6-g-f comme fluide incompressible**, sans prendre SRC
ou Q6 comme solution de référence.

Aucune modification C++/CUDA et aucun nouveau diagnostic ne sont ajoutés.

## Fluide de base : configuration calibrée 0493w1

Les deux cas utilisent `a256_dt002_k125`, le compromis physiquement calibré :

- `a = 1/256`
- `gamma = 20`
- `dt = 0.002`
- `kBT = 0.125`
- masse particule = 1
- rotation = 90 deg, signe aléatoire, grid shift
- thermostat `cell_relative_rescale` à chaque pas
- `nu_ref = 0.00059751`
- `cs_ref = 0.35459`
- `Dself_ref = 0.00016588`
- `Sc ≈ 3.60`
- à `Uchar=0.1064`, `Lref=0.24` : `Re=42.73736`, `Ma=0.30006`.

Le choix évite explicitement l'ancien régime pathologique faible-Re / très fort Mach.

Le profil Q6-g-f de production est gelé : `prestream_single_fused`,
`free_surface_masked`, B1, x7j, tau_rho=.25, gate compression +3 particules,
traction -6 particules, gain 1, tolérance CG 1e-5, resampling off.

## Cas A — parois physiques

Canal `0.5 x 0.25`, grille `128 x 64`, périodique en x, parois physiques y.

La force `ax=0.008137608192` est choisie pour donner, avec `nu_ref`,
une vitesse de centre analytique `Uc=0.1064`. Le temps diffusif fondamental est
`H^2/(pi^2 nu_ref)=10.5983` ; 30000 pas donnent `t=60`, soit environ
`5.66` temps diffusifs.

La viscosité et la forme parabolique sont mesurées sur le régime tardif. Un fit
libre `U=A y(H-y)+B` donne aussi le slip extrapolé `B`.

## Cas B — paroi plane chi / Brinkman

Domaine **périodique x et y**, `0.5 x 0.3125`, grille `128 x 80`.

Une bande `chi=0` de 16 cellules (`S=0.0625`) laisse un canal fluide de 64
cellules (`H=0.25`). Il n'y a aucune paroi physique.

- Darcy forcing = `mean`
- chi collision VP = OFF
- `alpha=2.44740096`
- `alpha*dt=0.0048948019`
- `ell_B=sqrt(nu_ref/alpha)=0.015625=4a`.

L'alpha est volontairement **résolu** et non raide/saturé. Il qualifie d'abord
l'équation de Brinkman elle-même.

La force `ax=0.00630539487205` donne analytiquement, pour `nu_ref` :

- `u_interface=0.0239563632`
- `u_mean_fluid=0.0789187877`
- `u_center=0.1064`.

L'analyseur ajuste la viscosité sur la solution de Brinkman piècewise complète
et fait un second fit indépendant sur la parabole de la seule zone fluide.

## Résultat attendu

La qualification ne demande pas à Q6-g-f de reproduire SRC. Elle demande :

1. une viscosité Q6-g-f cohérente entre la paroi physique et le canal Brinkman ;
2. un Poiseuille physique de forme correcte, avec slip extrapolé faible ;
3. un profil chi compatible avec la solution analytique Brinkman ;
4. une longueur de pénétration résolue et mesurable.

Un sweep vers des alpha plus raides ne sera entrepris qu'après ce cas résolu.
