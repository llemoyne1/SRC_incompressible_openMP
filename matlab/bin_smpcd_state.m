function fields = bin_smpcd_state(state, varargin)
%BIN_SMPCD_STATE Bin a particle state into regular cell fields.
%
% fields = bin_smpcd_state(state, 'Lx', 1, 'Ly', 1, 'Nx', 32, 'Ny', 32)
%
% Output matrices are Ny-by-Nx, with rows corresponding to y-cells and columns
% corresponding to x-cells. Velocity is mass-weighted. Vorticity is computed as
% omega_z = dUy/dx - dUx/dy.

    p = inputParser;
    addRequired(p, 'state', @isstruct);
    addParameter(p, 'Lx', [], @isnumeric);
    addParameter(p, 'Ly', [], @isnumeric);
    addParameter(p, 'Nx', [], @isnumeric);
    addParameter(p, 'Ny', [], @isnumeric);
    addParameter(p, 'periodicX', true, @islogical);
    addParameter(p, 'periodicY', true, @islogical);
    addParameter(p, 'fluidOnly', true, @(x) islogical(x) || isnumeric(x));
    parse(p, state, varargin{:});

    Lx = p.Results.Lx;
    Ly = p.Results.Ly;
    Nx = p.Results.Nx;
    Ny = p.Results.Ny;
    if isempty(Lx) || isempty(Ly) || isempty(Nx) || isempty(Ny)
        error('bin_smpcd_state:missingGrid', 'Lx, Ly, Nx and Ny are required.');
    end
    Nx = double(Nx);
    Ny = double(Ny);
    Lx = double(Lx);
    Ly = double(Ly);

    x = double(state.x(:));
    y = double(state.y(:));
    vx = double(state.vx(:));
    vy = double(state.vy(:));
    mass = double(state.mass(:));
    type = double(state.type(:));

    if isfield(state, 'role') && ~isempty(state.role)
        role = uint8(state.role(:));
    else
        role = ones(numel(x), 1, 'uint8');
    end
    if logical(p.Results.fluidOnly)
        keep = role == uint8(1);
        x = x(keep);
        y = y(keep);
        vx = vx(keep);
        vy = vy(keep);
        mass = mass(keep);
        type = type(keep);
    end

    dx = Lx / Nx;
    dy = Ly / Ny;

    if p.Results.periodicX
        x = mod(x, Lx);
    end
    if p.Results.periodicY
        y = mod(y, Ly);
    end

    ix = floor(x / dx) + 1;
    iy = floor(y / dy) + 1;
    ix = min(max(ix, 1), Nx);
    iy = min(max(iy, 1), Ny);

    subs = [iy, ix];
    sz = [Ny, Nx];

    N = accumarray(subs, 1, sz, @sum, 0);
    M = accumarray(subs, mass, sz, @sum, 0);
    Px = accumarray(subs, mass .* vx, sz, @sum, 0);
    Py = accumarray(subs, mass .* vy, sz, @sum, 0);
    KE = accumarray(subs, 0.5 .* mass .* (vx.^2 + vy.^2), sz, @sum, 0);

    Ux = nan(sz);
    Uy = nan(sz);
    nonEmpty = M > 0;
    Ux(nonEmpty) = Px(nonEmpty) ./ M(nonEmpty);
    Uy(nonEmpty) = Py(nonEmpty) ./ M(nonEmpty);

    % Use zero velocity in empty cells for derived spatial operators. Empty
    % cells remain identifiable through N and M.
    UxForCurl = Ux;
    UyForCurl = Uy;
    UxForCurl(~nonEmpty) = 0;
    UyForCurl(~nonEmpty) = 0;
    [dUx_dy, ~] = gradient(UxForCurl, dy, dx);
    [~, dUy_dx] = gradient(UyForCurl, dy, dx);
    omega = dUy_dx - dUx_dy;

    speed = sqrt(Ux.^2 + Uy.^2);
    rho = M ./ (dx * dy);
    kBTcell = nan(sz);
    kBTcell(nonEmpty) = KE(nonEmpty) ./ max(N(nonEmpty), 1); % 2D: KE per particle equals kBT for zero mean only approximately.

    [dominantType, dominantTypeFraction] = local_dominant_type(subs, type, sz, N);

    fields = struct();
    fields.Nx = Nx;
    fields.Ny = Ny;
    fields.Lx = Lx;
    fields.Ly = Ly;
    fields.dx = dx;
    fields.dy = dy;
    fields.xc = ((0:Nx-1) + 0.5) * dx;
    fields.yc = ((0:Ny-1) + 0.5) * dy;
    fields.N = N;
    fields.mass = M;
    fields.rho = rho;
    fields.Ux = Ux;
    fields.Uy = Uy;
    fields.speed = speed;
    fields.omega = omega;
    fields.kineticEnergy = KE;
    fields.kBTcell = kBTcell;
    fields.dominantType = dominantType;
    fields.dominantTypeFraction = dominantTypeFraction;
end

function [dominantType, fraction] = local_dominant_type(subs, type, sz, N)
    dominantType = nan(sz);
    fraction = nan(sz);
    uniqueTypes = unique(type(:));
    if isempty(uniqueTypes)
        return;
    end

    bestCount = zeros(sz);
    for k = 1:numel(uniqueTypes)
        tk = uniqueTypes(k);
        counts = accumarray(subs(type == tk, :), 1, sz, @sum, 0);
        replace = counts > bestCount;
        dominantType(replace) = tk;
        bestCount(replace) = counts(replace);
    end
    nonEmpty = N > 0;
    fraction(nonEmpty) = bestCount(nonEmpty) ./ N(nonEmpty);
end
