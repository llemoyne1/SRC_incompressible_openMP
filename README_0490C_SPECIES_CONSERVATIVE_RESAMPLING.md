# 0490c - species-conservative resampling safeguards

This patch is the first mutating multi-species safety patch. It does not yet
create per-species population targets or mass closures.

It guarantees the following invariants in the existing local population guard:

- CPU and CUDA rich-cell merges only combine particles with identical `type`;
- CUDA empty-cell refill remembers the previous single species of a cell instead
  of creating `type=0` particles;
- a cell whose remembered occupied state was mixed is skipped by empty refill,
  pending a later per-species refill policy;
- split operations keep inheriting the parent type.

The smoke test exercises a closed periodic mixed-species CUDA merge and a
single-species empty-refill memory case. Global species masses must be conserved
in both cases.
