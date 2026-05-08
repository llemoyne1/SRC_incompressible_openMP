function write_params_kv(params, filepath)
%WRITE_PARAMS_KV Strict serialization of a params struct to key=value text.

fn = fieldnames(params);
fid = fopen(filepath, 'w');
assert(fid >= 0, 'Cannot open %s for writing.', filepath);
c = onCleanup(@() fclose(fid));

for k = 1:numel(fn)
    key = fn{k};
    val = params.(key);
    if islogical(val)
        assert(isscalar(val), 'Logical field %s must be scalar.', key);
        sval = string(val);
    elseif isnumeric(val)
        assert(isscalar(val), 'Numeric field %s must be scalar for params.kv.', key);
        sval = sprintf('%.17g', val);
    elseif isstring(val) || ischar(val)
        sval = string(val);
    else
        error('Unsupported params field type for %s.', key);
    end
    fprintf(fid, '%s=%s\n', key, char(sval));
end
end
