function results = analyze_0493x14aj_n3_first_cycle(runsRoot, seeds)
%ANALYZE_0493X14AJ_N3_FIRST_CYCLE
% Focused, no-new-run analysis of the already generated two-phase n=3 drops.
%
% Purpose:
%   Determine whether the frequency deficit is already present during the
%   first coherent oscillation, before late-time thermal noise dominates.
%
% Usage from repository matlab/:
%   analyze_0493x14aj_n3_first_cycle('../runs')
%   analyze_0493x14aj_n3_first_cycle('../runs',[493180 493181 493182])
%
% Input:
%   Reuses the trace CSV already produced by
%   analyze_0493x14aj_n3_two_phase_jcp:
%     <run>/analysis/oscillating_drop_n3_two_phase_trace.csv
%
% No state re-reading, no new simulation, no fit beyond the first cycle.
%
% Primary timing observable:
%   G_z12 = T_th / (2*(t_zero2-t_zero1))
% because two consecutive zero crossings are separated by half a period.
% This is largely independent of the arbitrary phase of the initial condition.
%
% Complementary observables:
%   G_z1  = T_th/(4*t_zero1)
%   G_min = T_th/(2*t_min1)
%   G_max = T_th/t_max1
%
% Local extrema are refined with a quadratic interpolation through three
% consecutive samples. Zero crossings are linearly interpolated.

if nargin < 1 || isempty(runsRoot)
    runsRoot = '../runs';
end
if nargin < 2 || isempty(seeds)
    d = dir(fullfile(runsRoot,'0493x14aj_n3_two_phase_jcp_seed*'));
    seeds = [];
    for k = 1:numel(d)
        tok = regexp(d(k).name,'seed(\d+)$','tokens','once');
        if ~isempty(tok)
            seeds(end+1) = str2double(tok{1}); %#ok<AGROW>
        end
    end
    seeds = sort(unique(seeds));
end
if isempty(seeds)
    error('No x14aj JCP seed directories found under %s',runsRoot);
end

% Frozen theory point used by the current x14aj JCP campaign.
p.omegaTheory = 3.34229099435;
p.periodTheory = 1.87990373005;

fprintf('\n===== x14aj n=3 / FIRST-COHERENT-CYCLE ANALYSIS =====\n');
fprintf('omega_th=%.12g  T_th=%.12g\n',p.omegaTheory,p.periodTheory);
fprintf('Only 0 <= t/T_th <= 1.35 is used. Late-time fitting is intentionally excluded.\n\n');

rows = repmat(emptyRow(),0,1);
traces = cell(0,1);

for iseed = 1:numel(seeds)
    seed = seeds(iseed);
    runRoot = fullfile(runsRoot,sprintf('0493x14aj_n3_two_phase_jcp_seed%d',seed));
    tracePath = fullfile(runRoot,'analysis','oscillating_drop_n3_two_phase_trace.csv');
    if ~isfile(tracePath)
        warning('Missing trace for seed %d: %s',seed,tracePath);
        continue;
    end

    T = readtable(tracePath);
    need = {'time','q3Parallel'};
    if ~all(ismember(need,T.Properties.VariableNames))
        error('Trace %s must contain time and q3Parallel',tracePath);
    end

    t = T.time - T.time(1);
    q = T.q3Parallel;
    keep = t <= 1.35*p.periodTheory + 1e-12;
    t = t(keep); q = q(keep);

    if numel(t) < 8
        error('Seed %d: too few samples in first-cycle window',seed);
    end

    % First descending zero around T/4.
    tz1 = findZero(t,q,0.08*p.periodTheory,0.48*p.periodTheory,-1);

    % First minimum around T/2.
    [tmin,qmin] = localExtremum(t,q,0.28*p.periodTheory,0.72*p.periodTheory,'min');

    % Second, rising zero around 3T/4.
    tz2 = findZero(t,q,0.52*p.periodTheory,1.02*p.periodTheory,+1);

    % First positive maximum after the initial state, around one period.
    [tmax,qmax] = localExtremum(t,q,0.78*p.periodTheory,1.35*p.periodTheory,'max');

    q0 = q(1);

    r = emptyRow();
    r.seed = seed;
    r.q0 = q0;
    r.tZero1OverT = tz1/p.periodTheory;
    r.tMin1OverT = tmin/p.periodTheory;
    r.tZero2OverT = tz2/p.periodTheory;
    r.tMax1OverT = tmax/p.periodTheory;
    r.Gzero1 = p.periodTheory/(4*tz1);
    r.Gmin1 = p.periodTheory/(2*tmin);
    r.Gzero12 = p.periodTheory/(2*(tz2-tz1));
    r.Gmax1 = p.periodTheory/tmax;
    r.qMin1 = qmin;
    r.qMax1 = qmax;
    r.absMinOverInitial = abs(qmin)/max(abs(q0),eps);
    r.max1OverInitial = qmax/max(abs(q0),eps);

    rows(end+1,1) = r; %#ok<AGROW>
    traces{end+1,1} = struct('seed',seed,'t',t,'q',q, ...
        'tz1',tz1,'tmin',tmin,'tz2',tz2,'tmax',tmax, ...
        'qmin',qmin,'qmax',qmax); %#ok<AGROW>

    fprintf(['seed %d: z1=%.4fT  min=%.4fT  z2=%.4fT  max=%.4fT | ', ...
             'G_z12=%.4f  G_min=%.4f  G_max=%.4f\n'], ...
        seed,r.tZero1OverT,r.tMin1OverT,r.tZero2OverT,r.tMax1OverT, ...
        r.Gzero12,r.Gmin1,r.Gmax1);
end

if isempty(rows)
    error('No usable traces found.');
end

outDir = fullfile(runsRoot,'0493x14aj_n3_two_phase_jcp_analysis','first_cycle');
if ~isfolder(outDir), mkdir(outDir); end

Tout = struct2table(rows);
writetable(Tout,fullfile(outDir,'n3_first_cycle_by_seed.csv'));

metrics = {'Gzero12','Gmin1','Gmax1','Gzero1'};
ens = struct();
ens.seeds = [rows.seed];
ens.omegaTheory = p.omegaTheory;
ens.periodTheory = p.periodTheory;
for k = 1:numel(metrics)
    name = metrics{k};
    v = [rows.(name)];
    ens.([name 'Mean']) = mean(v,'omitnan');
    ens.([name 'Std']) = std(v,0,'omitnan');
end
ens.primaryMetric = 'Gzero12';
ens.primaryRationale = ['Two consecutive zero crossings give a half-period and ', ...
    'are less sensitive to amplitude decay and to the phase of the imposed initial deformation.'];
ens.scope = 'First coherent cycle only; no late-time thermal-tail fit.';

writeJson(fullfile(outDir,'n3_first_cycle_summary.json'),ens);

fid = fopen(fullfile(outDir,'n3_first_cycle_report.txt'),'w');
c = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid,'===== x14aj n=3 FIRST-COHERENT-CYCLE ANALYSIS =====\n');
fprintf(fid,'seeds=%s\n',mat2str(ens.seeds));
fprintf(fid,'omegaTheory=%.12g periodTheory=%.12g\n',p.omegaTheory,p.periodTheory);
fprintf(fid,'PRIMARY Gzero12=%.8g +/- %.5g\n',ens.Gzero12Mean,ens.Gzero12Std);
fprintf(fid,'Gmin1=%.8g +/- %.5g\n',ens.Gmin1Mean,ens.Gmin1Std);
fprintf(fid,'Gmax1=%.8g +/- %.5g\n',ens.Gmax1Mean,ens.Gmax1Std);
fprintf(fid,'Gzero1=%.8g +/- %.5g\n',ens.Gzero1Mean,ens.Gzero1Std);
fprintf(fid,'NOTE: only first-cycle timing is used; late-time stochastic tail is excluded.\n');
fprintf(fid,'NOTE: Gzero12 is the primary metric because it uses the interval between consecutive zero crossings.\n');
clear c

% Focused figure: only first coherent cycle, with theoretical phase markers.
fig = figure('Visible','off'); hold on; box on;
for k = 1:numel(traces)
    tr = traces{k};
    plot(tr.t/p.periodTheory,tr.q,'o-','DisplayName',sprintf('seed %d',tr.seed));
    plot(tr.tz1/p.periodTheory,0,'x','HandleVisibility','off','LineWidth',1.2);
    plot(tr.tmin/p.periodTheory,tr.qmin,'v','HandleVisibility','off');
    plot(tr.tz2/p.periodTheory,0,'x','HandleVisibility','off','LineWidth',1.2);
    plot(tr.tmax/p.periodTheory,tr.qmax,'^','HandleVisibility','off');
end
xline(0.25,':','HandleVisibility','off');
xline(0.50,':','HandleVisibility','off');
xline(0.75,':','HandleVisibility','off');
xline(1.00,':','HandleVisibility','off');
yline(0,':','HandleVisibility','off');
xlim([0 1.35]);
xlabel('t/T_3^{th}');
ylabel('q_3');
title('Two-phase n=3: first coherent cycle');
legend('Location','best');
exportgraphics(fig,fullfile(outDir,'n3_first_cycle_timing.png'),'Resolution',180);
close(fig);

fprintf('\nPRIMARY ensemble G_z12 = %.6f +/- %.6f (1 SD, %d seeds)\n', ...
    ens.Gzero12Mean,ens.Gzero12Std,numel(rows));
fprintf('Complementary G_min = %.6f +/- %.6f ; G_max = %.6f +/- %.6f\n', ...
    ens.Gmin1Mean,ens.Gmin1Std,ens.Gmax1Mean,ens.Gmax1Std);
fprintf('Outputs: %s\n',outDir);

results = struct('bySeed',rows,'ensemble',ens,'outputDir',outDir);
end

function tz = findZero(t,q,tlo,thi,direction)
idx = find(t(1:end-1) >= tlo & t(2:end) <= thi);
tz = NaN;
for k = idx(:)'
    a = q(k); b = q(k+1);
    crossed = (a == 0) || (a*b < 0);
    if ~crossed, continue; end
    slope = b-a;
    if direction < 0 && slope >= 0, continue; end
    if direction > 0 && slope <= 0, continue; end
    if a == 0
        tz = t(k);
    else
        tz = t(k) - a*(t(k+1)-t(k))/(b-a);
    end
    return;
end
error('Could not find requested zero crossing in [%.6g, %.6g]',tlo,thi);
end

function [te,qe] = localExtremum(t,q,tlo,thi,kind)
idx = find(t >= tlo & t <= thi);
if numel(idx) < 3
    error('Too few samples for extremum in [%.6g, %.6g]',tlo,thi);
end
if strcmp(kind,'min')
    [~,jrel] = min(q(idx));
else
    [~,jrel] = max(q(idx));
end
j = idx(jrel);

% Quadratic interpolation if the selected point has neighbors.
if j > 1 && j < numel(t)
    tt = t(j-1:j+1);
    qq = q(j-1:j+1);
    pp = polyfit(tt,qq,2);
    if abs(pp(1)) > eps
        tv = -pp(2)/(2*pp(1));
        if tv >= tt(1) && tv <= tt(3)
            qv = polyval(pp,tv);
            if (strcmp(kind,'min') && pp(1)>0) || (strcmp(kind,'max') && pp(1)<0)
                te = tv; qe = qv; return;
            end
        end
    end
end
te = t(j); qe = q(j);
end

function writeJson(path,S)
fid=fopen(path,'w');
if fid<0, error('Cannot write %s',path); end
c=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(S,'PrettyPrint',true));
fwrite(fid,newline);
end

function r=emptyRow()
r=struct('seed',NaN,'q0',NaN, ...
    'tZero1OverT',NaN,'tMin1OverT',NaN,'tZero2OverT',NaN,'tMax1OverT',NaN, ...
    'Gzero1',NaN,'Gmin1',NaN,'Gzero12',NaN,'Gmax1',NaN, ...
    'qMin1',NaN,'qMax1',NaN,'absMinOverInitial',NaN,'max1OverInitial',NaN);
end
