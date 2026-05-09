#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace mpcd {

struct Params {
    // domain / grid
    int Nx;
    int Ny;
    int Nc;
    int n;
    double Lx;
    double Ly;
    double dt;
    double a0;

    // MPCD
    double alpha;
    double kBT;
    double g;
    double bodyForceX;
    bool useThermostat;
    bool keepMeanFlow;

    // boundary conditions
    std::string boundary_left;
    std::string boundary_right;
    std::string boundary_bottom;
    std::string boundary_top;
    double Utop;
    double Ubottom;
    double wallSigma;

    // redistribution / closure (kept for later stages)
    bool noSurfaceCase;
    bool redistributionEnableSurfaceTopology;
    bool redistributionWallWettingEnabled;
    bool useInterfaceVelocityReorientation;
    bool useIncompressibleRedistribution;
    bool redistribAfterCollision;
    bool useZoneRedistribution;
    int zoneTileNx;
    int zoneTileNy;
    bool zoneUseShiftedSecondPass;
    bool zonePassthroughMode;
    bool zoneSingleFullDomainMode;
    bool enableMomentumCorrectionPostRedistribution;
    double gamma;
    double coef;
    std::string highMode;
    std::string lowMode;
    int maxRedistribPasses;
    bool useLocalFluidFractionThresholds;
    double fluidFracGain;
    double lowThrFloor;
    double highThrFloor;
    double lowThrBulkOverride;

    bool useLiquidClosure;
    bool useOptimalBetaRepair;
    double betaRepair;
    double betaEOS;
    double Kvirial;
    bool smoothPdriveAtInterzone;
    int smoothPdriveInterzoneWidthCells;
    double smoothPdriveInterzoneBlend;
    bool smoothPdriveIncludeShiftedLayouts;
      // Optional real-time visualization.
  // Commit 1 only wires parameters and a no-op backend.
  bool visualEnable;
  int visualEvery;
  std::string visualMode;              // particles | field | field_particles
  std::string visualField;             // Ux | Uy | speed | vorticity | N | rho
  bool visualFieldAutoScale;
  double visualFieldMin;
  double visualFieldMax;
  bool visualShowParticles;
  int visualMaxParticles;
  double visualPointSize;
  std::string visualParticleColorMode; // type | speed | Ux | Uy
    int visualWindowWidth;
  int visualWindowHeight;

  // Optional solid obstacle geometry.
  // Geometry only: no particle reflection is applied yet.
  bool obstacleEnable;
  std::string obstacleType; // none | cylinder
  double obstacleCx;
  double obstacleCy;
  double obstacleRadius;
};

struct State {
    std::vector<double> x;   // size 2*n, interleaved [x1,y1,x2,y2,...]
    std::vector<double> v;   // size 2*n, interleaved [vx1,vy1,...]
    std::vector<std::uint8_t> type;
    std::vector<double> r0;  // optional, size 2*n if present
};

struct CellFields {
    int Nx;
    int Ny;
    std::vector<std::int32_t> N;
    std::vector<double> Ux;
    std::vector<double> Uy;
    std::vector<double> Px;
    std::vector<double> Py;
    std::vector<double> T;
    std::vector<double> rho;
    std::vector<double> Pkin;
    std::vector<double> Pvir;
    std::vector<double> P;
    std::vector<double> rhoTarget;
};

struct WallInfo {
    int nBot = 0;
    int nTop = 0;
    int nLeft = 0;
    int nRight = 0;
    double dEwall = 0.0;
    double dPxBot = 0.0;
    double dPxTop = 0.0;
    double dPyBot = 0.0;
    double dPyTop = 0.0;
    double dPxLeft = 0.0;
    double dPxRight = 0.0;
    double dPyLeft = 0.0;
    double dPyRight = 0.0;
};

struct RunOutStep {
    std::string inputTag;
    std::string outputTag;
    double pBotInst = 0.0;
    double pTopInst = 0.0;
    double pMeanInst = 0.0;
    std::array<double, 6> redistribStats{};
    std::array<double, 10> redistDiag{};
    std::string layoutMode;
    int nZonesExecuted = 0;
};

} // namespace mpcd
