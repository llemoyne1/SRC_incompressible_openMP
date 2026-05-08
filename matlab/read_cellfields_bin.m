function G = read_cellfields_bin(filepath)
%READ_CELLFIELDS_BIN Read tranche 1 cell-field dump.

fid = fopen(filepath, 'r');
assert(fid >= 0, 'Cannot open %s.', filepath);
c = onCleanup(@() fclose(fid));

Nx = fread(fid, 1, 'int32=>double');
Ny = fread(fid, 1, 'int32=>double');
assert(~isempty(Nx) && ~isempty(Ny), 'Invalid cell field header.');
Nc = Nx * Ny;

G = struct();
G.Nx = Nx;
G.Ny = Ny;
G.N = reshape(fread(fid, [Nc, 1], 'int32=>double'), [Ny, Nx]);
G.Ux = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.Uy = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.Px = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.Py = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.T = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.rho = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.Pkin = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.Pvir = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.P = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
G.rhoTarget = reshape(fread(fid, [Nc, 1], 'double=>double'), [Ny, Nx]);
end
