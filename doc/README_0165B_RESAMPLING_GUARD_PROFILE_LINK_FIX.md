# 0165b — correction lien fonctions de nommage profil guards

Correctif minimal du patch 0165.

## Problème

`main_src_mpcd_base.cpp` appelle :

- `mpcd::resampling_population_guard_profile_phase_name(std::size_t)`
- `mpcd::resampling_mass_guard_profile_phase_name(std::size_t)`

mais `weighted_resampling.cpp` ne fournissait pas les définitions externes correspondantes. La compilation passait, mais l’édition de liens échouait avec `undefined reference`.

## Correction

Ajout des deux fonctions dans `src/weighted_resampling.cpp`, dans le namespace `mpcd` public, juste après la fermeture du namespace anonyme.

Aucune logique physique ou algorithmique n’est modifiée.
