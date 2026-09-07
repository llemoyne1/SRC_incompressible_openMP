function analyze_0493x14at_sato_stageA_campaign(campaignRoot)
%ANALYZE_0493X14AT_SATO_STAGEA_CAMPAIGN  Visual audit of x14at results.
%
% By default, finds the newest ../runs/0493x14at_sato_stageA_seed* campaign.
% The Python analyzers remain responsible for reconstructing the reduced-grid
% interface and for the numerical fits.  This MATLAB companion only plots the
% auditable campaign CSVs produced in analysis_0493x14at/.

if nargin < 1 || strlength(string(campaignRoot)) == 0
    d = dir(fullfile('..','runs','0493x14at_sato_stageA_seed*'));
    d = d([d.isdir]);
    if isempty(d)
        error('No ../runs/0493x14at_sato_stageA_seed* campaign found.');
    end
    [~,i] = max([d.datenum]);
    campaignRoot = fullfile(d(i).folder,d(i).name);
end
campaignRoot = char(campaignRoot);
analysisDir = fullfile(campaignRoot,'analysis_0493x14at');
summaryPath = fullfile(analysisDir,'campaign_summary.csv');
fitsPath = fullfile(analysisDir,'campaign_fits.csv');
if ~isfile(summaryPath)
    error('Missing %s. Run scripts/analyze_0493x14at_sato_stageA_campaign.py first.',summaryPath);
end

T = readtable(summaryPath,'TextType','string');
Hvals = unique(T.targetHOverD);

f1 = figure('Name','x14at Sato Stage-A: cavity response');
hold on; grid on; box on;
for k = 1:numel(Hvals)
    I = T.targetHOverD == Hvals(k);
    [x,ord] = sort(T.meanMeasuredModifiedFroude(I));
    yy = T.meanDepthOverJetWidth(I); yy = yy(ord);
    ee = T.stdDepthOverJetWidth(I); ee = ee(ord);
    errorbar(x,yy,ee,'o-','DisplayName',sprintf('SRC 2-D, H/D=%.3g',Hvals(k)));
end
xmax = max([1.17; T.meanMeasuredModifiedFroude(isfinite(T.meanMeasuredModifiedFroude))]);
xx = linspace(0,xmax,200);
plot(xx,1.30*xx,'--','DisplayName','Sato stage A: h/D = 1.30 Fr_m''');
xline(1.17,':','Sato critical Fr_m''=1.17','HandleVisibility','off');
xlabel('Measured modified Froude number Fr_m''');
ylabel('Mean cavity depth h/D');
title('0493x14at — planar analogue of Sato stage A');
legend('Location','best');
exportgraphics(f1,fullfile(analysisDir,'sato_stageA_h_over_D_vs_measured_Fr.png'),'Resolution',180);

f2 = figure('Name','x14at gas-pressure covariate');
hold on; grid on; box on;
for k = 1:numel(Hvals)
    I = T.targetHOverD == Hvals(k);
    [x,ord] = sort(T.targetModifiedFroude(I));
    yy = T.meanGasPressureOffsetOverRhoGd(I); yy = yy(ord);
    plot(x,yy,'o-','DisplayName',sprintf('H/D=%.3g',Hvals(k)));
end
yline(0,':','HandleVisibility','off');
xlabel('Target modified Froude number Fr_m''');
ylabel('(p_G-p_{G,0})/(rho_L g D)');
title('Measured gas-pressure offset retained as a covariate');
legend('Location','best');
exportgraphics(f2,fullfile(analysisDir,'sato_stageA_gas_pressure_covariate.png'),'Resolution',180);

fprintf('\n0493x14at campaign: %s\n',campaignRoot);
fprintf('Summary: %s\n',summaryPath);
if isfile(fitsPath)
    F = readtable(fitsPath,'TextType','string');
    disp(F);
end
fprintf('Important: Sato slope 1.30 is a 3-D experimental reference, not a strict 2-D pass/fail value.\n');
end
