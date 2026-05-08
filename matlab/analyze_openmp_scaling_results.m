function T = analyze_openmp_scaling_results(rootDir)
if nargin < 1 || isempty(rootDir)
    rootDir = pwd;
end

d = dir(fullfile(rootDir, 'threads_*'));
if isempty(d)
    error('Aucun sous-répertoire threads_* trouvé dans %s', rootDir);
end

rows = struct([]);
for k = 1:numel(d)
    runDir = fullfile(d(k).folder, d(k).name);
    tok = regexp(d(k).name, 'threads_(\d+)', 'tokens', 'once');
    if isempty(tok), continue; end
    nThreads = str2double(tok{1});

    kvCandidates = { ...
        fullfile(runDir,'benchmark_out_runout.kv'), ...
        fullfile(runDir,'state_out_runout.kv'), ...
        fullfile(runDir,'benchmark_out.kv'), ...
        fullfile(runDir,'state_out.kv')};
    kvPath = '';
    for j = 1:numel(kvCandidates)
        if exist(kvCandidates{j}, 'file')
            kvPath = kvCandidates{j};
            break;
        end
    end
    if isempty(kvPath), continue; end

    kv = parse_kv_local(kvPath);
    elapsed = parse_time_local(fullfile(runDir,'time.txt'));

    row = struct();
    row.threads = nThreads;
    row.elapsed_seconds = elapsed;
    row.finalQx = getnum_local(kv, 'finalQx');
    row.finalOccStd = getnum_local(kv, 'finalOccStd');
    row.finalOutBand = getnum_local(kv, 'finalOutBand');
    row.finalMeanKinetic = getnum_local(kv, 'finalMeanKinetic');
    row.finalBetaRepairApplied = getnum_local(kv, 'finalBetaRepairApplied');
    row.nThreadsUsedBase = getnum_local(kv, 'nThreadsUsedBase');
    row.nThreadsUsedShifted = getnum_local(kv, 'nThreadsUsedShifted');
    row.runDir = string(runDir);
    rows = [rows; row]; %#ok<AGROW>
end

if isempty(rows)
    error('Aucun résultat exploitable trouvé.');
end

[~,ord] = sort([rows.threads]);
rows = rows(ord);

T = struct2table(rows);

i1 = find(T.threads == 1, 1);
if ~isempty(i1) && ~isnan(T.elapsed_seconds(i1)) && T.elapsed_seconds(i1) > 0
    T.speedup_vs_1 = T.elapsed_seconds(i1) ./ T.elapsed_seconds;
    T.efficiency_vs_1 = T.speedup_vs_1 ./ T.threads;
    T.deltaQx_vs_1 = T.finalQx - T.finalQx(i1);
    T.deltaOccStd_vs_1 = T.finalOccStd - T.finalOccStd(i1);
    T.deltaMeanKinetic_vs_1 = T.finalMeanKinetic - T.finalMeanKinetic(i1);
else
    T.speedup_vs_1 = nan(height(T),1);
    T.efficiency_vs_1 = nan(height(T),1);
    T.deltaQx_vs_1 = nan(height(T),1);
    T.deltaOccStd_vs_1 = nan(height(T),1);
    T.deltaMeanKinetic_vs_1 = nan(height(T),1);
end

writetable(T, fullfile(rootDir, 'openmp_scaling_analysis.csv'));

figure('Name','OpenMP scaling - temps'); plot(T.threads, T.elapsed_seconds, '-o'); grid on
xlabel('Threads'); ylabel('Temps (s)'); title('Temps total vs threads');

figure('Name','OpenMP scaling - speedup'); plot(T.threads, T.speedup_vs_1, '-o'); grid on
xlabel('Threads'); ylabel('Speed-up'); title('Speed-up vs threads');

figure('Name','OpenMP scaling - efficacite'); plot(T.threads, T.efficiency_vs_1, '-o'); grid on
xlabel('Threads'); ylabel('Efficacité'); title('Efficacité vs threads');

figure('Name','OpenMP scaling - Q final'); plot(T.threads, T.finalQx, '-o'); grid on
xlabel('Threads'); ylabel('Q final'); title('Q final vs threads');

figure('Name','OpenMP scaling - occStd'); plot(T.threads, T.finalOccStd, '-o'); grid on
xlabel('Threads'); ylabel('occStd final'); title('occStd final vs threads');

figure('Name','OpenMP scaling - mean kinetic'); plot(T.threads, T.finalMeanKinetic, '-o'); grid on
xlabel('Threads'); ylabel('Mean kinetic final'); title('Énergie cinétique finale vs threads');

disp(T);

end

function kv = parse_kv_local(path)
kv = struct();
txt = splitlines(string(fileread(path)));
for i = 1:numel(txt)
    s = strtrim(txt(i));
    if s == "" || ~contains(s, "="), continue; end
    p = split(s, "=", 2);
    key = matlab.lang.makeValidName(strtrim(p(1)));
    val = strtrim(p(2));
    kv.(key) = val;
end
end

function x = getnum_local(kv, field)
if isfield(kv, field)
    x = str2double(kv.(field));
else
    x = NaN;
end
end

function x = parse_time_local(path)
x = NaN;
if ~exist(path, 'file'), return; end
txt = fileread(path);
tok = regexp(txt, 'elapsed_seconds=([0-9.]+)', 'tokens', 'once');
if ~isempty(tok)
    x = str2double(tok{1});
end
end
