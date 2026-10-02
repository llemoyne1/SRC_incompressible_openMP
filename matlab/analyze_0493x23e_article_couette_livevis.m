function summary = analyze_0493x23e_article_couette_livevis(runRoot, muRatio)
%ANALYZE_0493X23E_ARTICLE_COUETTE_LIVEVIS
% Conservative high-cadence analysis of the x14w two-phase Couette benchmark.
%
% The recorder stores rho and ux separately as float32.  With smoothPasses=0
% and filterMode=none, rho.*ux reconstructs the cell x-momentum up to the
% recorder float32 quantization.  The metrology therefore accumulates
%
%     ubar_x(y) = sum_{t,x} rho(x,y,t) ux(x,y,t) /
%                 sum_{t,x} rho(x,y,t)
%
% before antisymmetric folding and linear fits.
%
% Default usage from SRC_GPU-SURF/matlab:
%   analyze_0493x23e_article_couette_livevis
%
% Optional:
%   analyze_0493x23e_article_couette_livevis('../runs/...', 0.11843095)
%
% This analysis never modifies solver data.

if nargin < 1 || isempty(runRoot)
    runRoot = fullfile('..','runs','0493x23e_article_couette_livevis_Uw0075_seed593170');
end
if nargin < 2 || isempty(muRatio)
    muRatio = 0.11843095;
end

% Independent 64h Taylor--Green calibration means at the exact x14w point.
% Gas: PASS (src); liquid: REVIEW (src-q6-g-f).  These are used only to
% convert the measured Couette bulk density ratio into a dynamic-viscosity
% ratio; they are not fit to the Couette profile.
nuLiquidRef = 0.0006158804790631908;
nuGasRef = 0.0007293930958167586;
nuRatioRef = nuGasRef/nuLiquidRef;

lateStart = 6000;
lateEnd   = 18000;
blockWidth = 2000;
interfaceExcludeCells = 4;
wallExcludeCells = 4;

runRoot = char(runRoot);
outDir = fullfile(runRoot,'analysis_livevis');
if ~exist(outDir,'dir')
    mkdir(outDir);
end

paramsFile = fullfile(runRoot,'params','0493x23e_article_couette_livevis.kv');
if ~isfile(paramsFile)
    error('x23e:missingParams','Missing authoritative params file: %s',paramsFile);
end
P = read_kv_file(paramsFile);

% Authoritative run-point checks.  Fail rather than silently analysing a
% different physical experiment under the article label.
assert_close(kvnum(P,'Lx'),0.5,1e-12,'Lx');
assert_close(kvnum(P,'Ly'),0.5,1e-12,'Ly');
assert_close(kvnum(P,'Nx'),128,0,'Nx');
assert_close(kvnum(P,'Ny'),128,0,'Ny');
assert_close(kvnum(P,'dt'),0.002,1e-15,'dt');
assert_close(kvnum(P,'wallUxBottom'),-0.075,1e-12,'wallUxBottom');
assert_close(kvnum(P,'wallUxTop'),0.075,1e-12,'wallUxTop');

Lx = kvnum(P,'Lx');
Ly = kvnum(P,'Ly');
nx = round(kvnum(P,'Nx'));
ny = round(kvnum(P,'Ny'));
Uw = kvnum(P,'wallUxTop');
h = Ly/ny;
zInterface = 32*h;
zWall = 0.5*Ly;

recRoot = fullfile(runRoot,'output','recordings');
if ~isfolder(recRoot)
    error('x23e:noRecordings','Missing recordings directory: %s',recRoot);
end
D = dir(recRoot);
D = D([D.isdir]);
D = D(~ismember({D.name},{'.','..'}));

matches = {};
for k = 1:numel(D)
    sd = fullfile(recRoot,D(k).name);
    mf = fullfile(sd,'manifest.kv');
    tf = fullfile(sd,'timeline.csv');
    if isfile(mf) && isfile(tf)
        M = read_kv_file(mf);
        fields = string(kvstr(M,'recordFields'));
        if contains(fields,"rho") && contains(fields,"ux") && contains(fields,"uy")
            matches{end+1} = sd; %#ok<AGROW>
        end
    end
end
if isempty(matches)
    error('x23e:noMatchingSession','No recorder session with rho,ux,uy found under %s',recRoot);
end
if numel(matches) ~= 1
    error('x23e:ambiguousSession','Expected one rho/ux/uy recording session, found %d.',numel(matches));
end
sessionDir = matches{1};
manifestFile = fullfile(sessionDir,'manifest.kv');
timelineFile = fullfile(sessionDir,'timeline.csv');
M = read_kv_file(manifestFile);

% Recorder contract: these are metrology requirements, not tunable fit choices.
assert_close(kvnum(M,'liveGridNx'),128,0,'manifest liveGridNx');
assert_close(kvnum(M,'liveGridNy'),128,0,'manifest liveGridNy');
assert_close(kvnum(M,'recordEvery'),20,0,'manifest recordEvery');
assert_close(kvnum(M,'smoothPasses'),0,0,'manifest smoothPasses');
if ~strcmpi(strtrim(kvstr(M,'filterMode')),'none')
    error('x23e:filterMode','Expected filterMode=none, got %s',kvstr(M,'filterMode'));
end
if ~strcmpi(strtrim(kvstr(M,'recordFormat')),'f32')
    error('x23e:recordFormat','Expected recordFormat=f32, got %s',kvstr(M,'recordFormat'));
end

T = readtable(timelineFile,'VariableNamingRule','preserve');
required = {'step','field','file','nx','ny'};
for k=1:numel(required)
    if ~ismember(required{k},T.Properties.VariableNames)
        error('x23e:timeline','timeline.csv missing column %s',required{k});
    end
end
stepsAll = unique(double(T.step));
steps = stepsAll(stepsAll >= lateStart & stepsAll <= lateEnd);
if isempty(steps)
    error('x23e:noLateFrames','No frames in requested late window [%d,%d].',lateStart,lateEnd);
end

nBlocks = ceil((lateEnd-lateStart)/blockWidth);
massY = zeros(1,ny);
pxY = zeros(1,ny);
pyY = zeros(1,ny);
massBlock = zeros(nBlocks,ny);
pxBlock = zeros(nBlocks,ny);
pyBlock = zeros(nBlocks,ny);
frameCountBlock = zeros(nBlocks,1);

fields = string(T.field);
files = string(T.file);
tsteps = double(T.step);

for kk = 1:numel(steps)
    st = steps(kk);
    ir = find(tsteps==st & fields=="rho",1);
    ix = find(tsteps==st & fields=="ux",1);
    iy = find(tsteps==st & fields=="uy",1);
    if isempty(ir) || isempty(ix) || isempty(iy)
        error('x23e:incompleteFrame','Step %d lacks rho/ux/uy.',st);
    end
    rho = read_f32_grid(fullfile(sessionDir,char(files(ir))),nx,ny);
    ux  = read_f32_grid(fullfile(sessionDir,char(files(ix))),nx,ny);
    uy  = read_f32_grid(fullfile(sessionDir,char(files(iy))),nx,ny);

    if any(~isfinite(rho(:))) || any(~isfinite(ux(:))) || any(~isfinite(uy(:)))
        error('x23e:nonfinite','Non-finite recorder value at step %d.',st);
    end
    if any(rho(:)<0)
        error('x23e:negativeMass','Negative rho/mass recorder value at step %d.',st);
    end

    my  = sum(rho,1);
    pxy = sum(rho.*ux,1);
    pyy = sum(rho.*uy,1);
    massY = massY + my;
    pxY = pxY + pxy;
    pyY = pyY + pyy;

    b = floor((st-lateStart)/blockWidth)+1;
    b = min(max(b,1),nBlocks);
    massBlock(b,:) = massBlock(b,:) + my;
    pxBlock(b,:) = pxBlock(b,:) + pxy;
    pyBlock(b,:) = pyBlock(b,:) + pyy;
    frameCountBlock(b) = frameCountBlock(b)+1;
end

if any(massY<=0)
    error('x23e:emptyRow','At least one y row has zero accumulated mass.');
end
uxY = pxY./massY;
uyY = pyY./massY;

[profile,fit] = folded_fit(pxY,pyY,massY,h,zInterface,zWall, ...
                           interfaceExcludeCells,wallExcludeCells,Uw);
fit.muGasOverMuLiquidReference = muRatio;
fit.Rtau = fit.slopeRatio/muRatio;
fit.frames = numel(steps);
fit.firstStep = min(steps);
fit.lastStep = max(steps);

% Bulk density metrology from the same conservative recorder and the exact
% same fixed liquid/gas windows used for the Couette slope fits. massFold
% is the accumulated top/bottom mean of sum_x rho; dividing by nx*nFrames
% restores the mean recorded rho per cell.  The ratio is independent of
% this normalization.
profile.rhoFold = profile.massFold/(nx*numel(steps));
rhoLiquidBulk = mean(profile.rhoFold(profile.liquidMask));
rhoGasBulk = mean(profile.rhoFold(profile.gasMask));
rhoRatioBulk = rhoGasBulk/rhoLiquidBulk;
muRatioFromMeasuredRho = rhoRatioBulk*nuRatioRef;
RtauFromMeasuredRho = fit.slopeRatio/muRatioFromMeasuredRho;
rhoRatioRequiredBySlopes = fit.slopeRatio/nuRatioRef;

fit.rhoLiquidBulk = rhoLiquidBulk;
fit.rhoGasBulk = rhoGasBulk;
fit.rhoGasOverRhoLiquid = rhoRatioBulk;
fit.nuGasOverNuLiquidReference = nuRatioRef;
fit.muGasOverMuLiquidFromMeasuredRho = muRatioFromMeasuredRho;
fit.RtauFromMeasuredRho = RtauFromMeasuredRho;
fit.rhoGasOverRhoLiquidRequiredBySlopes = rhoRatioRequiredBySlopes;

blocksCell = cell(nBlocks,1);
for b=1:nBlocks
    if frameCountBlock(b)==0 || any(massBlock(b,:)<=0)
        error('x23e:block','Block %d has insufficient recorder data.',b);
    end
    uxB = pxBlock(b,:)./massBlock(b,:);
    uyB = pyBlock(b,:)./massBlock(b,:);
    [profileB,fb] = folded_fit(pxBlock(b,:),pyBlock(b,:),massBlock(b,:),h,zInterface,zWall, ...
                        interfaceExcludeCells,wallExcludeCells,Uw);
    rhoFoldB = profileB.massFold/(nx*frameCountBlock(b));
    fb.rhoLiquidBulk = mean(rhoFoldB(profileB.liquidMask));
    fb.rhoGasBulk = mean(rhoFoldB(profileB.gasMask));
    fb.rhoGasOverRhoLiquid = fb.rhoGasBulk/fb.rhoLiquidBulk;
    fb.muGasOverMuLiquidFromMeasuredRho = fb.rhoGasOverRhoLiquid*nuRatioRef;
    fb.RtauFromMeasuredRho = fb.slopeRatio/fb.muGasOverMuLiquidFromMeasuredRho;
    fb.block = b;
    fb.stepStart = lateStart+(b-1)*blockWidth;
    fb.stepEnd = min(lateEnd,lateStart+b*blockWidth);
    fb.frames = frameCountBlock(b);
    fb.Rtau = fb.slopeRatio/muRatio;
    blocksCell{b}=fb;
end
blocks = vertcat(blocksCell{:});

ratios = [blocks.slopeRatio];
Rtaus = [blocks.Rtau];
aLs = [blocks.liquidSlope];
aGs = [blocks.gasSlope];
rhoLs = [blocks.rhoLiquidBulk];
rhoGs = [blocks.rhoGasBulk];
rhoRatios = [blocks.rhoGasOverRhoLiquid];
muRatiosRho = [blocks.muGasOverMuLiquidFromMeasuredRho];
RtausRho = [blocks.RtauFromMeasuredRho];
nEff = numel(ratios);
ratioMean = mean(ratios);
ratioStd = std(ratios,0);
ratioSEM = ratioStd/sqrt(nEff);
t975_df5 = 2.57058183661474; % nBlocks=6 -> df=5
ratioCI95 = ratioMean + [-1 1]*t975_df5*ratioSEM;

% Ideal continuum reference using the independently calibrated viscosity ratio.
aGref = Uw / ((zWall-zInterface) + muRatio*zInterface);
aLref = muRatio*aGref;
uIref = aLref*zInterface;

% Profile table.
profileTable = table(profile.z(:),profile.zOverH(:),profile.uOdd(:), ...
    profile.uEven(:),profile.uyOdd(:),profile.uyEven(:),profile.massFold(:),profile.rhoFold(:), ...
    'VariableNames',{'z','zOverH','uOdd','uEven','uyOdd','uyEven','massFold','rhoFold'});
writetable(profileTable,fullfile(outDir,'couette_livevis_profile_0493x23e.csv'));

% Block table.
blockTable = table((1:nBlocks)', ...
    [blocks.stepStart]',[blocks.stepEnd]',[blocks.frames]', ...
    aLs',aGs',ratios',Rtaus',rhoLs',rhoGs',rhoRatios',muRatiosRho',RtausRho', ...
    [blocks.liquidR2]',[blocks.gasR2]', ...
    [blocks.interfaceSlipOverUw]',[blocks.gasWallSlipOverUw]', ...
    'VariableNames',{'block','stepStart','stepEnd','frames','aL','aG', ...
    'aL_over_aG','Rtau_nominalRho','rhoL','rhoG','rhoG_over_rhoL', ...
    'muG_over_muL_measuredRho','Rtau_measuredRho','R2L','R2G', ...
    'interfaceSlipOverUw','gasWallSlipOverUw'});
writetable(blockTable,fullfile(outDir,'couette_livevis_blocks_0493x23e.csv'));

summary = struct();
summary.status = 'MEASUREMENT';
summary.runRoot = runRoot;
summary.sessionDir = sessionDir;
summary.paramsFile = paramsFile;
summary.manifestFile = manifestFile;
summary.timelineFile = timelineFile;
summary.measurement = struct( ...
    'definition','sum_t,x(rho*ux)/sum_t,x(rho), then antisymmetric fold and fixed-window fits', ...
    'lateStartStep',lateStart,'lateEndStep',lateEnd,'frames',numel(steps), ...
    'smoothPasses',0,'filterMode','none','recordEvery',20);
summary.geometry = struct('Lx',Lx,'Ly',Ly,'Nx',nx,'Ny',ny,'h',h, ...
    'zInterfaceNominal',zInterface,'zWall',zWall, ...
    'interfaceExcludeCells',interfaceExcludeCells,'wallExcludeCells',wallExcludeCells);
summary.reference = struct('muGasOverMuLiquid',muRatio, ...
    'nuLiquid64h',nuLiquidRef,'nuGas64h',nuGasRef,'nuGasOverNuLiquid',nuRatioRef, ...
    'idealLiquidSlope',aLref,'idealGasSlope',aGref,'idealInterfaceVelocity',uIref);
summary.densityCheck = struct( ...
    'definition','mean recorded rho in the exact fixed bulk slope-fit windows', ...
    'rhoLiquidBulk',rhoLiquidBulk,'rhoGasBulk',rhoGasBulk, ...
    'rhoGasOverRhoLiquid',rhoRatioBulk, ...
    'muGasOverMuLiquidFromMeasuredRho',muRatioFromMeasuredRho, ...
    'RtauFromMeasuredRho',RtauFromMeasuredRho, ...
    'rhoGasOverRhoLiquidRequiredBySlopes',rhoRatioRequiredBySlopes);
summary.fit = fit;
summary.blockStatistics = struct( ...
    'nBlocks',nEff,'blockWidthSteps',blockWidth, ...
    'slopeRatioMean',ratioMean,'slopeRatioStd',ratioStd, ...
    'slopeRatioSEM',ratioSEM,'slopeRatioStudent95',ratioCI95, ...
    'RtauMean',mean(Rtaus),'RtauStd',std(Rtaus,0), ...
    'liquidSlopeMean',mean(aLs),'liquidSlopeStd',std(aLs,0), ...
    'gasSlopeMean',mean(aGs),'gasSlopeStd',std(aGs,0), ...
    'rhoRatioMean',mean(rhoRatios),'rhoRatioStd',std(rhoRatios,0), ...
    'muRatioMeasuredRhoMean',mean(muRatiosRho),'muRatioMeasuredRhoStd',std(muRatiosRho,0), ...
    'RtauMeasuredRhoMean',mean(RtausRho),'RtauMeasuredRhoStd',std(RtausRho,0));

jsonText = jsonencode(summary,'PrettyPrint',true);
fid=fopen(fullfile(outDir,'couette_livevis_summary_0493x23e.json'),'w');
if fid<0, error('x23e:write','Cannot write JSON summary.'); end
fprintf(fid,'%s\n',jsonText);
fclose(fid);

fid=fopen(fullfile(outDir,'couette_livevis_summary_0493x23e.txt'),'w');
if fid<0, error('x23e:write','Cannot write text summary.'); end
fprintf(fid,'0493x23e Couette LiveVis conservative metrology\n');
fprintf(fid,'runRoot = %s\n',runRoot);
fprintf(fid,'frames = %d, step window = [%d,%d]\n',numel(steps),lateStart,lateEnd);
fprintf(fid,'muG/muL reference = %.9g\n',muRatio);
fprintf(fid,'aL = %.10g, R2L = %.8f\n',fit.liquidSlope,fit.liquidR2);
fprintf(fid,'aG = %.10g, R2G = %.8f\n',fit.gasSlope,fit.gasR2);
fprintf(fid,'aL/aG = %.10g\n',fit.slopeRatio);
fprintf(fid,'R_tau (nominal rho ratio through mu reference) = %.10g\n',fit.Rtau);
fprintf(fid,'nuG/nuL 64h reference = %.10g\n',nuRatioRef);
fprintf(fid,'rhoL bulk = %.10g\n',rhoLiquidBulk);
fprintf(fid,'rhoG bulk = %.10g\n',rhoGasBulk);
fprintf(fid,'rhoG/rhoL bulk = %.10g\n',rhoRatioBulk);
fprintf(fid,'muG/muL from measured rho and 64h nu ratio = %.10g\n',muRatioFromMeasuredRho);
fprintf(fid,'R_tau from measured rho = %.10g\n',RtauFromMeasuredRho);
fprintf(fid,'rhoG/rhoL required by measured slopes = %.10g\n',rhoRatioRequiredBySlopes);
fprintf(fid,'interface slip/Uw = %+.8g\n',fit.interfaceSlipOverUw);
fprintf(fid,'gas wall slip/Uw = %+.8g\n',fit.gasWallSlipOverUw);
fprintf(fid,'common-mode RMS/Uw = %.8g\n',fit.commonModeRmsOverUw);
fprintf(fid,'uy RMS/Uw = %.8g\n',fit.uyRmsOverUw);
fprintf(fid,'block slope-ratio mean = %.10g\n',ratioMean);
fprintf(fid,'block slope-ratio SD = %.10g\n',ratioStd);
fprintf(fid,'block slope-ratio SEM = %.10g\n',ratioSEM);
fprintf(fid,'block slope-ratio Student95 = [%.10g, %.10g]\n',ratioCI95(1),ratioCI95(2));
fprintf(fid,'block rhoG/rhoL mean = %.10g, SD = %.10g\n',mean(rhoRatios),std(rhoRatios,0));
fprintf(fid,'block muG/muL measured-rho mean = %.10g, SD = %.10g\n',mean(muRatiosRho),std(muRatiosRho,0));
fprintf(fid,'block R_tau measured-rho mean = %.10g, SD = %.10g\n',mean(RtausRho),std(RtausRho,0));
fclose(fid);

% Article-oriented diagnostic figure: full conservative profile + time blocks.
fig = figure('Color','w','Position',[100 100 760 720]);
tl = tiledlayout(fig,2,1,'TileSpacing','compact','Padding','compact');

ax1=nexttile(tl,1);
plot(ax1,profile.zOverH,profile.uOdd./Uw,'o','MarkerSize',4,'DisplayName','LiveVis conservative mean');
hold(ax1,'on');
zq=linspace(0,zWall,500);
uRef=zeros(size(zq));
liq=zq<=zInterface;
uRef(liq)=aLref*zq(liq);
uRef(~liq)=uIref+aGref*(zq(~liq)-zInterface);
plot(ax1,zq/h,uRef./Uw,'--','LineWidth',1.4,'DisplayName','continuum reference, \mu_G/\mu_L');
zl=linspace(min(profile.z(profile.liquidMask)),max(profile.z(profile.liquidMask)),100);
zg=linspace(min(profile.z(profile.gasMask)),max(profile.z(profile.gasMask)),100);
plot(ax1,zl/h,(fit.liquidSlope*zl+fit.liquidIntercept)./Uw,'-','LineWidth',1.5,'DisplayName','liquid fit');
plot(ax1,zg/h,(fit.gasSlope*zg+fit.gasIntercept)./Uw,'-','LineWidth',1.5,'DisplayName','gas fit');
xline(ax1,zInterface/h,':','interface');
xlabel(ax1,'z/h');
ylabel(ax1,'u_a/U_w');
grid(ax1,'on');
legend(ax1,'Location','northwest');
title(ax1,sprintf('Couette x23e: a_L/a_G=%.4f, R_\\tau=%.3f',fit.slopeRatio,fit.Rtau));

ax2=nexttile(tl,2);
plot(ax2,1:nBlocks,ratios,'o-','LineWidth',1.1);
hold(ax2,'on');
yline(ax2,muRatio,'--','\mu_G/\mu_L');
xlabel(ax2,'2000-step block');
ylabel(ax2,'a_L/a_G');
grid(ax2,'on');
title(ax2,sprintf('temporal blocks: mean %.4f, SD %.4f',ratioMean,ratioStd));

exportgraphics(fig,fullfile(outDir,'couette_livevis_0493x23e.png'),'Resolution',220);
exportgraphics(fig,fullfile(outDir,'couette_livevis_0493x23e.pdf'),'ContentType','vector');

% Density diagnostic from the same fixed windows.  This is intentionally a
% separate figure so the original Couette profile figure remains unchanged.
figRho = figure('Color','w','Position',[140 140 760 520]);
plot(profile.zOverH,profile.rhoFold,'o-','MarkerSize',4);
hold on;
xline(zInterface/h,':','interface');
yline(rhoLiquidBulk,'--','rho_L bulk');
yline(rhoGasBulk,'--','rho_G bulk');
xlabel('z/h');
ylabel('recorded \rho (bulk mean per cell)');
grid on;
title(sprintf('Couette x23e density: rho_G/rho_L=%.4f, mu_G/mu_L=%.4f', ...
    rhoRatioBulk,muRatioFromMeasuredRho));
exportgraphics(figRho,fullfile(outDir,'couette_livevis_density_0493x23e.png'),'Resolution',220);
exportgraphics(figRho,fullfile(outDir,'couette_livevis_density_0493x23e.pdf'),'ContentType','vector');

fprintf('\n[0493x23e-livevis] conservative profile: %d frames, steps %d..%d\n',numel(steps),min(steps),max(steps));
fprintf('[0493x23e-livevis] aL=%+.8g R2L=%.6f\n',fit.liquidSlope,fit.liquidR2);
fprintf('[0493x23e-livevis] aG=%+.8g R2G=%.6f\n',fit.gasSlope,fit.gasR2);
fprintf('[0493x23e-livevis] aL/aG=%.8g  muG/muL(nominal-rho ref)=%.8g  Rtau=%.8g\n',fit.slopeRatio,muRatio,fit.Rtau);
fprintf('[0493x23e-livevis] rhoL=%.8g rhoG=%.8g rhoG/rhoL=%.8g\n',rhoLiquidBulk,rhoGasBulk,rhoRatioBulk);
fprintf('[0493x23e-livevis] nuG/nuL=%.8g -> muG/muL(measured rho)=%.8g -> Rtau=%.8g\n', ...
    nuRatioRef,muRatioFromMeasuredRho,RtauFromMeasuredRho);
fprintf('[0493x23e-livevis] rhoG/rhoL required by slopes=%.8g\n',rhoRatioRequiredBySlopes);
fprintf('[0493x23e-livevis] block rhoG/rhoL mean=%.8g SD=%.8g; measured-rho Rtau mean=%.8g SD=%.8g\n', ...
    mean(rhoRatios),std(rhoRatios,0),mean(RtausRho),std(RtausRho,0));
fprintf('[0493x23e-livevis] block mean ratio=%.8g SD=%.8g SEM=%.8g 95%%=[%.8g, %.8g]\n', ...
    ratioMean,ratioStd,ratioSEM,ratioCI95(1),ratioCI95(2));
fprintf('[0493x23e-livevis] interface slip/Uw=%+.5f, wall slip/Uw=%+.5f, common RMS/Uw=%.5g, uy RMS/Uw=%.5g\n', ...
    fit.interfaceSlipOverUw,fit.gasWallSlipOverUw,fit.commonModeRmsOverUw,fit.uyRmsOverUw);
fprintf('[0493x23e-livevis] outputs: %s\n',outDir);

end

function A = read_f32_grid(path,nx,ny)
fid=fopen(path,'rb');
if fid<0, error('x23e:read','Cannot open %s',path); end
c=onCleanup(@() fclose(fid));
v=fread(fid,nx*ny,'single=>double');
if numel(v)~=nx*ny
    error('x23e:truncated','Expected %d float32 values in %s, got %d.',nx*ny,path,numel(v));
end
% Recorder layout is row-major c = iy*nx + ix.  MATLAB reshape(nx,ny)
% therefore yields A(ix,iy), making sum(A,1) the x integral.
A=reshape(v,[nx,ny]);
end

function [profile,fit] = folded_fit(pxY,pyY,massY,h,zInterface,zWall,interfaceExcludeCells,wallExcludeCells,Uw)
ny=numel(massY);
if mod(ny,2)~=0, error('x23e:ny','Even ny required.'); end
nh=ny/2;
topPx=pxY(nh+1:ny);
botPx=pxY(nh:-1:1);
topPy=pyY(nh+1:ny);
botPy=pyY(nh:-1:1);
topM=massY(nh+1:ny);
botM=massY(nh:-1:1);
foldM=topM+botM;
if any(foldM<=0), error('x23e:foldMass','Zero folded mass.'); end

z=((0:nh-1)+0.5)*h;
% Conservative symmetry projection: sign-flip the bottom momentum, then combine
% momenta and masses before reconstructing velocity.  This retains the same
% barycentric estimator through the antisymmetric fold.
uOdd=(topPx-botPx)./foldM;
uEven=(topPx+botPx)./foldM;
uyOdd=(topPy-botPy)./foldM;
uyEven=(topPy+botPy)./foldM;
massFold=0.5*foldM;
uyY=pyY./massY;

zLmax=zInterface-interfaceExcludeCells*h;
zGmin=zInterface+interfaceExcludeCells*h;
zGmax=zWall-wallExcludeCells*h;
liquidMask=(z>0 & z<=zLmax);
gasMask=(z>=zGmin & z<=zGmax);

[aL,bL,r2L,rmsL]=ols_fit(z(liquidMask),uOdd(liquidMask));
[aG,bG,r2G,rmsG]=ols_fit(z(gasMask),uOdd(gasMask));
ratio=aL/aG;
uLi=aL*zInterface+bL;
uGi=aG*zInterface+bG;
uGw=aG*zWall+bG;

fit=struct();
fit.liquidSlope=aL;
fit.liquidIntercept=bL;
fit.liquidR2=r2L;
fit.liquidFitRms=rmsL;
fit.liquidFitPoints=sum(liquidMask);
fit.gasSlope=aG;
fit.gasIntercept=bG;
fit.gasR2=r2G;
fit.gasFitRms=rmsG;
fit.gasFitPoints=sum(gasMask);
fit.slopeRatio=ratio;
fit.interfaceVelocityLiquid=uLi;
fit.interfaceVelocityGas=uGi;
fit.interfaceSlip=uGi-uLi;
fit.interfaceSlipOverUw=(uGi-uLi)/Uw;
fit.gasWallExtrapolated=uGw;
fit.gasWallSlip=Uw-uGw;
fit.gasWallSlipOverUw=(Uw-uGw)/Uw;
fit.commonModeRms=sqrt(mean(uEven.^2));
fit.commonModeRmsOverUw=fit.commonModeRms/abs(Uw);
fit.uyRms=sqrt(mean(uyY.^2));
fit.uyRmsOverUw=fit.uyRms/abs(Uw);
fit.zLiquidFitMax=zLmax;
fit.zGasFitMin=zGmin;
fit.zGasFitMax=zGmax;

profile=struct('z',z,'zOverH',z/h,'uOdd',uOdd,'uEven',uEven, ...
    'uyOdd',uyOdd,'uyEven',uyEven,'massFold',massFold, ...
    'liquidMask',liquidMask,'gasMask',gasMask);
end

function [a,b,r2,rmsFit]=ols_fit(x,y)
x=x(:); y=y(:);
if numel(x)<3, error('x23e:fit','Need at least 3 fit points.'); end
xm=mean(x); ym=mean(y);
sxx=sum((x-xm).^2);
a=sum((x-xm).*(y-ym))/sxx;
b=ym-a*xm;
res=y-(a*x+b);
sse=sum(res.^2);
sst=sum((y-ym).^2);
if sst>0, r2=1-sse/sst; else, r2=NaN; end
rmsFit=sqrt(mean(res.^2));
end

function S=read_kv_file(path)
fid=fopen(path,'r');
if fid<0, error('x23e:kv','Cannot open %s',path); end
c=onCleanup(@() fclose(fid));
S=struct();
while true
    line=fgetl(fid);
    if ~ischar(line), break; end
    hash=strfind(line,'#');
    if ~isempty(hash), line=line(1:hash(1)-1); end
    eq=strfind(line,'=');
    if isempty(eq), continue; end
    key=strtrim(line(1:eq(1)-1));
    val=strtrim(line(eq(1)+1:end));
    if isempty(key), continue; end
    key=matlab.lang.makeValidName(key);
    S.(key)=val;
end
end

function v=kvnum(S,key)
k=matlab.lang.makeValidName(key);
if ~isfield(S,k), error('x23e:kv','Missing key %s',key); end
v=str2double(S.(k));
if ~isfinite(v), error('x23e:kv','Key %s is not numeric: %s',key,S.(k)); end
end

function v=kvstr(S,key)
k=matlab.lang.makeValidName(key);
if ~isfield(S,k), error('x23e:kv','Missing key %s',key); end
v=S.(k);
end

function assert_close(a,b,tol,name)
if tol==0
    ok=(a==b);
else
    ok=abs(a-b)<=tol*max(1,abs(b));
end
if ~ok
    error('x23e:contract','%s=%g, expected %g',name,a,b);
end
end
