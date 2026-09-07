# Architecture relationnelle

```text
objects
  ├── milestones
  ├── symbols ──< symbol_names
  ├── artifacts
  └── git commits
       │
       └──────── relations ────────┐
             source_object_id      │
             relation_type         │
             target_object_id ─────┘
```

Exemples :

```text
symbol:env:WALL_KBT
    --SETS_PARAMETER-->
symbol:param:wallKBT
    --DEFINED_OR_USED_IN-->
artifact:src/params_io_base.cpp
```

```text
milestone:0493x14ai-fix1
    --FIXES-->
milestone:0493x14ai

symbol:env:MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE
    --ASSOCIATED_WITH-->
milestone:0493x14ai-fix1
```

```text
artifact:scripts/run_0414_segmented_xy_neumann_qualification.sh
    --QUALIFIES-->
milestone:20260907-0414-segmented-xy
    --EXTENDS-->
milestone:0493x8r / x8s / x8t / x8k
```

Les relations automatiques sont associées à un niveau de confiance :

- `A` : relation explicite/provenance directe ;
- `B` : inférence structurée forte (nom de jalon dans fichier/métadonnée, alias normalisé) ;
- `C` : inférence textuelle historique à confirmer.
