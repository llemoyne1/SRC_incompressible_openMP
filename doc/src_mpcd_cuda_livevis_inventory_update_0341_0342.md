# Mise à jour inventaire livevis — 0341a à 0342a

Cette mise à jour part de `src_mpcd_cuda_livevis_inventory_0314_to_0339a.csv` et ajoute les développements livevis récents.

## 0341a–0341d : contrôle runtime livevis

Ajouts principaux :

- `SRC_LIVE_VIS_CONTROL_FILE`, `SRC_LIVE_VIS_CONTROL_EVERY`, `SRC_LIVE_VIS_CONTROL_LOG` côté binaire ;
- `LIVE_VIS_CONTROL_ENABLE`, `LIVE_VIS_CONTROL_FILE`, `LIVE_VIS_CONTROL_DIR`, `LIVE_VIS_CONTROL_BASENAME`, `LIVE_VIS_CONTROL_FILE_EFFECTIVE`, `LIVE_VIS_CONTROL_EVERY`, `LIVE_VIS_CONTROL_LOG` côté scripts ;
- clés `livevis_control.kv:field`, `clip`, `gain`, `smoothPasses`.

`LIVE_VIS_CONTROL_FILE_EFFECTIVE` est documenté comme variable interne/résolue : il ne doit pas être fixé manuellement.

## 0342a : contrôle runtime du colormap

Ajouts principaux :

- `SRC_LIVE_VIS_COLORMAP` côté binaire ;
- `LIVE_VIS_COLORMAP` côté scripts ;
- clé `livevis_control.kv:colormap`.

Colormaps documentés : `blue_red`, `gray`, `thermal`.
