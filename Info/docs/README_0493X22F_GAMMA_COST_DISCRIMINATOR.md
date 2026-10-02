# 0493x22f — gamma cost discriminator

Diagnostic-only paired wall timing on the frozen article binary.

Purpose: test whether the apparently large relative cost of current Q6-G-F at the article point is primarily caused by the low occupancy gamma=8, for which particle SRC is very cheap while the 128x128 elliptic solve has nearly fixed grid cost.

Matrix: gamma=8 and gamma=20, 128x128, h=1/256, same dt/kBT/alpha/seed, SRC_PROD versus current production Q6GF_PROD_X7J (x7j=1, 0407=0), 3 paired repetitions with alternating order. Internal profiles, LiveVis, recording and dumps are OFF during primary timing.

No solver source, physics, tolerance or article binary is modified.
