function write_state_bin(prefix, x, v, type, r0)
%WRITE_STATE_BIN Write interleaved particle arrays for the C++ tranche 1 code.
%
% x, v, r0 must be n x 2 arrays. type is optional uint8 n x 1.

assert(size(x,2) == 2, 'x must be n x 2');
assert(size(v,2) == 2, 'v must be n x 2');
assert(size(x,1) == size(v,1), 'x and v must have same number of particles');

n = size(x,1);
write_double_interleaved([prefix '_x.bin'], x, n);
write_double_interleaved([prefix '_v.bin'], v, n);

if nargin >= 4 && ~isempty(type)
    assert(numel(type) == n, 'type must have n elements');
    fid = fopen([prefix '_type.bin'], 'w');
    assert(fid >= 0, 'Cannot open type output file');
    c = onCleanup(@() fclose(fid));
    fwrite(fid, uint8(type(:)), 'uint8');
end

if nargin >= 5 && ~isempty(r0)
    assert(all(size(r0) == [n 2]), 'r0 must be n x 2');
    write_double_interleaved([prefix '_r0.bin'], r0, n);
end
end

function write_double_interleaved(filepath, A, n)
fid = fopen(filepath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', filepath);
c = onCleanup(@() fclose(fid));
B = reshape(A.', [2*n, 1]);
fwrite(fid, B, 'double');
end
