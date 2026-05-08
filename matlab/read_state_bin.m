function S = read_state_bin(prefix, n, hasType, hasR0)
%READ_STATE_BIN Read C++ tranche 1 state dumps.

if nargin < 3, hasType = false; end
if nargin < 4, hasR0 = false; end

S = struct();
S.x = read_double_interleaved([prefix '_x.bin'], n);
S.v = read_double_interleaved([prefix '_v.bin'], n);

if hasType
    fid = fopen([prefix '_type.bin'], 'r');
    assert(fid >= 0, 'Cannot open type file');
    c = onCleanup(@() fclose(fid));
    S.type = fread(fid, [n, 1], 'uint8=>uint8');
end

if hasR0
    S.r0 = read_double_interleaved([prefix '_r0.bin'], n);
end
end

function A = read_double_interleaved(filepath, n)
fid = fopen(filepath, 'r');
assert(fid >= 0, 'Cannot open %s.', filepath);
c = onCleanup(@() fclose(fid));
raw = fread(fid, [2*n, 1], 'double=>double');
assert(numel(raw) == 2*n, 'Unexpected payload length in %s.', filepath);
A = reshape(raw, [2, n]).';
end
