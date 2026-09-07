# 0493x14al — Taylor–Culick historique x13h, paire A/B

Objectif : isoler l'effet du gaz/couplage x14 sans changer le liquide de la campagne x13h.

- A `CASE=liquid` : liquide/vide, point x13h historique exact.
- B `CASE=liquid_gas` : même liquide initial (SHA-256 canonique identique), gaz x14 ajouté à l'extérieur.
- Aucun changement C++/CUDA.
- `./livevis_control.kv` n'est jamais modifié ; chaque run crée son contrôle dans son propre `RUN_ROOT`.
- Analyse A/B commune depuis l'enregistrement `mass` filtré type liquide, puis A rejoue aussi l'analyseur historique x13n sur les dumps 10 pas.
