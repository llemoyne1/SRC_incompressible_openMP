function G = read_f64_grid_bin(filepath)
%READ_F64_GRID_BIN Read a binary double grid with [int32 Nx, int32 Ny] header.

fid = fopen(filepath, 'r');
assert(fid >= 0, 'Cannot open %s.', filepath);
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
Nx = fread(fid, 1, 'int32=>double');
Ny = fread(fid, 1, 'int32=>double');
assert(~isempty(Nx) && ~isempty(Ny), 'Invalid grid header in %s.', filepath);
Nc = Nx * Ny;
A = fread(fid, [Nc, 1], 'double=>double');
assert(numel(A) == Nc, 'Invalid payload size in %s.', filepath);
G = struct();
G.Nx = Nx;
G.Ny = Ny;
G.A = reshape(A, [Ny, Nx]);
end
