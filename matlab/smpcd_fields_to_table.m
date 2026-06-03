function T = smpcd_fields_to_table(fields, varargin)
%SMPCD_FIELDS_TO_TABLE Convert binned SRC/MPCD fields to a MATLAB table.

    p = inputParser;
    addRequired(p, 'fields', @isstruct);
    addParameter(p, 'step', NaN, @isnumeric);
    addParameter(p, 'time', NaN, @isnumeric);
    parse(p, fields, varargin{:});

    [Xc, Yc] = meshgrid(fields.xc, fields.yc);
    n = numel(Xc);
    step = repmat(double(p.Results.step), n, 1);
    time = repmat(double(p.Results.time), n, 1);

    T = table(step, time, Xc(:), Yc(:), ...
        fields.N(:), fields.mass(:), fields.rho(:), ...
        fields.Ux(:), fields.Uy(:), fields.speed(:), fields.omega(:), ...
        fields.dominantType(:), fields.dominantTypeFraction(:), ...
        'VariableNames', {'step','time','x','y','N','mass','rho','Ux','Uy','speed','omega','dominantType','dominantTypeFraction'});
end
