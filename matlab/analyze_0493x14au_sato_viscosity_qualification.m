function analyze_0493x14au_sato_viscosity_qualification()
% 0493x14au — consolidate the Taylor-Green viscosity qualifications used by
% the x14at Sato near-field gas/liquid campaign.
%
% Reads only ../runs/* as required by the SRC project convention.  The
% authoritative viscosity values are those written by the existing standalone
% 0493w1 calibrator; this script only consolidates the liquid/gas and wavelength
% comparisons and propagates them to the Sato campaign dimensionless numbers.

root = fullfile('..','runs','0493x14au_sato_viscosity');
out = fullfile(root,'analysis_0493x14au');
if ~exist(out,'dir'), mkdir(out); end

cases = struct(...
    'name', {'liquid_lambda64h','liquid_lambda21p333h','gas_lambda64h','gas_lambda21p333h'}, ...
    'phase',{'liquid','liquid','gas','gas'}, ...
    'wavelengthOverH',{64,64/3,64,64/3});

rows = struct([]);
for i = 1:numel(cases)
    p = fullfile(root,cases(i).name,'analysis','fluid_characterization.json');
    if ~exist(p,'file')
        error('0493x14au:missingResult','Missing %s',p);
    end
    s = jsondecode(fileread(p));
    r = struct();
    r.caseName = cases(i).name;
    r.phase = cases(i).phase;
    r.path = char(s.path);
    r.wavelengthOverH = cases(i).wavelengthOverH;
    r.wavelengthOverD = cases(i).wavelengthOverH/20;
    r.status = char(s.status);
    r.viscosityStatus = char(s.viscosityStatus);
    r.nu = numeric_or_nan(s,'viscosityKinematic');
    r.nuStd = numeric_or_nan(s,'viscosityStd');
    r.nuCV = numeric_or_nan(s,'viscosityCV');
    r.gamma = s.gamma;
    r.dt = s.dt;
    r.kBT = s.kBT;
    r.mass = s.particleMass;
    r.cellSize = s.cellSize;
    r.lambdaMeanOverH = s.lambdaMeanOverCell;
    rows = [rows; r]; %#ok<AGROW>
end

T = struct2table(rows);
writetable(T,fullfile(out,'viscosity_cases.csv'));

L0 = rows(1); La = rows(2); G0 = rows(3); Ga = rows(4);
liq = scale_comparison(L0,La);
gas = scale_comparison(G0,Ga);

C = table(...
    string({'liquid';'gas'}), ...
    [L0.nu;G0.nu], [L0.nuStd;G0.nuStd], [L0.nuCV;G0.nuCV], ...
    [La.nu;Ga.nu], [La.nuStd;Ga.nuStd], [La.nuCV;Ga.nuCV], ...
    [liq.relDiff;gas.relDiff], [liq.z;gas.z], ...
    string({liq.scaleStatus;gas.scaleStatus}), ...
    'VariableNames',{'phase','nuPrimary','nuPrimaryStd','nuPrimaryCV', ...
    'nuApplicationScale','nuApplicationScaleStd','nuApplicationScaleCV', ...
    'relativeScaleDifference','scaleDifferenceZ','scaleConsistency'});
writetable(C,fullfile(out,'viscosity_scale_comparison.csv'));

% x14at/Sato campaign defaults, copied only for propagation of the calibrated
% nu values.  The runner remains the authority for the actual executed case.
h = 1/256;
gamma = 20;
mL = 1.0; mG = 0.1;
rhoL = gamma*mL/h^2;
rhoG = gamma*mG/h^2;
D = 20*h;
gabs = 0.5;
sigma = 294.461365748622;
Fr = [0.20; 0.40; 0.660364520158346; 0.90];
c = (pi/4)^2;
U = sqrt(Fr .* (rhoL/rhoG) .* gabs .* D ./ c);

nuL = L0.nu;
nuG = G0.nu;
ReL = U*D/nuL;
ReG = U*D/nuG;
muL = rhoL*nuL;
muG = rhoG*nuG;
WeG = rhoG.*U.^2.*D/sigma;
Bo = (rhoL-rhoG)*gabs*D^2/sigma;
OhL = nuL*sqrt(rhoL/(sigma*D));
CaL = muL.*U/sigma;

Dtab = table(Fr,U,ReL,ReG,WeG,repmat(Bo,numel(Fr),1), ...
    repmat(OhL,numel(Fr),1),CaL, ...
    'VariableNames',{'FrModifiedTarget','UJetNominal','ReLiquid','ReGas', ...
    'WeGas','BoDensityDifference','OhLiquid','CaLiquid'});
writetable(Dtab,fullfile(out,'sato_stageA_dimensionless_with_calibrated_nu.csv'));

% Separate figures by phase.
make_plot(L0,La,'Liquid Q6-G-F',fullfile(out,'viscosity_scale_liquid.png'));
make_plot(G0,Ga,'Gas SRC',fullfile(out,'viscosity_scale_gas.png'));

report = fullfile(out,'viscosity_qualification_report.txt');
fid = fopen(report,'w');
if fid < 0, error('Cannot create %s',report); end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'0493x14au Sato viscosity qualification\n');
fprintf(fid,'====================================\n\n');
fprintf(fid,'Primary metrology: existing 0493w1 standalone Taylor-Green ensemble.\n');
fprintf(fid,'Primary wavelength = 64 h; application check = 64/3 h = %.6f h = %.6f D.\n\n',64/3,(64/3)/20);
print_phase(fid,'LIQUID',L0,La,liq);
print_phase(fid,'GAS',G0,Ga,gas);
fprintf(fid,'Dynamic viscosity ratio mu_G/mu_L (primary nu) = %.10g\n',muG/muL);
fprintf(fid,'Kinematic viscosity ratio nu_G/nu_L = %.10g\n',nuG/nuL);
fprintf(fid,'rho_G/rho_L = %.10g\n\n',rhoG/rhoL);
fprintf(fid,'Sato campaign propagation uses D=20h, |g|=0.5 and sigma=%.15g.\n',sigma);
fprintf(fid,'The 3-D experimental coefficient is not used as a viscosity acceptance criterion.\n');
fprintf(fid,'Scale consistency is diagnostic: CONSISTENT_2SIGMA means |nu_app-nu_primary| <= 2*sqrt(sd_primary^2+sd_app^2).\n');

fprintf('===== 0493x14au VISCOSITY QUALIFICATION =====\n');
fprintf('liquid nu=%.10g std=%.4g CV=%.3f%% scaleDelta=%+.3f%% %s\n', ...
    L0.nu,L0.nuStd,100*L0.nuCV,100*liq.relDiff,liq.scaleStatus);
fprintf('gas    nu=%.10g std=%.4g CV=%.3f%% scaleDelta=%+.3f%% %s\n', ...
    G0.nu,G0.nuStd,100*G0.nuCV,100*gas.relDiff,gas.scaleStatus);
fprintf('muG/muL=%.10g nuG/nuL=%.10g\n',muG/muL,nuG/nuL);
fprintf('results=%s\n',out);
end

function x = numeric_or_nan(s,name)
if isfield(s,name) && ~isempty(s.(name))
    x = double(s.(name));
else
    x = NaN;
end
end

function q = scale_comparison(a,b)
q = struct();
q.relDiff = (b.nu-a.nu)/a.nu;
sig = hypot(a.nuStd,b.nuStd);
if isfinite(sig) && sig > 0
    q.z = abs(b.nu-a.nu)/sig;
    if q.z <= 2
        q.scaleStatus = 'CONSISTENT_2SIGMA';
    else
        q.scaleStatus = 'SCALE_DEPENDENCE_REVIEW';
    end
else
    q.z = NaN;
    q.scaleStatus = 'UNCERTAINTY_UNRESOLVED';
end
end

function print_phase(fid,label,a,b,q)
fprintf(fid,'%s\n',label);
fprintf(fid,'  primary path=%s status=%s viscosityStatus=%s\n',a.path,a.status,a.viscosityStatus);
fprintf(fid,'  nu(64h)=%.12g  std=%.6g  CV=%.4f%%\n',a.nu,a.nuStd,100*a.nuCV);
fprintf(fid,'  app-scale status=%s viscosityStatus=%s\n',b.status,b.viscosityStatus);
fprintf(fid,'  nu(64/3h)=%.12g  std=%.6g  CV=%.4f%%\n',b.nu,b.nuStd,100*b.nuCV);
fprintf(fid,'  delta_app/primary=%+.5f%%  z=%.5g  scale=%s\n\n',100*q.relDiff,q.z,q.scaleStatus);
end

function make_plot(a,b,label,outfile)
f = figure('Visible','off');
x = [a.wavelengthOverH b.wavelengthOverH];
y = [a.nu b.nu];
e = [a.nuStd b.nuStd];
errorbar(x,y,e,'o-','LineWidth',1.2,'MarkerSize',6);
xlabel('Taylor-Green wavelength / h');
ylabel('Kinematic viscosity \nu');
title(['0493x14au - ' label]);
grid on;
set(gca,'XDir','reverse');
exportgraphics(f,outfile,'Resolution',160);
close(f);
end
