function write_smpcd_state(filename, state)
%WRITE_SMPCD_STATE Write SRCMPCD_STATE_BIN_V1/V2 particle state.
%
% Required fields, all column-compatible vectors of length Np:
%   state.x, state.y, state.vx, state.vy : double
%   state.type                           : uint32-compatible
%   state.mass                           : double
%
% Optional field:
%   state.role                           : uint8-compatible
%
% If state.role is present, the writer emits the OpenMP resampling V2 format:
%   x, y, vx, vy, type, mass, role
% with role convention 0=Inactive, 1=Fluid, 2=Latent.  Without state.role, it
% keeps emitting the legacy V1 payload so old generators remain unchanged.

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

    hasRole = isfield(state, 'role') && ~isempty(state.role);
    if hasRole
        role = uint8(state.role(:));
        if numel(role) ~= n
            error('write_smpcd_state:roleSizeMismatch', 'state.role must have the same length as state.x.');
        end
        version = uint32(2);
    else
        role = uint8.empty(0,1);
        version = uint32(1);
    end

    fid = fopen(filename, 'w', 'ieee-le');
    if fid < 0
        error('write_smpcd_state:openFailed', 'Cannot open file for writing: %s', filename);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    magic = uint8(zeros(16,1));
    tag = uint8('SRCMPCD_STATE');
    magic(1:numel(tag)) = tag;

    fwrite(fid, magic, 'uint8');
    fwrite(fid, version,          'uint32'); % version
    fwrite(fid, uint32(hex2dec('01020304')), 'uint32'); % endian marker
    fwrite(fid, uint32(2),          'uint32'); % dim
    fwrite(fid, uint32(1),          'uint32'); % layout: 1=SoA
    fwrite(fid, Np,                 'uint64');
    fwrite(fid, uint32(1),          'uint32'); % hasType
    fwrite(fid, uint32(1),          'uint32'); % hasMass
    fwrite(fid, uint32(8),          'uint32'); % realSize: double
    fwrite(fid, uint32(4),          'uint32'); % typeSize: uint32

    reserved = zeros(8,1,'uint64');
    if hasRole
        reserved(1) = uint64(1); % has role payload
        reserved(2) = uint64(1); % role scalar size in bytes
    end
    fwrite(fid, reserved, 'uint64');

    fwrite(fid, x,    'double');
    fwrite(fid, y,    'double');
    fwrite(fid, vx,   'double');
    fwrite(fid, vy,   'double');
    fwrite(fid, type, 'uint32');
    fwrite(fid, mass, 'double');
    if hasRole
        fwrite(fid, role, 'uint8');
    end
end
