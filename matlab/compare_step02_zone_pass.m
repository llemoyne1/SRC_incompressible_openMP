function out = compare_step02_zone_pass(stateInPrefix, stateOutPrefix, params)
%COMPARE_STEP02_ZONE_PASS Compare tranche 2 zone-pass input/output states.

Sin = read_state_bin(stateInPrefix, params.n, true, true);
Sout = read_state_bin(stateOutPrefix, params.n, true, true);
Gin = local_compute_cell_fields(Sin.x, Sin.v, params);
Gout = local_compute_cell_fields(Sout.x, Sout.v, params);
runout = read_params_kv([stateOutPrefix '_runout.kv']);

out = struct();
out.meanDx = mean(abs(Sout.x - Sin.x), 1);
out.meanDv = mean(abs(Sout.v - Sin.v), 1);
out.meanVelIn = mean(Sin.v, 1);
out.meanVelOut = mean(Sout.v, 1);
out.meanEkIn = mean(0.5 * sum(Sin.v.^2, 2));
out.meanEkOut = mean(0.5 * sum(Sout.v.^2, 2));
out.Gin = Gin;
out.Gout = Gout;
out.runout = runout;
num = @(s) str2double(string(s));

fprintf('\n=== compare_step02_zone_pass ===\n');
fprintf('mean dx                       : [%g, %g]\n', out.meanDx(1), out.meanDx(2));
fprintf('mean dv                       : [%g, %g]\n', out.meanDv(1), out.meanDv(2));
fprintf('mean velocity in / out        : [%g, %g] / [%g, %g]\n', ...
    out.meanVelIn(1), out.meanVelIn(2), out.meanVelOut(1), out.meanVelOut(2));
fprintf('mean kinetic energy in / out  : %g / %g\n', out.meanEkIn, out.meanEkOut);
if isfield(runout, 'occStdBefore') && isfield(runout, 'occStdAfter')
    fprintf('occStd before / after         : %g / %g\n', num(runout.occStdBefore), num(runout.occStdAfter));
end
if isfield(runout, 'outBandBefore') && isfield(runout, 'outBandAfter')
    fprintf('outBand before / after        : %g / %g\n', num(runout.outBandBefore), num(runout.outBandAfter));
end
if isfield(runout, 'nParticlesMovedDense') && isfield(runout, 'nParticlesMovedSparse')
    fprintf('nParticlesMoved dense / sparse: %g / %g\n', num(runout.nParticlesMovedDense), num(runout.nParticlesMovedSparse));
end
fprintf('================================\n');

figure('Name','tranche2_zonepass_compare');
subplot(1,2,1);
imagesc(Gin.N); axis equal tight; set(gca,'YDir','normal'); colorbar;
title('N before');
subplot(1,2,2);
imagesc(Gout.N); axis equal tight; set(gca,'YDir','normal'); colorbar;
title('N after');
end

function G = local_compute_cell_fields(x, v, params)
aX = params.Lx / params.Nx;
aY = params.Ly / params.Ny;
ix = floor(x(:,1)/aX) + 1;
iy = floor(x(:,2)/aY) + 1;
ix = min(max(ix, 1), params.Nx);
iy = min(max(iy, 1), params.Ny);
ic = sub2ind([params.Ny, params.Nx], iy, ix);
Nc = params.Nc;
Nvec = accumarray(ic, 1, [Nc, 1], @sum, 0);
Pxvec = accumarray(ic, v(:,1), [Nc, 1], @sum, 0);
Pyvec = accumarray(ic, v(:,2), [Nc, 1], @sum, 0);
Uxvec = zeros(Nc,1); Uyvec = zeros(Nc,1);
mask = Nvec > 0;
Uxvec(mask) = Pxvec(mask) ./ Nvec(mask);
Uyvec(mask) = Pyvec(mask) ./ Nvec(mask);
G = struct();
G.N = reshape(Nvec, [params.Ny, params.Nx]);
G.Ux = reshape(Uxvec, [params.Ny, params.Nx]);
G.Uy = reshape(Uyvec, [params.Ny, params.Nx]);
end
