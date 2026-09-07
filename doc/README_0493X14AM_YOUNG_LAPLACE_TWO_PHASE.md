# 0493x14am — Young–Laplace diphasique multi-rayons

But : qualifier directement la tension superficielle mécanique avec gaz explicite, sans baseline longue sigma=0.

- liquide : point historique x13h (`gamma=8`, `120 deg`, `kBT_L=0.125`, `dt=0.0063471328149122585`)
- gaz : type 2, `mG=0.1`, `kBT_G=0.08`, Q6 direct OFF
- x6g : `eos_accessible_volume`, avec `KBT(global)=kBT_G` explicitement
- chaîne : x9 + x6g + x14l + x14v + x14ad + x14ai-fix1 + chaîne liquide qualifiée
- rayons screen : `R/h = 32 40 48 64`
- sigma : 10000
- observable : `cuda_static_drop_pressure_0493x9e.csv`
- fit principal : `pL-pG = b + sigma_eff <kappa_p3>`

Aucune modification C++/CUDA et aucun nouveau diagnostic runtime.
