function state = read_smpcd_state(filename)
%READ_SMPCD_STATE Read SRCMPCD_STATE_BIN_V1/V2 particle state.
%
% V1 payload:
%   x, y, vx, vy, type, mass
%
% V2 payload:
%   x, y, vx, vy, type, mass, role
%
% The V2 role convention used by the OpenMP resampling branch is:
%   0 = Inactive, 1 = Fluid, 2 = Latent.
% V1 files are returned with role=Fluid for every particle.

    arguments
        filename (1,:) char
    end

    fid = fopen(filename, 'r', 'ieee-le');
    if fid < 0
        error('read_smpcd_state:openFailed', 'Cannot open file for reading: %s', filename);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    magic = fread(fid, 16, 'uint8=>uint8');
    expected = uint8(zeros(16,1));
    tag = uint8('SRCMPCD_STATE');
    expected(1:numel(tag)) = tag;
    if numel(magic) ~= 16 || any(magic ~= expected)
        error('read_smpcd_state:badMagic', 'Invalid .smpcd magic: %s', filename);
    end

    version = fread(fid, 1, 'uint32=>uint32');
    endian = fread(fid, 1, 'uint32=>uint32');
    dim = fread(fid, 1, 'uint32=>uint32');
    layout = fread(fid, 1, 'uint32=>uint32');
    Np = fread(fid, 1, 'uint64=>uint64');
    hasType = fread(fid, 1, 'uint32=>uint32');
    hasMass = fread(fid, 1, 'uint32=>uint32');
    realSize = fread(fid, 1, 'uint32=>uint32');
    typeSize = fread(fid, 1, 'uint32=>uint32');
    reserved = fread(fid, 8, 'uint64=>uint64');

    if ~(version == uint32(1) || version == uint32(2))
        error('read_smpcd_state:badVersion', 'Unsupported .smpcd version: %u', version);
    end
    if endian ~= uint32(hex2dec('01020304'))
        error('read_smpcd_state:badEndian', 'Unexpected endian marker.');
    end
    if dim ~= uint32(2) || layout ~= uint32(1) || hasType ~= uint32(1) || hasMass ~= uint32(1) || realSize ~= uint32(8) || typeSize ~= uint32(4)
        error('read_smpcd_state:unsupportedFormat', 'Unsupported .smpcd layout or scalar type.');
    end

    n = double(Np);
    state = struct();
    state.format = sprintf('SRCMPCD_STATE_BIN_V%d', double(version));
    state.dim = double(dim);
    state.Np = n;
    state.x = fread(fid, n, 'double=>double');
    state.y = fread(fid, n, 'double=>double');
    state.vx = fread(fid, n, 'double=>double');
    state.vy = fread(fid, n, 'double=>double');
    state.type = fread(fid, n, 'uint32=>uint32');
    state.mass = fread(fid, n, 'double=>double');

    if version == uint32(2)
        if numel(reserved) < 1 || reserved(1) ~= uint64(1)
            error('read_smpcd_state:badRoleFlag', 'Unsupported V2 role flag in: %s', filename);
        end
        state.role = fread(fid, n, 'uint8=>uint8');
    else
        state.role = ones(n, 1, 'uint8');
    end

    if numel(state.x) ~= n || numel(state.y) ~= n || numel(state.vx) ~= n || ...
       numel(state.vy) ~= n || numel(state.type) ~= n || numel(state.mass) ~= n || numel(state.role) ~= n
        error('read_smpcd_state:truncatedPayload', 'The .smpcd payload is truncated: %s', filename);
    end
end
