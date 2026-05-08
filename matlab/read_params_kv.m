function params = read_params_kv(filepath)
%READ_PARAMS_KV Read a key=value params file into a struct of strings.

fid = fopen(filepath, 'r');
assert(fid >= 0, 'Cannot open %s for reading.', filepath);
c = onCleanup(@() fclose(fid));
params = struct();

while true
    tline = fgetl(fid);
    if ~ischar(tline), break; end
    tline = strtrim(tline);
    if isempty(tline) || startsWith(tline, '#')
        continue;
    end
    parts = split(tline, '=');
    assert(numel(parts) >= 2, 'Invalid key=value line: %s', tline);
    key = matlab.lang.makeValidName(strtrim(parts{1}));
    val = strtrim(join(parts(2:end), '='));
    params.(key) = char(val);
end
end
