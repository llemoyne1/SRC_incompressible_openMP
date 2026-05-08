function out = compare_step01_stream_bc_collision(prefixIn, prefixOut, params)
%COMPARE_STEP01_STREAM_BC_COLLISION Minimal post-processing for tranche 1.
%
% prefixIn  : prefix used with write_state_bin for input state
% prefixOut : output prefix produced by the C++ executable
% params    : params struct, used only for n and simple plotting helpers

Sin = read_state_bin(prefixIn, params.n, false, false);
Sout = read_state_bin(prefixOut, params.n, false, false);
G = read_cellfields_bin([prefixOut '_cellfields.bin']);
R = read_params_kv([prefixOut '_runout.kv']);

out = struct();
out.Sin = Sin;
out.Sout = Sout;
out.G = G;
out.runout = R;
out.dx_x = Sout.x(:,1) - Sin.x(:,1);
out.dx_y = Sout.x(:,2) - Sin.x(:,2);
out.dv_x = Sout.v(:,1) - Sin.v(:,1);
out.dv_y = Sout.v(:,2) - Sin.v(:,2);
out.energyIn = 0.5 * mean(sum(Sin.v.^2, 2));
out.energyOut = 0.5 * mean(sum(Sout.v.^2, 2));
out.meanVin = mean(Sin.v, 1);
out.meanVout = mean(Sout.v, 1);

fprintf('\n=== compare_step01_stream_bc_collision ===\n');
fprintf('mean dx                    : [%g, %g]\n', mean(out.dx_x), mean(out.dx_y));
fprintf('mean dv                    : [%g, %g]\n', mean(out.dv_x), mean(out.dv_y));
fprintf('mean velocity in / out     : [%g, %g] / [%g, %g]\n', ...
    out.meanVin(1), out.meanVin(2), out.meanVout(1), out.meanVout(2));
fprintf('mean kinetic energy in/out : %g / %g\n', out.energyIn, out.energyOut);
fprintf('==========================================\n');
end
