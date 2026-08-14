function suite = analyze_vk_symmetry_breaking_0493x7v(varargin)
%ANALYZE_VK_SYMMETRY_BREAKING_0493X7V Measure growth of the VK symmetry-breaking mode.
%
% 0493x7v is a MATLAB-only post-processing extension of 0493x7u. It does not
% rerun the solver. It uses the x7u timeseries to select equivalent convective
% windows and rereads only the corresponding particle dumps.
%
% Primary quantity:
%   reflection about y=y0, y'=2*y0-y
%     Ux_break    = 0.5*(Ux(y)-Ux(y'))
%     Uy_break    = 0.5*(Uy(y)+Uy(y'))
%     omega_break = 0.5*(omega(y)+omega(y'))
%
% For an exactly symmetric cylinder wake, these three fields vanish.  The
% primary axis is the cylinder centreline.  A channel-centreline calculation
% is also performed by default as a sensitivity check because the current VK
% cylinder is slightly offset from Ly/2.
%
% To isolate the coherent oscillatory wake from MPCD shot noise, x7v builds a
% two-mode POD basis from the SRC symmetry-breaking velocity snapshots for each
% geometry. Q6 and Q6-g-f are projected onto this SAME SRC basis. The envelope
%
%       A_POD = sqrt(a1^2+a2^2)/sqrt(2*Ncells)
%
% is fitted over common convective intervals with
%
%       log(A_POD) = c + sigma_D * tau_D,
%
% where tau_D = integral(U_inf dt / D) comes directly from x7u.  sigma_D is
% therefore the effective growth rate per convected cylinder diameter.  A
% dimensional fit d(log A)/dt is reported too.
%
% A self-POD pair is additionally calculated for each mode.  If Q6-g-f has a
% weak SRC-template amplitude but a strong self-POD amplitude, it is developing
% a different symmetry-breaking structure rather than simply suppressing the
% SRC shedding mode.
%
% Default execution directory: repository matlab/
%
% Typical use:
%   suite = analyze_vk_symmetry_breaking_0493x7v;
%
% Main outputs under ../runs/vk_symmetry_breaking_0493x7v_analysis:
%   vk_symmetry_breaking_timeseries_0493x7v.csv
%   vk_symmetry_breaking_summary_0493x7v.csv
%   vk_symmetry_breaking_pod_0493x7v.mat
%   diagnostic PNG/PDF figures
%
% Required existing helpers:
%   read_smpcd_state.m, bin_smpcd_state.m, parse_smpcd_kv.m
%
% Required x7u columns:
%   parentRun, runDir, mode, paramsFile, step, time, tauD, tauL, Uupstream

p = inputParser;
p.FunctionName = 'analyze_vk_symmetry_breaking_0493x7v';
addParameter(p, 'X7UTimeseries', '../runs/vk_vorticity_transport_0493x7u_analysis/vk_vorticity_timeseries_0493x7u.csv', @(x) ischar(x) || isstring(x));
addParameter(p, 'OutputDir', '../runs/vk_symmetry_breaking_0493x7v_analysis', @(x) ischar(x) || isstring(x));
addParameter(p, 'AnalysisCellsPerDiameter', 20, @(x) isnumeric(x) && isscalar(x) && x >= 8);
addParameter(p, 'WakeXRangeD', [0.75 7.00], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'WakeHalfHeightD', 1.50, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'ReadTauDRange', [4.0 15.0], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'WrapLimitDomainTransits', 0.80, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'FitTauDRanges', [4 8; 8 12; 12 15; 4 12], @(x) isnumeric(x) && size(x,2) == 2);
addParameter(p, 'PrimaryFitTauDRange', [4 12], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'MinFitPoints', 6, @(x) isnumeric(x) && isscalar(x) && x >= 3);
addParameter(p, 'MinFitR2', 0.70, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(p, 'SymmetryAxes', {'cylinder','channel'}, @(x) ischar(x) || isstring(x) || iscell(x));
addParameter(p, 'PODModes', 2, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'FluidRole', 1, @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'MakePlots', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'ShowFigures', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'WriteMat', true, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

x7uFile = char(opt.X7UTimeseries);
outDir = char(opt.OutputDir);
if exist(x7uFile,'file') ~= 2
    error('0493x7v:noX7U', 'x7u timeseries not found: %s', x7uFile);
end
if ~exist(outDir,'dir'), mkdir(outDir); end

T0 = readtable(x7uFile, 'VariableNamingRule', 'preserve');
required = {'parentRun','runDir','mode','paramsFile','step','time','tauD','tauL','Uupstream'};
for j = 1:numel(required)
    if ~ismember(required{j}, T0.Properties.VariableNames)
        error('0493x7v:missingColumn', 'Required x7u column missing: %s', required{j});
    end
end

T0.parentRun = string(T0.parentRun);
T0.runDir = string(T0.runDir);
T0.mode = string(T0.mode);
T0.paramsFile = string(T0.paramsFile);
T0.modeCanonical = strings(height(T0),1);
for i = 1:height(T0)
    T0.modeCanonical(i) = local_canonical_mode(T0.mode(i));
end

% Keep one run directory per parent configuration and canonical mode.  This is
% important when both q6-g-f and src-q6-g-f aliases exist: the longest complete
% run wins, so a short historical directory cannot silently replace it.
[selected, selectionTable] = local_select_best_alias_runs(T0);
writetable(selectionTable, fullfile(outDir,'vk_symmetry_breaking_selection_0493x7v.csv'));

parents = unique(selected.parentRun, 'stable');
allRows = {};
allSummary = {};
podStore = struct();

axesOpt = local_cellstr(opt.SymmetryAxes);
for ip = 1:numel(parents)
    parent = parents(ip);
    Tp = selected(selected.parentRun == parent,:);
    modesPresent = unique(Tp.modeCanonical,'stable');
    if ~any(modesPresent == "src")
        warning('0493x7v:noSRC','Skipping %s: no SRC reference run.',char(parent));
        continue;
    end

    cfg = local_prepare_configuration(Tp, opt);
    fprintf('\n[0493x7v] configuration=%s D=%.6g analysis=%dx%d offset=(cy-Ly/2)/D=%.6g\n', ...
        cfg.name, cfg.D, cfg.NxA, cfg.NyA, cfg.cylinderOffsetD);

    % Read each selected mode once. The same physical snapshots are reused for
    % the cylinder-axis and channel-axis parity calculations.
    modeData = struct();
    modeOrder = ["src","src-q6","src-q6-g-f"];
    for im = 1:numel(modeOrder)
        cm = modeOrder(im);
        if ~any(Tp.modeCanonical == cm), continue; end
        Tm = Tp(Tp.modeCanonical == cm,:);
        modeData.(local_mode_field(cm)) = local_read_mode_snapshots(Tm, cfg, opt);
    end

    for ia = 1:numel(axesOpt)
        axisName = lower(string(axesOpt{ia}));
        if axisName == "cylinder"
            y0 = cfg.cy;
        elseif axisName == "channel"
            y0 = 0.5*cfg.Ly;
        else
            error('0493x7v:badAxis','Unknown SymmetryAxes entry: %s',char(axisName));
        end

        % Build parity vectors for all modes on one identical wake mask.
        parity = struct();
        for im = 1:numel(modeOrder)
            cm = modeOrder(im);
            mf = local_mode_field(cm);
            if ~isfield(modeData,mf), continue; end
            parity.(mf) = local_build_parity_series(modeData.(mf), cfg, y0, axisName, opt);
        end

        src = parity.src;
        fitRange = sort(double(opt.PrimaryFitTauDRange(:).'));
        podMask = src.tauD >= fitRange(1) & src.tauD <= min(double(opt.ReadTauDRange(2)),15) & ...
            src.tauL < double(opt.WrapLimitDomainTransits);
        if nnz(podMask) < max(6,round(opt.PODModes)+2)
            warning('0493x7v:sparseSRC','%s axis=%s has only %d SRC POD frames.',cfg.name,char(axisName),nnz(podMask));
            continue;
        end

        [srcBasis, srcMean, srcPodInfo] = local_pod_basis(src.Xvelocity(:,podMask), round(opt.PODModes));
        if size(srcBasis,2) < 2
            warning('0493x7v:podRank','%s axis=%s SRC POD rank < 2; skipping.',cfg.name,char(axisName));
            continue;
        end

        cfgKey = local_safe_name(cfg.name);
        axisKey = local_safe_name(char(axisName));
        storeKey = matlab.lang.makeValidName([cfgKey,'__',axisKey]);
        podStore.(storeKey) = struct('configuration',cfg.name,'axis',char(axisName),'y0',y0, ...
            'basis',srcBasis,'srcMean',srcMean,'info',srcPodInfo,'maskLinearIndex',src.maskLinearIndex, ...
            'xc',cfg.xc,'yc',cfg.yc,'wakeMask',src.wakeMask);

        for im = 1:numel(modeOrder)
            cm = modeOrder(im);
            mf = local_mode_field(cm);
            if ~isfield(parity,mf), continue; end
            P = parity.(mf);

            modePodMask = P.tauD >= fitRange(1) & P.tauD <= min(double(opt.ReadTauDRange(2)),15) & ...
                P.tauL < double(opt.WrapLimitDomainTransits);
            if nnz(modePodMask) < 4
                warning('0493x7v:sparseMode','%s %s axis=%s has only %d POD-centering frames.', ...
                    cfg.name,char(cm),char(axisName),nnz(modePodMask));
                continue;
            end

            % Remove each mode's stationary parity bias before projection. This
            % suppresses the small fixed asymmetry caused by cy ~= Ly/2 and
            % isolates the oscillatory symmetry-breaking component.
            modeMean = mean(P.Xvelocity(:,modePodMask),2,'omitnan');
            Xc = P.Xvelocity - modeMean;
            coeff = srcBasis(:,1:2).' * Xc;
            commonAmp = sqrt(sum(coeff(1:2,:).^2,1)).' / sqrt(size(P.Xvelocity,1));

            [selfBasis, selfMean, selfInfo] = local_pod_basis(P.Xvelocity(:,modePodMask), round(opt.PODModes));
            if size(selfBasis,2) >= 2
                selfCoeff = selfBasis(:,1:2).' * (P.Xvelocity - selfMean);
                selfAmp = sqrt(sum(selfCoeff(1:2,:).^2,1)).' / sqrt(size(P.Xvelocity,1));
            else
                selfCoeff = nan(2,numel(P.tauD));
                selfAmp = nan(numel(P.tauD),1);
            end

            commonCapture = local_projection_capture(Xc(:,modePodMask),srcBasis(:,1:2));
            selfCapture = local_projection_capture(P.Xvelocity(:,modePodMask)-selfMean,selfBasis(:,1:min(2,size(selfBasis,2))));

            rowTable = local_timeseries_table(P,cfg,axisName,y0,cm,commonAmp,coeff,selfAmp,selfCoeff);
            allRows{end+1,1} = rowTable; %#ok<AGROW>

            summary = local_summary_table(P,rowTable,cfg,axisName,y0,cm,srcPodInfo,selfInfo, ...
                commonCapture,selfCapture,opt);
            allSummary{end+1,1} = summary; %#ok<AGROW>

            if logical(opt.MakePlots)
                local_make_mode_plot(rowTable,summary,cfg,axisName,cm,opt,outDir);
            end
        end

        if logical(opt.MakePlots)
            local_make_configuration_plot(allRows,cfg,axisName,opt,outDir);
        end
    end
end

if isempty(allRows)
    error('0493x7v:noResults','No analyzable symmetry-breaking series were produced.');
end
T = vertcat(allRows{:});
S = vertcat(allSummary{:});
writetable(T, fullfile(outDir,'vk_symmetry_breaking_timeseries_0493x7v.csv'));
writetable(S, fullfile(outDir,'vk_symmetry_breaking_summary_0493x7v.csv'));

suite = struct();
suite.timeseries = T;
suite.summary = S;
suite.selection = selectionTable;
suite.options = opt;
suite.pod = podStore;
suite.outputDir = outDir;
if logical(opt.WriteMat)
    save(fullfile(outDir,'vk_symmetry_breaking_pod_0493x7v.mat'),'suite','-v7.3');
end

if logical(opt.MakePlots)
    local_make_suite_growth_plot(S,opt,outDir);
end

fprintf('\n===== 0493x7v VK SYMMETRY-BREAKING GROWTH =====\n');
primaryAxis = "cylinder";
Sp = S(S.axis == primaryAxis,:);
for i = 1:height(Sp)
    fprintf('%s | mode=%s | axis=%s | offsetD=%+.4g | sigmaD(srcPOD,4-12)=%s R2=%s | sigmaD(selfPOD,4-12)=%s R2=%s | capture(src/self)=%.3f/%.3f | status=%s\n', ...
        char(Sp.configuration(i)), char(Sp.mode(i)), char(Sp.axis(i)), Sp.cylinderOffsetD(i), ...
        local_num_string(Sp.sigmaD_common_primary(i)), local_num_string(Sp.r2D_common_primary(i)), ...
        local_num_string(Sp.sigmaD_self_primary(i)), local_num_string(Sp.r2D_self_primary(i)), ...
        Sp.commonPodCapture(i), Sp.selfPodCapture(i), char(Sp.fitStatusCommon(i)));
end
fprintf('timeseries=%s\n',fullfile(outDir,'vk_symmetry_breaking_timeseries_0493x7v.csv'));
fprintf('summary=%s\n',fullfile(outDir,'vk_symmetry_breaking_summary_0493x7v.csv'));
fprintf('status=COMPLETE\n');
end

% =========================================================================
function [selected, Q] = local_select_best_alias_runs(T)
parents = unique(T.parentRun,'stable');
rows = {};
sel = false(height(T),1);
canonOrder = ["src","src-q6","src-q6-g-f"];
for ip = 1:numel(parents)
    for im = 1:numel(canonOrder)
        cm = canonOrder(im);
        idx = find(T.parentRun == parents(ip) & T.modeCanonical == cm);
        if isempty(idx), continue; end
        dirs = unique(T.runDir(idx),'stable');
        bestScore = [-Inf -Inf]; bestDir = "";
        for jd = 1:numel(dirs)
            j = idx(T.runDir(idx) == dirs(jd));
            mTau = max(T.tauD(j),[],'omitnan');
            if isempty(mTau) || ~isfinite(mTau), mTau=-Inf; end
            score = [mTau numel(j)];
            if score(1)>bestScore(1) || (score(1)==bestScore(1) && score(2)>bestScore(2))
                bestScore=score; bestDir=dirs(jd);
            end
        end
        chosen = idx(T.runDir(idx)==bestDir);
        sel(chosen)=true;
        rawModes = strjoin(unique(T.mode(chosen),'stable'),';');
        rows{end+1,1}=table(parents(ip),cm,bestDir,string(rawModes),bestScore(1),bestScore(2),numel(dirs), ...
            'VariableNames',{'parentRun','modeCanonical','selectedRunDir','selectedRawMode','maxTauD','nFrames','aliasDirectoryCount'}); %#ok<AGROW>
        if numel(dirs)>1
            fprintf('[0493x7v] alias selection parent=%s mode=%s -> %s (tauDmax=%.4g, frames=%d; candidates=%d)\n', ...
                char(parents(ip)),char(cm),char(bestDir),bestScore(1),bestScore(2),numel(dirs));
        end
    end
end
selected=T(sel,:);
if isempty(rows), Q=table(); else, Q=vertcat(rows{:}); end
end

% =========================================================================
function cfg = local_prepare_configuration(Tp,opt)
% Geometry is common to all modes in one parentRun. Use SRC params when possible.
idx=find(Tp.modeCanonical=="src",1,'first'); if isempty(idx), idx=1; end
runDir=char(Tp.runDir(idx));
paramsFile=local_resolve_params_file(char(Tp.paramsFile(idx)),runDir);
params=parse_smpcd_kv(paramsFile);
Lx=local_param_num(params,{'Lx'},NaN); Ly=local_param_num(params,{'Ly'},NaN);
NxNative=round(local_param_num(params,{'Nx','NX'},NaN));
NyNative=round(local_param_num(params,{'Ny','NY'},NaN));
dt=local_param_num(params,{'dt','DT'},NaN);
[cx,cy,R]=local_cylinder(params);
if ~all(isfinite([Lx Ly NxNative NyNative dt cx cy R])) || R<=0
    error('0493x7v:badParams','Incomplete geometry in %s',paramsFile);
end
D=2*R;
dxTarget=D/double(opt.AnalysisCellsPerDiameter);
NxA=max(8,round(Lx/dxTarget)); NyA=max(8,round(Ly/dxTarget));
xc=((0:NxA-1)+0.5)*Lx/NxA;
yc=((0:NyA-1)+0.5)*Ly/NyA;
[~,name]=fileparts(char(Tp.parentRun(1)));
periodicX=local_axis_periodic(params,'x'); periodicY=local_axis_periodic(params,'y');
cfg=struct('name',name,'parentRun',char(Tp.parentRun(1)),'paramsFile',paramsFile, ...
    'Lx',Lx,'Ly',Ly,'NxNative',NxNative,'NyNative',NyNative,'dt',dt,'periodicX',periodicX,'periodicY',periodicY, ...
    'cx',cx,'cy',cy,'R',R,'D',D,'NxA',NxA,'NyA',NyA,'xc',xc,'yc',yc, ...
    'cylinderOffsetD',(cy-0.5*Ly)/D);
end

% =========================================================================
function M = local_read_mode_snapshots(Tm,cfg,opt)
Tm=sortrows(Tm,'tauD');
range=sort(double(opt.ReadTauDRange(:).'));
keep=isfinite(Tm.tauD) & isfinite(Tm.tauL) & Tm.tauD>=range(1) & Tm.tauD<=range(2) & ...
    Tm.tauL<double(opt.WrapLimitDomainTransits);
Tm=Tm(keep,:);
if height(Tm)<4
    modeName='unknown'; if ~isempty(Tm), modeName=char(Tm.modeCanonical(1)); end
    warning('0493x7v:sparseRead','%s mode=%s only %d frames in requested tauD range.',cfg.name,modeName,height(Tm));
end
n=height(Tm);
if n==0, error('0493x7v:noFramesInRange','%s has no dumps in requested convective window.',cfg.name); end
Ux=cell(n,1); Uy=cell(n,1); Om=cell(n,1); N=cell(n,1);
for k=1:n
    dump=local_dump_path(char(Tm.runDir(k)),Tm.step(k));
    st=read_smpcd_state(dump);
    fld=bin_smpcd_state(st,'Lx',cfg.Lx,'Ly',cfg.Ly,'Nx',cfg.NxA,'Ny',cfg.NyA, ...
        'periodicX',cfg.periodicX,'periodicY',cfg.periodicY,'fluidOnly',true);
    ux=local_fill_empty_velocity(fld.Ux);
    uy=local_fill_empty_velocity(fld.Uy);
    om=local_vorticity(ux,uy,fld.dx,fld.dy,cfg.periodicX,cfg.periodicY);
    Ux{k}=ux; Uy{k}=uy; Om{k}=om; N{k}=fld.N;
    fprintf('[0493x7v] %s mode=%s %2d/%2d step=%g tauD=%.4g tauL=%.4g\n', ...
        cfg.name,char(Tm.modeCanonical(k)),k,n,Tm.step(k),Tm.tauD(k),Tm.tauL(k));
end
M=struct('table',Tm,'Ux',{Ux},'Uy',{Uy},'omega',{Om},'N',{N});
end

% =========================================================================
function P = local_build_parity_series(M,cfg,y0,axisName,opt)
n=height(M.table);
[X,Y]=meshgrid(cfg.xc,cfg.yc);
xr=sort(double(opt.WakeXRangeD(:).'));
xmin=cfg.cx+xr(1)*cfg.D; xmax=cfg.cx+xr(2)*cfg.D;
h=double(opt.WakeHalfHeightD)*cfg.D;
baseMask=X>=xmin & X<=xmax & abs(Y-y0)<=h;
ym=2*y0-cfg.yc(:);
mirrorValid=ym>=cfg.yc(1) & ym<=cfg.yc(end);
valid2D=repmat(mirrorValid,1,cfg.NxA);
wakeMask=baseMask & valid2D;
idx=find(wakeMask);
nc=numel(idx);
Xvel=nan(2*nc,n);
Avel=nan(n,1); Aom=nan(n,1); AvelN=nan(n,1);
for k=1:n
    ux=M.Ux{k}; uy=M.Uy{k}; om=M.omega{k}; nn=M.N{k};
    uxM=interp1(cfg.yc(:),ux,ym,'linear',NaN);
    uyM=interp1(cfg.yc(:),uy,ym,'linear',NaN);
    omM=interp1(cfg.yc(:),om,ym,'linear',NaN);
    uxB=0.5*(ux-uxM);
    uyB=0.5*(uy+uyM);
    omB=0.5*(om+omM);
    scaleU=max(abs(M.table.Uupstream(k)),1e-12);
    vx=uxB(idx)/scaleU; vy=uyB(idx)/scaleU;
    Xvel(:,k)=[vx;vy];
    Avel(k)=sqrt(mean(vx.^2+vy.^2,'omitnan'));
    Aom(k)=sqrt(mean(omB(idx).^2,'omitnan'))*cfg.D/scaleU;
    w=double(nn(idx)); good=isfinite(vx)&isfinite(vy)&isfinite(w)&w>0;
    if any(good)
        AvelN(k)=sqrt(sum(w(good).*(vx(good).^2+vy(good).^2))/sum(w(good)));
    end
end
P=struct();
P.axis=char(axisName); P.y0=y0; P.wakeMask=wakeMask; P.maskLinearIndex=idx;
P.Xvelocity=Xvel; P.AvelocityBreak=Avel; P.AvelocityBreakNWeighted=AvelN; P.AomegaBreak=Aom;
P.step=M.table.step; P.time=M.table.time; P.tauD=M.table.tauD; P.tauL=M.table.tauL;
P.Uupstream=M.table.Uupstream; P.runDir=M.table.runDir; P.rawMode=M.table.mode;
end

% =========================================================================
function [U,mu,info]=local_pod_basis(X,nModes)
mu=mean(X,2,'omitnan');
Xc=X-mu;
Xc(~isfinite(Xc))=0;
[U,S,~]=svd(Xc,'econ');
r=min([size(U,2),round(nModes)]);
U=U(:,1:r);
s=diag(S); e=s.^2; et=sum(e);
if et>0
    frac=e/et; cum=cumsum(frac);
else
    frac=zeros(size(e)); cum=zeros(size(e));
end
info=struct('singularValues',s,'energyFractions',frac,'cumulativeEnergy',cum, ...
    'energyFirst',local_pick_vector(frac,1),'energyFirst2',sum(frac(1:min(2,end))), ...
    'pairEnergyRatio',local_pair_ratio(e));
end

function r=local_pair_ratio(e)
if numel(e)<2 || e(2)<=0, r=NaN; else, r=e(1)/e(2); end
end

function v=local_pick_vector(a,k)
if numel(a)>=k, v=a(k); else, v=NaN; end
end

function c=local_projection_capture(Xc,U)
if isempty(U) || isempty(Xc), c=NaN; return; end
Xc(~isfinite(Xc))=0;
den=sum(Xc(:).^2);
if den<=0, c=NaN; return; end
Y=U.'*Xc;
c=sum(Y(:).^2)/den;
end

% =========================================================================
function T=local_timeseries_table(P,cfg,axisName,y0,cm,commonAmp,coeff,selfAmp,selfCoeff)
n=numel(P.tauD);
a1=coeff(1,:).'; a2=coeff(2,:).';
if size(selfCoeff,1)>=2
    s1=selfCoeff(1,:).'; s2=selfCoeff(2,:).';
else
    s1=nan(n,1); s2=nan(n,1);
end
T=table(repmat(string(cfg.name),n,1),repmat(string(cfg.parentRun),n,1),repmat(string(cm),n,1), ...
    string(P.rawMode),repmat(string(axisName),n,1),repmat(y0,n,1),repmat(cfg.cylinderOffsetD,n,1), ...
    P.step,P.time,P.tauD,P.tauL,P.Uupstream,P.AvelocityBreak,P.AvelocityBreakNWeighted,P.AomegaBreak, ...
    commonAmp,a1,a2,selfAmp,s1,s2,string(P.runDir), ...
    'VariableNames',{'configuration','parentRun','mode','rawMode','axis','symmetryAxisY','cylinderOffsetD', ...
    'step','time','tauD','tauL','Uupstream','AvelocityBreak','AvelocityBreakNWeighted','AomegaBreak', ...
    'AcommonSrcPOD','commonPODa1','commonPODa2','AselfPOD','selfPODa1','selfPODa2','runDir'});
end

% =========================================================================
function S=local_summary_table(P,T,cfg,axisName,y0,cm,srcInfo,selfInfo,commonCapture,selfCapture,opt)
primary=sort(double(opt.PrimaryFitTauDRange(:).'));
fitCommon=local_log_fit(T.tauD,T.AcommonSrcPOD,T.time,primary,opt);
fitSelf=local_log_fit(T.tauD,T.AselfPOD,T.time,primary,opt);
fitRawV=local_log_fit(T.tauD,T.AvelocityBreak,T.time,primary,opt);
fitRawW=local_log_fit(T.tauD,T.AomegaBreak,T.time,primary,opt);

ranges=double(opt.FitTauDRanges);
winVals=nan(size(ranges,1),6);
for j=1:size(ranges,1)
    fc=local_log_fit(T.tauD,T.AcommonSrcPOD,T.time,ranges(j,:),opt);
    winVals(j,:)=[fc.sigmaD fc.r2D fc.sigmaTime fc.r2Time fc.nPoints fc.growthFactor];
end

A48=local_window_rms(T.tauD,T.AcommonSrcPOD,[4 8]);
A812=local_window_rms(T.tauD,T.AcommonSrcPOD,[8 12]);
A1215=local_window_rms(T.tauD,T.AcommonSrcPOD,[12 15]);

S=table(string(cfg.name),string(cfg.parentRun),string(cm),string(axisName),y0,cfg.cylinderOffsetD, ...
    cfg.Lx,cfg.Ly,cfg.NxNative,cfg.NyNative,cfg.NxA,cfg.NyA,cfg.D,height(T), ...
    srcInfo.energyFirst2,srcInfo.pairEnergyRatio,selfInfo.energyFirst2,selfInfo.pairEnergyRatio,commonCapture,selfCapture, ...
    A48,A812,A1215, ...
    fitCommon.sigmaD,fitCommon.r2D,fitCommon.sigmaTime,fitCommon.r2Time,fitCommon.nPoints,fitCommon.growthFactor,string(fitCommon.status), ...
    fitSelf.sigmaD,fitSelf.r2D,fitSelf.sigmaTime,fitSelf.r2Time,fitSelf.nPoints,fitSelf.growthFactor,string(fitSelf.status), ...
    fitRawV.sigmaD,fitRawV.r2D,fitRawW.sigmaD,fitRawW.r2D, ...
    'VariableNames',{'configuration','parentRun','mode','axis','symmetryAxisY','cylinderOffsetD', ...
    'Lx','Ly','NxNative','NyNative','analysisNx','analysisNy','D','nFrames', ...
    'srcPodEnergy12','srcPodPairEnergyRatio','selfPodEnergy12','selfPodPairEnergyRatio','commonPodCapture','selfPodCapture', ...
    'AcommonRmsTau4to8','AcommonRmsTau8to12','AcommonRmsTau12to15', ...
    'sigmaD_common_primary','r2D_common_primary','sigmaTime_common_primary','r2Time_common_primary','fitPointsCommon','growthFactorCommon','fitStatusCommon', ...
    'sigmaD_self_primary','r2D_self_primary','sigmaTime_self_primary','r2Time_self_primary','fitPointsSelf','growthFactorSelf','fitStatusSelf', ...
    'sigmaD_rawVelocity_primary','r2D_rawVelocity_primary','sigmaD_rawVorticity_primary','r2D_rawVorticity_primary'});

for j=1:size(ranges,1)
    tag=sprintf('tau%gto%g',ranges(j,1),ranges(j,2)); tag=strrep(tag,'.','p'); tag=strrep(tag,'-','m');
    S.(['sigmaD_common_',tag])=winVals(j,1);
    S.(['r2D_common_',tag])=winVals(j,2);
    S.(['sigmaTime_common_',tag])=winVals(j,3);
    S.(['r2Time_common_',tag])=winVals(j,4);
    S.(['fitPoints_common_',tag])=winVals(j,5);
    S.(['growthFactor_common_',tag])=winVals(j,6);
end
end

% =========================================================================
function f=local_log_fit(tau,A,time,range,opt)
range=sort(double(range(:).'));
keep=isfinite(tau)&isfinite(A)&A>0&isfinite(time)&tau>=range(1)&tau<=range(2);
x=tau(keep); y=log(A(keep)); tt=time(keep);
f=struct('sigmaD',NaN,'r2D',NaN,'sigmaTime',NaN,'r2Time',NaN,'nPoints',numel(x),'growthFactor',NaN,'status',"INSUFFICIENT_POINTS");
if numel(x)<round(opt.MinFitPoints), return; end
[p,~,mu]=polyfit(x,y,1); yp=polyval(p,x,[],mu); slopeD=p(1)/mu(2);
f.sigmaD=slopeD; f.r2D=local_r2(y,yp);
[pt,~,mut]=polyfit(tt,y,1); ypt=polyval(pt,tt,[],mut); f.sigmaTime=pt(1)/mut(2); f.r2Time=local_r2(y,ypt);
f.growthFactor=exp(f.sigmaD*(max(x)-min(x)));
if f.sigmaD<=0
    f.status="DECAY_OR_FLAT";
elseif f.r2D>=double(opt.MinFitR2)
    f.status="PASS_LINEAR";
else
    f.status="WEAK_LINEARITY";
end
end

function r=local_r2(y,yp)
ssr=sum((y-yp).^2); sst=sum((y-mean(y)).^2);
if sst<=eps, r=NaN; else, r=1-ssr/sst; end
end

function a=local_window_rms(tau,A,range)
range=sort(double(range(:).')); k=isfinite(tau)&isfinite(A)&tau>=range(1)&tau<range(2);
if ~any(k), a=NaN; else, a=sqrt(mean(A(k).^2,'omitnan')); end
end

% =========================================================================
function local_make_mode_plot(T,S,cfg,axisName,cm,opt,outDir)
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name',sprintf('0493x7v %s %s %s',cfg.name,char(cm),char(axisName)));
tl=tiledlayout(2,2,'Padding','compact','TileSpacing','compact'); %#ok<NASGU>
nexttile;
semilogy(T.tauD,T.AcommonSrcPOD,'-o','LineWidth',1.1,'MarkerSize',3); hold on;
semilogy(T.tauD,T.AselfPOD,'-','LineWidth',1.0);
semilogy(T.tauD,T.AvelocityBreak,'--','LineWidth',0.9);
xlabel('\tau_D'); ylabel('amplitude'); grid on;
legend({'SRC-template POD pair','self POD pair','raw parity velocity'},'Location','best');
title(sprintf('%s | %s | %s axis',cfg.name,char(cm),char(axisName)),'Interpreter','none');
nexttile;
plot(T.tauD,T.commonPODa1,'-','LineWidth',1.0); hold on; plot(T.tauD,T.commonPODa2,'-','LineWidth',1.0);
xlabel('\tau_D'); ylabel('POD coefficient'); grid on; legend({'a_1','a_2'},'Location','best'); title('SRC shedding-mode coordinates');
nexttile;
plot(T.commonPODa1,T.commonPODa2,'-o','MarkerSize',3); axis equal; grid on; xlabel('a_1'); ylabel('a_2'); title('POD phase plane');
nexttile;
semilogy(T.tauD,T.AomegaBreak,'-','LineWidth',1.0); xlabel('\tau_D'); ylabel('\omega_{break,rms}D/U_\infty'); grid on; title('Raw even-vorticity parity');
sgtitle(sprintf('sigma_D(4-12)=%.4g, R^2=%.3f, capture=%.3f',S.sigmaD_common_primary,S.r2D_common_primary,S.commonPodCapture));
local_export_figure(fig,fullfile(outDir,['vk_symmetry_breaking_',local_safe_name(cfg.name),'_',local_safe_name(char(cm)),'_',local_safe_name(char(axisName))]));
end

function local_make_configuration_plot(allRows,cfg,axisName,opt,outDir)
% Select only rows belonging to this configuration+axis from accumulated tables.
T=vertcat(allRows{:});
k=T.configuration==string(cfg.name)&T.axis==string(axisName); T=T(k,:);
if isempty(T), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name',sprintf('0493x7v compare %s %s',cfg.name,char(axisName)));
hold on; modes=["src","src-q6","src-q6-g-f"];
for i=1:numel(modes)
    Q=T(T.mode==modes(i),:); if isempty(Q), continue; end
    semilogy(Q.tauD,Q.AcommonSrcPOD,'-o','LineWidth',1.15,'MarkerSize',3,'DisplayName',char(modes(i)));
end
xlabel('\tau_D'); ylabel('SRC-template symmetry-breaking POD amplitude'); grid on; legend('Location','best');
title(sprintf('%s | %s axis | common SRC shedding basis',cfg.name,char(axisName)),'Interpreter','none');
local_export_figure(fig,fullfile(outDir,['vk_symmetry_breaking_compare_',local_safe_name(cfg.name),'_',local_safe_name(char(axisName))]));
end

function local_make_suite_growth_plot(S,opt,outDir)
Sc=S(S.axis=="cylinder",:); if isempty(Sc), return; end
vis='off'; if logical(opt.ShowFigures), vis='on'; end
fig=figure('Visible',vis,'Color','w','Name','0493x7v symmetry-breaking growth summary');
configs=unique(Sc.configuration,'stable'); modes=["src","src-q6","src-q6-g-f"];
Y=nan(numel(configs),numel(modes)); R=nan(size(Y));
for i=1:numel(configs)
    for j=1:numel(modes)
        k=Sc.configuration==configs(i)&Sc.mode==modes(j);
        if any(k), Y(i,j)=Sc.sigmaD_common_primary(find(k,1)); R(i,j)=Sc.r2D_common_primary(find(k,1)); end
    end
end
bar(categorical(configs),Y,'grouped'); ylabel('\sigma_D = d ln A / d\tau_D'); grid on;
legend(cellstr(modes),'Location','best'); title('Growth of SRC-template symmetry-breaking mode, cylinder axis');
for i=1:numel(configs)
    for j=1:numel(modes)
        if isfinite(Y(i,j))
            text(i+(j-(numel(modes)+1)/2)*0.20,Y(i,j),sprintf('R^2 %.2f',R(i,j)),'Rotation',90,'VerticalAlignment','bottom','HorizontalAlignment','center','FontSize',8);
        end
    end
end
local_export_figure(fig,fullfile(outDir,'vk_symmetry_breaking_growth_summary_0493x7v'));
end

function local_export_figure(fig,base)
try, exportgraphics(fig,[base,'.png'],'Resolution',160); catch, saveas(fig,[base,'.png']); end
try, exportgraphics(fig,[base,'.pdf'],'ContentType','vector'); catch, try, saveas(fig,[base,'.pdf']); catch, end, end
if strcmpi(get(fig,'Visible'),'off'), close(fig); end
end

% =========================================================================
function dump=local_dump_path(runDir,step)
out=fullfile(runDir,'output');
step=round(double(step));
exact=fullfile(out,sprintf('state_step_%06d.smpcd',step));
if exist(exact,'file')==2, dump=exact; return; end
files=dir(fullfile(out,'state_step_*.smpcd'));
for k=1:numel(files)
    tok=regexp(files(k).name,'state_step_(\d+)\.smpcd$','tokens','once');
    if ~isempty(tok) && str2double(tok{1})==step
        dump=fullfile(files(k).folder,files(k).name); return;
    end
end
error('0493x7v:missingDump','Missing step %d under %s',step,out);
end

function pfile=local_resolve_params_file(candidate,runDir)
if exist(candidate,'file')==2, pfile=candidate; return; end
cands={fullfile(runDir,'params','vk_darcy_chi_periodic.kv'),fullfile(runDir,'output','params_used.kv'),fullfile(runDir,'params_used.kv')};
for k=1:numel(cands)
    if exist(cands{k},'file')==2, pfile=cands{k}; return; end
end
error('0493x7v:noParams','No params file found for %s',runDir);
end

% =========================================================================
function omega=local_vorticity(Ux,Uy,dx,dy,periodicX,periodicY)
Ux=local_fill_empty_velocity(Ux); Uy=local_fill_empty_velocity(Uy);
if periodicX
    dUy_dx=(circshift(Uy,[0,-1])-circshift(Uy,[0,1]))/(2*dx);
else
    dUy_dx=local_derivative_x(Uy,dx);
end
if periodicY
    dUx_dy=(circshift(Ux,[-1,0])-circshift(Ux,[1,0]))/(2*dy);
else
    dUx_dy=local_derivative_y(Ux,dy);
end
omega=dUy_dx-dUx_dy;
end

function A=local_fill_empty_velocity(A)
if all(isfinite(A(:))), return; end
for pass=1:4
    bad=~isfinite(A); if ~any(bad(:)), break; end
    vals=zeros(size(A)); cnt=zeros(size(A));
    shifts={[0 1],[0 -1],[1 0],[-1 0]};
    for j=1:numel(shifts)
        B=circshift(A,shifts{j}); ok=isfinite(B); vals(ok)=vals(ok)+B(ok); cnt(ok)=cnt(ok)+1;
    end
    fill=bad&cnt>0; A(fill)=vals(fill)./cnt(fill);
end
A(~isfinite(A))=0;
end

function d=local_derivative_x(A,dx)
d=zeros(size(A)); d(:,2:end-1)=(A(:,3:end)-A(:,1:end-2))/(2*dx); d(:,1)=(A(:,2)-A(:,1))/dx; d(:,end)=(A(:,end)-A(:,end-1))/dx;
end
function d=local_derivative_y(A,dy)
d=zeros(size(A)); d(2:end-1,:)=(A(3:end,:)-A(1:end-2,:))/(2*dy); d(1,:)=(A(2,:)-A(1,:))/dy; d(end,:)=(A(end,:)-A(end-1,:))/dy;
end

% =========================================================================

function tf=local_axis_periodic(params,axisName)
tf=false;
if strcmpi(axisName,'x')
    if isfield(params,'bcX'), tf=strcmpi(char(string(params.bcX)),'periodic'); return; end
    if isfield(params,'bcLeft')&&isfield(params,'bcRight')
        tf=strcmpi(char(string(params.bcLeft)),'periodic')&&strcmpi(char(string(params.bcRight)),'periodic');
    end
else
    if isfield(params,'bcY'), tf=strcmpi(char(string(params.bcY)),'periodic'); return; end
    if isfield(params,'bcBottom')&&isfield(params,'bcTop')
        tf=strcmpi(char(string(params.bcBottom)),'periodic')&&strcmpi(char(string(params.bcTop)),'periodic');
    end
end
end

function [cx,cy,R]=local_cylinder(params)
cx=local_param_num(params,{'darcyCircleCx','immersedSolidCx','immersedCircleCx'},NaN);
cy=local_param_num(params,{'darcyCircleCy','immersedSolidCy','immersedCircleCy'},NaN);
R=local_param_num(params,{'darcyCircleR','immersedSolidR','immersedCircleR'},NaN);
if isfinite(cx)&&isfinite(cy)&&isfinite(R)&&R>0, return; end
if isfield(params,'darcyChiFile')
    chi=char(string(params.darcyChiFile));
    tok=regexp(chi,'circle_xc([^_/\\]+)_yc([^_/\\]+)_(?:rc|r)([^_/\\]+)_','tokens','once');
    if ~isempty(tok)
        tx=local_filename_number(tok{1}); ty=local_filename_number(tok{2}); tr=local_filename_number(tok{3});
        if isfinite(tx)&&isfinite(ty)&&isfinite(tr)&&tr>0, cx=tx; cy=ty; R=tr; return; end
    end
end
end

function v=local_filename_number(s)
s=char(s); v=str2double(s); if isfinite(v), return; end
s=strrep(s,'p','.'); if startsWith(s,'m'), s=['-',s(2:end)]; end; v=str2double(s);
end

function v=local_param_num(params,names,default)
v=default;
for k=1:numel(names)
    n=names{k};
    if isfield(params,n)
        x=params.(n);
        if isnumeric(x), y=double(x(1)); else, y=str2double(char(string(x))); end
        if isfinite(y), v=y; return; end
    end
end
end

% =========================================================================
function cm=local_canonical_mode(mode)
s=lower(strtrim(char(string(mode))));
switch s
    case {'src','classic'}
        cm="src";
    case {'src-q6','q6'}
        cm="src-q6";
    case {'src-q6-g-f','q6-g-f','src+q6-g-f'}
        cm="src-q6-g-f";
    otherwise
        cm=string(s);
end
end

function f=local_mode_field(cm)
switch char(cm)
    case 'src', f='src';
    case 'src-q6', f='src_q6';
    case 'src-q6-g-f', f='src_q6_g_f';
    otherwise, f=matlab.lang.makeValidName(char(cm));
end
end

function c=local_cellstr(x)
if ischar(x), c={x}; elseif isstring(x), c=cellstr(x); else, c=x; end
end

function s=local_safe_name(s)
s=regexprep(char(string(s)),'[^A-Za-z0-9._-]+','_');
end

function s=local_num_string(x)
if isfinite(x), s=sprintf('%.6g',x); else, s='NA'; end
end
