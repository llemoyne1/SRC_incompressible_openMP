from pathlib import Path

p = Path("src/cuda_resampling_pipeline_shadow_0445.cu")
s = p.read_text()

repls = {
    "        std::vector<unsigned int> hParticle(cpuOps0458.size());":
    "        std::vector<unsigned int> hParticle(maxOps, 0u);",

    "        std::vector<int> hDonor(cpuOps0458.size());":
    "        std::vector<int> hDonor(maxOps, -1);",

    "        std::vector<int> hReceiver(cpuOps0458.size());":
    "        std::vector<int> hReceiver(maxOps, -1);",

    "        std::vector<std::uint32_t> hType(cpuOps0458.size());":
    "        std::vector<std::uint32_t> hType(maxOps, 0u);",

    "        std::vector<double> hMass(cpuOps0458.size());":
    "        std::vector<double> hMass(maxOps, 0.0);",

    "        std::vector<double> hPx(cpuOps0458.size());":
    "        std::vector<double> hPx(maxOps, 0.0);",

    "        std::vector<double> hPy(cpuOps0458.size());":
    "        std::vector<double> hPy(maxOps, 0.0);",

    "        std::vector<double> hKe(cpuOps0458.size());":
    "        std::vector<double> hKe(maxOps, 0.0);",

    "        std::vector<std::uint8_t> hRole(cpuOps0458.size());":
    "        std::vector<std::uint8_t> hRole(maxOps, static_cast<std::uint8_t>(ParticleRole::Inactive));",
}

changed = 0
for old, new in repls.items():
    if old not in s:
        raise SystemExit(f"missing expected pattern: {old}")
    s = s.replace(old, new, 1)
    changed += 1

p.write_text(s)
print(f"[0458C] patched {changed} CPU-op carrier host buffers to maxOps-sized padded vectors")
