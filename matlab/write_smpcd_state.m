function write_smpcd_state(filename, state)
%WRITE_SMPCD_STATE Write SRCMPCD_STATE_BIN_V1 particle state.
%
% Required fields, all column-compatible vectors of length Np:
%   state.x, state.y, state.vx, state.vy : double
%   state.type                           : uint32-compatible
%   state.mass                           : double
%
% The .smpcd file contains only the microscopic particle state. Simulation
% parameters remain in params.kv.

    arguments
        filename (1,:) char
        state struct
    end

    required = {'x','y','vx','vy','type','mass'};
    for k = 1:numel(required)
        if ~isfield(state, required{k})
            error('write_smpcd_state:missingField', 'Missing state.%s', required{k});
        end
    end

    x = double(state.x(:));
    y = double(state.y(:));
    vx = double(state.vx(:));
    vy = double(state.vy(:));
    type = uint32(state.type(:));
    mass = double(state.mass(:));

    Np = uint64(numel(x));
    n = double(Np);
    if numel(y) ~= n || numel(vx) ~= n || numel(vy) ~= n || numel(type) ~= n || numel(mass) ~= n
        error('write_smpcd_state:sizeMismatch', 'All state arrays must have the same length.');
    end

    fid = fopen(filename, 'w', 'ieee-le');
    if fid < 0
        error('write_smpcd_state:openFailed', 'Cannot open file for writing: %s', filename);
    end
    cleaner = onCleanup(@() fclose(fid));

    magic = uint8(zeros(16,1));
    tag = uint8('SRCMPCD_STATE');
    magic(1:numel(tag)) = tag;

    fwrite(fid, magic, 'uint8');
    fwrite(fid, uint32(1),          'uint32'); % version
    fwrite(fid, uint32(hex2dec('01020304')), 'uint32'); % endian marker
    fwrite(fid, uint32(2),          'uint32'); % dim
    fwrite(fid, uint32(1),          'uint32'); % layout: 1=SoA
    fwrite(fid, Np,                 'uint64');
    fwrite(fid, uint32(1),          'uint32'); % hasType
    fwrite(fid, uint32(1),          'uint32'); % hasMass
    fwrite(fid, uint32(8),          'uint32'); % realSize: double
    fwrite(fid, uint32(4),          'uint32'); % typeSize: uint32
    fwrite(fid, zeros(8,1,'uint64'),'uint64'); % reserved

    fwrite(fid, x,    'double');
    fwrite(fid, y,    'double');
    fwrite(fid, vx,   'double');
    fwrite(fid, vy,   'double');
    fwrite(fid, type, 'uint32');
    fwrite(fid, mass, 'double');
end
