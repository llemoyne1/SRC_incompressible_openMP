# 0366 — Segments quiver en noir

## Objet

Ce correctif remplace la couleur blanche des segments quiver par une couleur **noire** dans la visualisation live. Sur les cartes `thermal` ou sur des fonds localement clairs, les segments noirs sont plus visibles que les segments blancs.

## Modification

Dans `src/live_visualization_0335.cpp`, la couleur OpenGL de l’overlay quiver passe de :

```cpp
glColor3f(1.0f, 1.0f, 1.0f);
```

à :

```cpp
glColor3f(0.0f, 0.0f, 0.0f);
```

## Impact performance

Aucun impact mesurable sur le temps d’exécution : seul l’état de couleur OpenGL est modifié.
