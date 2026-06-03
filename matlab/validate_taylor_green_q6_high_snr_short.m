function out = validate_taylor_green_q6_high_snr_short(varargin)
%VALIDATE_TAYLOR_GREEN_Q6_HIGH_SNR_SHORT Validate the short high-SNR TG pair.
%
%   out = validate_taylor_green_q6_high_snr_short()
%
%   This wrapper calls validate_taylor_green_q6_periodic on the default
%   high-SNR short classic and Q6 run directories.

p = inputParser;
p.FunctionName = 'validate_taylor_green_q6_high_snr_short';
addParameter(p, 'classicRunDir', '../runs/taylor_green_high_snr_classic_64x64_g80_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'q6RunDir', '../runs/taylor_green_high_snr_q6_64x64_g80_short', @(s) ischar(s) || isstring(s));
addParameter(p, 'makePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'plotFinalFields', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

out = validate_taylor_green_q6_periodic( ...
    char(string(opt.classicRunDir)), ...
    char(string(opt.q6RunDir)), ...
    'makePlots', logical(opt.makePlots), ...
    'plotFinalFields', logical(opt.plotFinalFields));

fprintf('\nHigh-SNR short TG validation notes:\n');
fprintf('  This case uses gamma=80, U0=0.08, kBT=0.01, tEnd=0.5.\n');
fprintf('  It is intended to keep the Taylor--Green mode measurable over the validation window.\n');
fprintf('  Runtime Q6 divergence remains the primary projection diagnostic.\n\n');
end
