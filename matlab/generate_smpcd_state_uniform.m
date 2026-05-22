function state = generate_smpcd_state_uniform(varargin)
%GENERATE_SMPCD_STATE_UNIFORM Generate a 2-D uniform SRC/MPCD initial state.
%
% Example:
%   state = generate_smpcd_state_uniform('output','initial_state.smpcd', ...
%       'Lx',1,'Ly',1,'Nx',64,'Ny',64,'gamma',20,'kBT',0.01, ...
%       'mass',1,'type',0,'seed',12345);

    p = inputParser;
    p.addParameter('output', '', @(s) ischar(s) || isstring(s));
    p.addParameter('Lx', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('Ly', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('Nx', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('Ny', 64, @(x) isnumeric(x) && isscalar(x) && x >= 1);
    p.addParameter('gamma', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && abs(x-round(x)) < eps);
    p.addParameter('kBT', 0.01, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('mass', 1.0, @(x) isnumeric(x) && isscalar(x) && x > 0);
    p.addParameter('type', uint32(0), @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.addParameter('seed', 12345, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('mode', 'uniform_per_cell', @(s) ischar(s) || isstring(s));
    p.addParameter('velocityMode', 'maxwell', @(s) ischar(s) || isstring(s));
    p.addParameter('removeMeanMomentum', true, @(x) islogical(x) && isscalar(x));
    p.addParameter('excludeCircle', false, @(x) islogical(x) && isscalar(x));
    p.addParameter('circleCx', 0.5, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('circleCy', 0.5, @(x) isnumeric(x) && isscalar(x));
    p.addParameter('circleR', 0.1, @(x) isnumeric(x) && isscalar(x) && x >= 0);
    p.parse(varargin{:});
    opt = p.Results;

    rng(double(opt.seed), 'twister');

    Nx = double(opt.Nx);
    Ny = double(opt.Ny);
    gamma = double(opt.gamma);
    Np = Nx * Ny * gamma;
    dx = opt.Lx / Nx;
    dy = opt.Ly / Ny;

    mode = char(opt.mode);
    switch mode
        case 'uniform_per_cell'
            [ix, iy] = ndgrid(0:Nx-1, 0:Ny-1);
            cellIx = repelem(ix(:), gamma);
            cellIy = repelem(iy(:), gamma);
            x = (cellIx + rand(Np,1)) * dx;
            y = (cellIy + rand(Np,1)) * dy;
        case 'uniform_random'
            x = opt.Lx * rand(Np,1);
            y = opt.Ly * rand(Np,1);
        otherwise
            error('generate_smpcd_state_uniform:badMode', 'Unknown mode: %s', mode);
    end

    if opt.excludeCircle && opt.circleR > 0
        inside = ((x - opt.circleCx).^2 + (y - opt.circleCy).^2) < opt.circleR.^2;
        while any(inside)
            nReplace = nnz(inside);
            x(inside) = opt.Lx * rand(nReplace,1);
            y(inside) = opt.Ly * rand(nReplace,1);
            inside = ((x - opt.circleCx).^2 + (y - opt.circleCy).^2) < opt.circleR.^2;
        end
    end

    velocityMode = char(opt.velocityMode);
    switch velocityMode
        case 'maxwell'
            sigma = sqrt(opt.kBT / opt.mass);
            vx = sigma * randn(Np,1);
            vy = sigma * randn(Np,1);
        case 'zero'
            vx = zeros(Np,1);
            vy = zeros(Np,1);
        otherwise
            error('generate_smpcd_state_uniform:badVelocityMode', 'Unknown velocityMode: %s', velocityMode);
    end

    type = repmat(uint32(opt.type), Np, 1);
    mass = repmat(double(opt.mass), Np, 1);

    if opt.removeMeanMomentum
        M = sum(mass);
        vx = vx - sum(mass .* vx) / M;
        vy = vy - sum(mass .* vy) / M;
    end

    state = struct();
    state.x = x;
    state.y = y;
    state.vx = vx;
    state.vy = vy;
    state.type = type;
    state.mass = mass;

    if strlength(string(opt.output)) > 0
        write_smpcd_state(char(opt.output), state);
    end
end
