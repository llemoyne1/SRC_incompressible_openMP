# GPU patch 0262 build fix

This runner/build fix corrects the 0262 CUDA build source list.

The original 0262 build script referenced:

```text
src/cuda_streaming_solid_simple_0246.cu
```

That file is not part of the validated 0246 wall-simple patch. The correct source file is:

```text
src/cuda_streaming_wall_simple_0246.cu
```

Apply from repository root:

```bash
unzip -o gpu_patch_0262_buildfix_files_only.zip
bash scripts/run_cuda_classic_src_solid_resident_0262.sh
```
