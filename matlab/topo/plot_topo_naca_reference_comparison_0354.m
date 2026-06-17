function C = plot_topo_naca_reference_comparison_0354(proxyCsv, varargin)
%PLOT_TOPO_NACA_REFERENCE_COMPARISON_0354 Compare SRC-Darcy NACA proxy to reference polar.
%
% C = plot_topo_naca_reference_comparison_0354(proxyCsv, ...
%       'ReferenceCsv', 'data/reference/naca0012_ladson_re6e6_reference_0354.csv', ...
%       'OutputDir', 'runs/topo_matlab_plots_0354', ...
%       'ShowFigures', true)
%
% The comparison is intentionally normalized:
%   lift proxy is normalized by its value at NormalizeAoA (default 10 deg)
%   reference CL is normalized by CL at NormalizeAoA
%   drag proxy is normalized by its value at 0 deg
%   reference CD is normalized by CD at 0 deg
%
% This avoids treating the Darcy/Brinkman force proxies as calibrated CL/CD.

p = inputParser;
addRequired(p, 'proxyCsv', @(s)ischar(s) || isstring(s));
addParameter(p, 'ReferenceCsv', fullfile('data','reference','naca0012_ladson_re6e6_reference_0354.csv'), @(s)ischar(s) || isstring(s));
addParameter(p, 'OutputDir', fullfile('runs','topo_matlab_plots_0354'), @(s)ischar(s) || isstring(s));
addParameter(p, 'ShowFigures', true, @(x)islogical(x) || isnumeric(x));
addParameter(p, 'Prefix', 'naca0012_reference_comparison_0354', @(s)ischar(s) || isstring(s));
addParameter(p, 'NormalizeAoA', 10, @isnumeric);
parse(p, proxyCsv, varargin{:});

proxyCsv = char(p.Results.proxyCsv);
refCsv = char(p.Results.ReferenceCsv);
outDir = char(p.Results.OutputDir);
prefix = char(p.Results.Prefix);
showFigures = logical(p.Results.ShowFigures);
normalizeAoA = double(p.Results.NormalizeAoA);

if ~isfile(proxyCsv)
    error('Missing proxy CSV: %s', proxyCsv);
end
if ~isfile(refCsv)
    error('Missing reference CSV: %s', refCsv);
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

P = local_read_csv(proxyCsv);
R = local_read_csv(refCsv);

aoaP = local_col(P, 'aoaDeg');
liftP = local_col(P, 'liftProxy_mean');
dragP = local_col(P, 'dragProxy_mean');

aoaR = local_col(R, 'aoaDeg');
liftR = local_col(R, 'CL');
dragR = local_col(R, 'CD');

[aoaP, ip] = sort(aoaP); liftP = liftP(ip); dragP = dragP(ip);
[aoaR, ir] = sort(aoaR); liftR = liftR(ir); dragR = dragR(ir);

liftPScale = abs(interp1(aoaP, liftP, normalizeAoA, 'linear', 'extrap'));
liftRScale = abs(interp1(aoaR, liftR, normalizeAoA, 'linear', 'extrap'));
dragPScale = abs(interp1(aoaP, dragP, 0.0, 'linear', 'extrap'));
dragRScale = abs(interp1(aoaR, dragR, 0.0, 'linear', 'extrap'));

if liftPScale <= 0 || ~isfinite(liftPScale), liftPScale = max(abs(liftP)); end
if liftRScale <= 0 || ~isfinite(liftRScale), liftRScale = max(abs(liftR)); end
if dragPScale <= 0 || ~isfinite(dragPScale), dragPScale = max(abs(dragP)); end
if dragRScale <= 0 || ~isfinite(dragRScale), dragRScale = max(abs(dragR)); end

liftPN = liftP ./ liftPScale;
liftRN = liftR ./ liftRScale;
dragPN = dragP ./ dragPScale;
dragRN = dragR ./ dragRScale;

refLiftAtProxy = interp1(aoaR, liftRN, aoaP, 'linear', 'extrap');
refDragAtProxy = interp1(aoaR, dragRN, aoaP, 'linear', 'extrap');

C = table;
C.aoaDeg = aoaP(:);
C.proxyLiftNorm = liftPN(:);
C.referenceLiftNorm = refLiftAtProxy(:);
C.liftNormError = C.proxyLiftNorm - C.referenceLiftNorm;
C.proxyDragNorm = dragPN(:);
C.referenceDragNorm = refDragAtProxy(:);
C.dragNormError = C.proxyDragNorm - C.referenceDragNorm;
C.proxyLiftOverDragNorm = C.proxyLiftNorm ./ C.proxyDragNorm;
C.referenceLiftOverDragNorm = C.referenceLiftNorm ./ C.referenceDragNorm;

if local_has_col(P, 'ReEff')
    C.ReEff = local_col(P, 'ReEff');
end
if local_has_col(P, 'U0')
    C.U0 = local_col(P, 'U0');
end
if local_has_col(P, 'kBT')
    C.kBT = local_col(P, 'kBT');
end

outCsv = fullfile(outDir, [prefix '_comparison.csv']);
writetable(C, outCsv);

visibleState = local_visible(showFigures);

fig = figure('Visible', visibleState);
plot(aoaP, liftPN, '-o', 'LineWidth', 1.5); hold on;
plot(aoaR, liftRN, '--s', 'LineWidth', 1.5);
grid on; xlabel('AoA [deg]'); ylabel(sprintf('Lift normalized at %.0f deg', normalizeAoA));
title('NACA 0012: normalized lift shape');
legend('SRC-Darcy proxy', 'Reference CL', 'Location', 'best');
local_save(fig, outDir, [prefix '_lift_norm']);

fig = figure('Visible', visibleState);
plot(aoaP, dragPN, '-o', 'LineWidth', 1.5); hold on;
plot(aoaR, dragRN, '--s', 'LineWidth', 1.5);
grid on; xlabel('AoA [deg]'); ylabel('Drag normalized at 0 deg');
title('NACA 0012: normalized drag shape');
legend('SRC-Darcy proxy', 'Reference CD', 'Location', 'best');
local_save(fig, outDir, [prefix '_drag_norm']);

fig = figure('Visible', visibleState);
plot(dragPN, liftPN, '-o', 'LineWidth', 1.5); hold on;
plot(dragRN, liftRN, '--s', 'LineWidth', 1.5);
grid on; xlabel('Normalized drag'); ylabel('Normalized lift');
title('NACA 0012: normalized lift-vs-drag polar');
legend('SRC-Darcy proxy', 'Reference CL/CD shape', 'Location', 'best');
local_save(fig, outDir, [prefix '_lift_vs_drag_norm']);

fig = figure('Visible', visibleState);
plot(aoaP, C.proxyLiftOverDragNorm, '-o', 'LineWidth', 1.5); hold on;
plot(aoaP, C.referenceLiftOverDragNorm, '--s', 'LineWidth', 1.5);
grid on; xlabel('AoA [deg]'); ylabel('Normalized lift / normalized drag');
title('NACA 0012: normalized finesse shape');
legend('SRC-Darcy proxy', 'Reference', 'Location', 'best');
local_save(fig, outDir, [prefix '_finesse_norm']);

fprintf('[0354-matlab] proxyCsv=%s\n', proxyCsv);
fprintf('[0354-matlab] referenceCsv=%s\n', refCsv);
fprintf('[0354-matlab] wrote %s\n', outCsv);
end

function T = local_read_csv(path)
opts = detectImportOptions(path, 'Delimiter', ',');
try
    opts.VariableNamingRule = 'preserve';
catch
end
if any(strcmp(opts.VariableNames, 'naca'))
    try
        opts = setvartype(opts, 'naca', 'char');
    catch
    end
end
T = readtable(path, opts);
end

function tf = local_has_col(T, name)
tf = any(strcmp(T.Properties.VariableNames, name));
end

function v = local_col(T, name)
if ~local_has_col(T, name)
    error('Missing column %s. Available columns: %s', name, strjoin(T.Properties.VariableNames, ', '));
end
v = T.(name);
if iscell(v) || isstring(v) || iscategorical(v)
    v = str2double(string(v));
end
end

function s = local_visible(showFigures)
if showFigures
    s = 'on';
else
    s = 'off';
end
end

function local_save(fig, outDir, base)
png = fullfile(outDir, [base '.png']);
pdf = fullfile(outDir, [base '.pdf']);
saveas(fig, png);
saveas(fig, pdf);
fprintf('[0354-matlab] wrote %s\n', png);
fprintf('[0354-matlab] wrote %s\n', pdf);
end
