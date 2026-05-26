function info = inspect_smpcd_state(filename, varargin)
%INSPECT_SMPCD_STATE Print and optionally plot a .smpcd particle state.
%
% Example:
%   info = inspect_smpcd_state('initial_state.smpcd', 'Lx',1,'Ly',1,'Nx',64,'Ny',64,'makePlots',true);

    p = inputParser;
    p.addRequired('filename', @(s) ischar(s) || isstring(s));
    p.addParameter('Lx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('Ly', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x > 0));
    p.addParameter('Nx', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    p.addParameter('Ny', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
    p.addParameter('makePlots', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('maxScatter', 20000, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.parse(filename, varargin{:});
    opt = p.Results;

    s = read_smpcd_state(char(filename));
    m = s.mass(:);
    vx = s.vx(:);
    vy = s.vy(:);
    M = sum(m);
    Px = sum(m .* vx);
    Py = sum(m .* vy);
    ux = Px / M;
    uy = Py / M;
    dvx = vx - ux;
    dvy = vy - uy;
    Ekin = 0.5 * sum(m .* (vx.^2 + vy.^2));
    Erel = 0.5 * sum(m .* (dvx.^2 + dvy.^2));
    dof = max(2 * double(s.Np) - 2, 1);
    kBT_est = 2 * Erel / dof;

    [utype, ~, ic] = unique(s.type);
    typeCounts = accumarray(ic, 1);

    info = struct();
    info.filename = char(filename);
    info.format = s.format;
    info.dim = s.dim;
    info.Np = s.Np;
    info.xRange = [min(s.x), max(s.x)];
    info.yRange = [min(s.y), max(s.y)];
    info.vxMeanStd = [mean(vx), std(vx)];
    info.vyMeanStd = [mean(vy), std(vy)];
    info.massRange = [min(m), max(m)];
    info.totalMass = M;
    info.momentum = [Px, Py];
    info.meanVelocity = [ux, uy];
    info.meanKineticEnergyPerParticle = Ekin / double(s.Np);
    info.estimatedKBT = kBT_est;
    info.types = table(utype(:), typeCounts(:), 'VariableNames', {'type','count'});

    fprintf('File                         : %s\n', info.filename);
    fprintf('Format                       : %s\n', info.format);
    fprintf('Dimension                    : %d\n', info.dim);
    fprintf('Particles                    : %d\n', info.Np);
    fprintf('x range                      : [%.16g, %.16g]\n', info.xRange(1), info.xRange(2));
    fprintf('y range                      : [%.16g, %.16g]\n', info.yRange(1), info.yRange(2));
    fprintf('vx mean/std                  : %.16g / %.16g\n', info.vxMeanStd(1), info.vxMeanStd(2));
    fprintf('vy mean/std                  : %.16g / %.16g\n', info.vyMeanStd(1), info.vyMeanStd(2));
    fprintf('mass min/max                 : %.16g / %.16g\n', info.massRange(1), info.massRange(2));
    fprintf('total mass                   : %.16g\n', info.totalMass);
    fprintf('momentum Px,Py               : %.16g / %.16g\n', info.momentum(1), info.momentum(2));
    fprintf('mean velocity Ux,Uy          : %.16g / %.16g\n', info.meanVelocity(1), info.meanVelocity(2));
    fprintf('mean kinetic energy/particle : %.16g\n', info.meanKineticEnergyPerParticle);
    fprintf('estimated kBT                : %.16g\n', info.estimatedKBT);
    disp(info.types);

    if opt.makePlots
        idx = 1:s.Np;
        if s.Np > opt.maxScatter
            idx = randperm(s.Np, opt.maxScatter);
        end

        figure('Name', 'SMPCD state: particle positions');
        scatter(s.x(idx), s.y(idx), 4, double(s.type(idx)), 'filled');
        axis equal tight;
        xlabel('x'); ylabel('y'); title('Particle positions, colored by type');
        colorbar;

        figure('Name', 'SMPCD state: velocity histograms');
        histogram(s.vx, 80); hold on;
        histogram(s.vy, 80);
        xlabel('velocity'); ylabel('count'); legend('vx','vy'); title('Velocity distributions');

        if ~isempty(opt.Lx) && ~isempty(opt.Ly) && ~isempty(opt.Nx) && ~isempty(opt.Ny)
            ix = min(max(floor(s.x / opt.Lx * opt.Nx) + 1, 1), opt.Nx);
            iy = min(max(floor(s.y / opt.Ly * opt.Ny) + 1, 1), opt.Ny);
            N = accumarray([iy(:), ix(:)], 1, [opt.Ny, opt.Nx], @sum, 0);
            figure('Name', 'SMPCD state: cell occupancy');
            imagesc(N); axis image; colorbar;
            xlabel('ix'); ylabel('iy'); title('Cell occupancy N');
        end
    end
end
