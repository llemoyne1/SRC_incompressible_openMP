function T = plot_topo_naca_polar_proxy_0351(polarCsv, varargin)
%PLOT_TOPO_NACA_POLAR_PROXY_0351 Plot compact NACA polar-proxy CSV outputs.
%
% T = plot_topo_naca_polar_proxy_0351(polarCsv, 'OutputDir', outDir,
%                                     'ShowFigures', true/false,
%                                     'Prefix', prefix)
%
% Input:
%   polarCsv: CSV produced by analyze_topo_naca_polar_proxy_0350.py.
%
% Outputs:
%   Figures for lift proxy, drag proxy, lift/drag proxy and Darcy power.
%   A sorted copy of the input table is written next to the figures.

p = inputParser;
p.addRequired('polarCsv', @(x) ischar(x) || isstring(x));
p.addParameter('OutputDir', '', @(x) ischar(x) || isstring(x));
p.addParameter('ShowFigures', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('Prefix', 'naca_polar_proxy_0351', @(x) ischar(x) || isstring(x));
p.addParameter('SavePng', true, @(x) islogical(x) || isnumeric(x));
p.addParameter('SavePdf', true, @(x) islogical(x) || isnumeric(x));
p.parse(polarCsv, varargin{:});
opt = p.Results;

polarCsv = char(opt.polarCsv);
if ~isfile(polarCsv)
    error('plot_topo_naca_polar_proxy_0351:MissingFile', 'Missing polar CSV: %s', polarCsv);
end

T = local_read_polar_csv_0351(polarCsv);
T = local_sort_table_by_column(T, 'aoaDeg');

if strlength(string(opt.OutputDir)) == 0
    outDir = fullfile(fileparts(polarCsv), 'plots_0351');
else
    outDir = char(opt.OutputDir);
end
if ~exist(outDir, 'dir')
    mkdir(outDir);
end

prefix = char(opt.Prefix);
visibleMode = local_visible_mode(opt.ShowFigures);

sortedCsv = fullfile(outDir, [prefix '_sorted.csv']);
writetable(T, sortedCsv);

aoa = local_col(T, 'aoaDeg');

fig = figure('Name', 'NACA lift proxy vs AoA', 'Visible', visibleMode);
local_errorbar_or_plot(aoa, local_col(T, 'liftProxy_mean'), local_optional_col(T, 'liftProxy_std'), 'o-');
grid on;
xlabel('\alpha [deg]');
ylabel('liftProxy mean');
title('NACA lift proxy vs angle of attack');
local_save_figure(fig, outDir, [prefix '_lift_proxy'], opt.SavePng, opt.SavePdf);

fig = figure('Name', 'NACA drag proxy vs AoA', 'Visible', visibleMode);
local_errorbar_or_plot(aoa, local_col(T, 'dragProxy_mean'), local_optional_col(T, 'dragProxy_std'), 'o-');
grid on;
xlabel('\alpha [deg]');
ylabel('dragProxy mean');
title('NACA drag proxy vs angle of attack');
local_save_figure(fig, outDir, [prefix '_drag_proxy'], opt.SavePng, opt.SavePdf);

fig = figure('Name', 'NACA lift-over-drag proxy vs AoA', 'Visible', visibleMode);
plot(aoa, local_col(T, 'liftOverDragProxy'), 'o-', 'LineWidth', 1.2);
grid on;
xlabel('\alpha [deg]');
ylabel('liftOverDragProxy');
title('NACA lift/drag proxy vs angle of attack');
local_save_figure(fig, outDir, [prefix '_lift_over_drag_proxy'], opt.SavePng, opt.SavePdf);

if local_has_col(T, 'darcyPower_mean')
    fig = figure('Name', 'NACA Darcy power vs AoA', 'Visible', visibleMode);
    local_errorbar_or_plot(aoa, local_col(T, 'darcyPower_mean'), local_optional_col(T, 'darcyPower_std'), 'o-');
    grid on;
    xlabel('\alpha [deg]');
    ylabel('darcyPower mean');
    title('Darcy power proxy vs angle of attack');
    local_save_figure(fig, outDir, [prefix '_darcy_power'], opt.SavePng, opt.SavePdf);
end

fprintf('[0351-matlab] polarCsv=%s\n', polarCsv);
fprintf('[0351-matlab] outputDir=%s\n', outDir);
fprintf('[0351-matlab] sortedCsv=%s\n', sortedCsv);
end


function T = local_read_polar_csv_0351(path)
try
    opts = detectImportOptions(path, 'FileType', 'text', 'Delimiter', ',');
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
catch
    try
        T = readtable(path, 'FileType', 'text', 'Delimiter', ',', ...
                      'ReadVariableNames', true, 'VariableNamingRule', 'preserve');
    catch
        T = readtable(path, 'FileType', 'text', 'Delimiter', ',', ...
                      'ReadVariableNames', true);
    end
end
if any(strcmp(T.Properties.VariableNames, 'naca'))
    n = T.naca;
    if isnumeric(n)
        T.naca = string(compose('%04.0f', n));
    elseif iscell(n)
        T.naca = string(n);
    elseif iscategorical(n)
        T.naca = string(n);
    end
end
end


function visibleMode = local_visible_mode(showFigures)
if logical(showFigures)
    visibleMode = 'on';
else
    visibleMode = 'off';
end
end

function tf = local_has_col(T, name)
tf = any(strcmp(T.Properties.VariableNames, name));
end

function x = local_col(T, name)
if ~local_has_col(T, name)
    error('plot_topo_naca_polar_proxy_0351:MissingColumn', 'Missing column: %s', name);
end
x = T.(name);
end

function x = local_optional_col(T, name)
if local_has_col(T, name)
    x = T.(name);
else
    x = [];
end
end

function T = local_sort_table_by_column(T, name)
if local_has_col(T, name)
    [~, idx] = sort(T.(name));
    T = T(idx, :);
end
end

function local_errorbar_or_plot(x, y, e, spec)
if isempty(e)
    plot(x, y, spec, 'LineWidth', 1.2);
else
    errorbar(x, y, e, spec, 'LineWidth', 1.2);
end
end

function local_save_figure(fig, outDir, basename, savePng, savePdf)
if logical(savePng)
    png = fullfile(outDir, [basename '.png']);
    saveas(fig, png);
    fprintf('[0351-matlab] wrote %s\n', png);
end
if logical(savePdf)
    pdf = fullfile(outDir, [basename '.pdf']);
    set(fig, 'PaperPositionMode', 'auto');
    print(fig, pdf, '-dpdf', '-bestfit');
    fprintf('[0351-matlab] wrote %s\n', pdf);
end
end
