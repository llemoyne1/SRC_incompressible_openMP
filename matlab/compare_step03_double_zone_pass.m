function out = compare_step03_double_zone_pass(stateInPrefix, stateBasePrefix, stateOutPrefix, params)
%COMPARE_STEP03_DOUBLE_ZONE_PASS Compare tranche 3 double-pass states.
Sin = read_state_bin(stateInPrefix, params.n, true, true);
Sbase = read_state_bin(stateBasePrefix, params.n, true, true);
Sout = read_state_bin(stateOutPrefix, params.n, true, true);
Gin = local_compute_cell_fields(Sin.x, Sin.v, params);
Gbase = local_compute_cell_fields(Sbase.x, Sbase.v, params);
Gout = local_compute_cell_fields(Sout.x, Sout.v, params);
runout = read_params_kv([stateOutPrefix '_runout.kv']);
num = @(s) str2double(string(s));

out = struct();
out.meanDxBase = mean(abs(Sbase.x - Sin.x), 1);
out.meanDvBase = mean(abs(Sbase.v - Sin.v), 1);
out.meanDxShift = mean(abs(Sout.x - Sbase.x), 1);
out.meanDvShift = mean(abs(Sout.v - Sbase.v), 1);
out.meanDxTotal = mean(abs(Sout.x - Sin.x), 1);
out.meanDvTotal = mean(abs(Sout.v - Sin.v), 1);
out.meanVelIn = mean(Sin.v, 1);
out.meanVelBase = mean(Sbase.v,1);
out.meanVelOut = mean(Sout.v, 1);
out.meanEkIn = mean(0.5 * sum(Sin.v.^2, 2));
out.meanEkBase = mean(0.5 * sum(Sbase.v.^2, 2));
out.meanEkOut = mean(0.5 * sum(Sout.v.^2, 2));
out.Gin = Gin; out.Gbase = Gbase; out.Gout = Gout; out.runout = runout;

fprintf('\n=== compare_step03_double_zone_pass ===\n');
fprintf('mean dx base / shifted / total      : [%g, %g] / [%g, %g] / [%g, %g]\n', ...
    out.meanDxBase(1), out.meanDxBase(2), out.meanDxShift(1), out.meanDxShift(2), out.meanDxTotal(1), out.meanDxTotal(2));
fprintf('mean dv base / shifted / total      : [%g, %g] / [%g, %g] / [%g, %g]\n', ...
    out.meanDvBase(1), out.meanDvBase(2), out.meanDvShift(1), out.meanDvShift(2), out.meanDvTotal(1), out.meanDvTotal(2));
fprintf('mean velocity in / base / out       : [%g, %g] / [%g, %g] / [%g, %g]\n', ...
    out.meanVelIn(1), out.meanVelIn(2), out.meanVelBase(1), out.meanVelBase(2), out.meanVelOut(1), out.meanVelOut(2));
fprintf('mean kinetic energy in/base/out     : %g / %g / %g\n', out.meanEkIn, out.meanEkBase, out.meanEkOut);
if isfield(runout, 'base_occStdBefore') && isfield(runout, 'base_occStdAfter')
    fprintf('base occStd before / after          : %g / %g\n', num(runout.base_occStdBefore), num(runout.base_occStdAfter));
end
if isfield(runout, 'shifted_occStdBefore') && isfield(runout, 'shifted_occStdAfter')
    fprintf('shifted occStd before / after       : %g / %g\n', num(runout.shifted_occStdBefore), num(runout.shifted_occStdAfter));
end
if isfield(runout, 'base_outBandBefore') && isfield(runout, 'base_outBandAfter')
    fprintf('base outBand before / after         : %g / %g\n', num(runout.base_outBandBefore), num(runout.base_outBandAfter));
end
if isfield(runout, 'shifted_outBandBefore') && isfield(runout, 'shifted_outBandAfter')
    fprintf('shifted outBand before / after      : %g / %g\n', num(runout.shifted_outBandBefore), num(runout.shifted_outBandAfter));
end
if isfield(runout, 'totalParticlesMovedDense') && isfield(runout, 'totalParticlesMovedSparse')
    fprintf('nParticlesMoved total dense/sparse  : %g / %g\n', num(runout.totalParticlesMovedDense), num(runout.totalParticlesMovedSparse));
end
fprintf('==========================================\n');

figure('Name','tranche3_doublepass_compare');
subplot(1,3,1); imagesc(Gin.N); axis equal tight; set(gca,'YDir','normal'); colorbar; title('N before');
subplot(1,3,2); imagesc(Gbase.N); axis equal tight; set(gca,'YDir','normal'); colorbar; title('N after base');
subplot(1,3,3); imagesc(Gout.N); axis equal tight; set(gca,'YDir','normal'); colorbar; title('N after shifted');
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
