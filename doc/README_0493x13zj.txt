0493x13zj -- run_ok reference-fluid + LiveVis harmonization

Scope: scripts only; no C++/CUDA changes and no rebuild required.

Reference liquid defaults exposed in each run_ok runner:
  h = 1/256 via Lx/Nx = Ly/Ny
  gamma = 8
  liquid/reference particle mass = 1
  kBT = 0.125
  dt = 0.0063471328149122585
  rotation = 120 deg
  random rotation sign = true
  grid shift = true
  thermostat = cell_relative_rescale every step
  lambda/h = 0.72

Application rematching:
  tg U0=.05
  io_box Uin=.10
  step U=.12
  naca U=.10
  bend_pipe U=.10
  dambreak gravityY=-.01, liquid mass=1
  dripping gravityY=-.01
  injection Uin=.10, liquid mass=1, gas type-2 mass=.1 by default
  splash/puddle impact Vy=-.15

VK is replaced by the reduced Zovatto/Pedrizzetti demonstrator:
  grid 1200x400, domain 4.6875x1.5625, D/h=80, H/D=5,
  4D upstream + 11D downstream, nominal Re_H=280 using nu=5.6029e-4.

LiveVis:
  exactly one root control file: ./livevis_control.kv
  liveEvery=100
  recordEnable=true
  recordFields=mass,ux,uy
  recordEvery=100
  filterSampleEvery=100
  liveGridNx/liveGridNy are left unset so defaults inherit solver Nx/Ny.
  recordStride is commented because it is a legacy cadence alias that can
  override recordEvery depending on line order.

Recorder runtime caveat from existing 0432 implementation:
  recording grid/fields/filter/cadence are locked during an active session.
  To alter them live, set recordEnable=false, save, wait one control poll,
  edit values, then set recordEnable=true again. No core-code change is made.

The common launch summary is shortened to PATHS / FLUID / RUN / LIVE and no
longer prints the complete params.kv or environment.
