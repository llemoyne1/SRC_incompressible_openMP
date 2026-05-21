function params = parse_smpcd_kv(filename)
%PARSE_SMPCD_KV Parse a simple key=value SRC/MPCD parameter file.
%
% params = parse_smpcd_kv(filename)
%
% The parser is intentionally small and permissive. It ignores blank lines and
% comments starting with '#'. Values are converted to double/logical when this
% is unambiguous; otherwise they are returned as strings.

    arguments
        filename (1,:) char
    end

    if ~isfile(filename)
        error('parse_smpcd_kv:fileNotFound', 'Cannot find parameter file: %s', filename);
    end

    params = struct();
    fid = fopen(filename, 'r');
    if fid < 0
        error('parse_smpcd_kv:openFailed', 'Cannot open parameter file: %s', filename);
    end
    cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

    lineNumber = 0;
    while true
        raw = fgetl(fid);
        if ~ischar(raw)
            break;
        end
        lineNumber = lineNumber + 1;

        commentPos = strfind(raw, '#');
        if ~isempty(commentPos)
            raw = raw(1:commentPos(1)-1);
        end
        raw = strtrim(raw);
        if isempty(raw)
            continue;
        end

        eqPos = strfind(raw, '=');
        if isempty(eqPos)
            warning('parse_smpcd_kv:ignoredLine', 'Ignoring malformed line %d in %s: %s', lineNumber, filename, raw);
            continue;
        end

        key = strtrim(raw(1:eqPos(1)-1));
        valueText = strtrim(raw(eqPos(1)+1:end));
        if isempty(key)
            warning('parse_smpcd_kv:emptyKey', 'Ignoring line %d with empty key in %s.', lineNumber, filename);
            continue;
        end

        key = matlab.lang.makeValidName(key);
        params.(key) = local_parse_value(valueText);
    end
end

function value = local_parse_value(valueText)
    if isempty(valueText)
        value = '';
        return;
    end

    lowerText = lower(valueText);
    if any(strcmp(lowerText, {'true','yes','on'}))
        value = true;
        return;
    end
    if any(strcmp(lowerText, {'false','no','off'}))
        value = false;
        return;
    end

    numericValue = str2double(valueText);
    if ~isnan(numericValue) && isfinite(numericValue)
        value = numericValue;
        return;
    end

    value = valueText;
end
