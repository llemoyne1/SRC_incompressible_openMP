# 0493o1-fix2 — CUDA population-guard authority

The first 0493o1 integration correctly applied target-driven CUDA splits, but
then fell through to the historical CPU population support guard because the
legacy `speciesResamplingPopulationGuardCudaEnable` flag remained false.

That CPU guard performs N>NMax merges independently of
`resamplingExtractionEnable`.  A CPU merge inside the active prefix transfers
the victim mass to a survivor and marks the victim inactive.  The active-prefix
host/device synchronization later restores the complete prefix role mask to
Fluid, reactivating the victim payload and duplicating mass.

Fix2 treats `localSupportSplitOnly0493o1` as an authoritative CUDA guard result:

- the CPU population guard is bypassed;
- CUDA split diagnostics feed the generic population-guard summary;
- the shared CUDA state is not invalidated as though a CPU edit had occurred;
- the historical symmetric and species-CUDA paths are unchanged.
