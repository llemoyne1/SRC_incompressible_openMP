function G = read_i32_grid_bin(filepath)
%READ_I32_GRID_BIN Read an int32 grid dump with [Nx,Ny] header.

fid = fopen(filepath, 'r');
assert(fid >= 0, 'Cannot open %s.', filepath);
c = onCleanup(@() fclose(fid));

Nx = fread(fid, 1, 'int32=>double');
Ny = fread(fid, 1, 'int32=>double');
assert(~isempty(Nx) && ~isempty(Ny), 'Invalid i32 grid header.');
Nc = Nx * Ny;
vals = fread(fid, [Nc, 1], 'int32=>double');
assert(numel(vals) == Nc, 'Invalid i32 grid payload.');
G = struct();
G.Nx = Nx;
G.Ny = Ny;
G.data = reshape(vals, [Ny, Nx]);
end
