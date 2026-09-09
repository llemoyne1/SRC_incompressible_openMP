# Curation V4.4 — série 0493 resident species-resampling / physics

## Périmètre

Cette curation couvre le premier cycle `0493` avant les séries `0493o`, `0493w` et
`0493x`. Elle ne suppose aucune progression alphabétique complète : seuls les labels
attestés par README, Git, code ou qualification sont promus.

## Jalons retenus

| Jalon | Nature | Preuve principale | Rôle |
|---|---|---|---|
| 0493A | INFRA | README + checker | routage résident universel |
| 0493B | CODE | README + Git | politique de mutation par espèce |
| 0493C | QUALIFICATION | README + runners | qualification frontières/Darcy |
| 0493C-fix3 | FIX | commit Git | seuils medium cohérents avec gamma |
| 0493D | PERF | code | sélection parallèle déterministe |
| 0493D-fix1 | FIX | commit + code | rejeu historique des mutations |
| 0493E | QUALIFICATION | README + smoke | physique mono-espèce |
| 0493F | QUALIFICATION | README + smoke | physique deux espèces |
| 0493F-fix2 | FIX | README + smoke | état de référence physiquement neutre |
| 0493G | CODE | README + code | restauration locale des moments par espèce |
| 0493H | QUALIFICATION | README + shear wave | diagnostic physique transport |
| 0493I | FIX | code + checker | fermeture conservative mono-espèce |
| 0493J | CODE | README + diagnostics | fermeture cinétique conservative par espèce |

Aucun `0493C-fix1/fix2` n'est créé : le suffixe `fix3` est visible dans Git, mais la
présente archive ne fournit pas assez de preuve pour reconstruire les deux numéros
intermédiaires. Ils restent donc à rechercher dans le backlog au lieu d'être inventés.

## Chaîne technique

`0493A/B` universalise la chaîne résidente et rend la mutation sélective par espèce.
`0493C` qualifie cette architecture. `0493D` traite ensuite le coût de sélection des
transferts tout en gardant un ordre déterministe.

`0493E/F` déplacent la qualification vers la physique. Le `F-fix2` construit un état à
deux espèces où les moments physiques initiaux sont uniformes malgré une population
checkerboard, afin que le resampling ne soit pas confondu avec un forçage initial.

`0493G` corrige la restauration de moment/énergie : chaque espèce est restaurée autour de
son propre barycentre, et non du barycentre de mélange. Le test d'onde de cisaillement
`0493H` montre néanmoins que la conservation globale reste insuffisante. `0493I` corrige
le branchement mono-espèce de la fermeture masse/impulsion, puis `0493J` ajoute la
fermeture conservative de l'énergie cinétique relative par espèce.

## Politique de preuve

Les jalons A/B/C/E/F/F-fix2/G/H/J disposent d'un README dédié. Les jalons D et I sont
conservés avec confiance B car leurs labels et leurs contrats sont explicitement présents
dans les sources de production et leurs checks. Les correctifs C-fix3 et D-fix1 sont
explicitement nommés dans l'historique Git.

Cette curation illustre la règle générale V4.4 : Git est une preuve majeure, mais pas la
seule source de vérité historique. Les documents de conception, commentaires de production
et validations reproductibles peuvent attester un jalon lorsque l'historique a consolidé
plusieurs étapes dans un même commit.
