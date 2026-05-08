function stats = compare_benchmark_poiseuille_1500(prep, M, Snaps, R)
%COMPARE_BENCHMARK_POISEUILLE_1500 Simple post-processing for Poiseuille benchmark.

stats = struct();
stats.finalOccStd = M.occStd(end);
stats.finalOutBand = M.outBand(end);
stats.finalMeanKinetic = M.meanKinetic(end);
stats.finalQx = M.Qx(end);
stats.finalBetaRepairOpt = M.betaRepairOpt(end);
stats.finalBetaRepairDen = M.betaRepairDen(end);
stats.finalRmsRepairDU = M.rmsRepairDU(end);

fprintf('\n=== compare_benchmark_poiseuille_1500 ===\n');
fprintf('nSteps                    : %d\n', prep.params.benchmark_nSteps);
fprintf('final occStd              : %.8g\n', stats.finalOccStd);
fprintf('final outBand             : %.8g\n', stats.finalOutBand);
fprintf('final mean kinetic        : %.8g\n', stats.finalMeanKinetic);
fprintf('final Qx                  : %.8g\n', stats.finalQx);
fprintf('runout finalOccStd        : %s\n', R.finalOccStd);
fprintf('runout finalOutBand       : %s\n', R.finalOutBand);
fprintf('runout finalQx            : %s\n', R.finalQx);
fprintf('final betaRepair opt      : %.8g\n', stats.finalBetaRepairOpt);
fprintf('final betaRepair den      : %.8g\n', stats.finalBetaRepairDen);
fprintf('final rmsRepairDU         : %.8g\n', stats.finalRmsRepairDU);
fprintf('=========================================\n');

figure('Name','benchmark_poiseuille_metrics');
subplot(2,2,1); plot(M.step, M.occStd, 'LineWidth', 1.2); grid on; title('occStd'); xlabel('step');
subplot(2,2,2); plot(M.step, M.outBand, 'LineWidth', 1.2); grid on; title('outBand'); xlabel('step');
subplot(2,2,3); plot(M.step, M.meanKinetic, 'LineWidth', 1.2); grid on; title('mean kinetic'); xlabel('step');
subplot(2,2,4); plot(M.step, M.Qx, 'LineWidth', 1.2); grid on; title('Qx'); xlabel('step');

nSnap = numel(Snaps);
figure('Name','benchmark_poiseuille_snapshots');
for k = 1:nSnap
    subplot(2, nSnap, k);
    imagesc(Snaps(k).cell.Ux);
    axis equal tight; set(gca, 'YDir', 'normal'); colorbar;
    title(sprintf('Ux step %d', Snaps(k).step));
    subplot(2, nSnap, nSnap + k);
    imagesc(Snaps(k).cell.N);
    axis equal tight; set(gca, 'YDir', 'normal'); colorbar;
    title(sprintf('N step %d', Snaps(k).step));
end

figure('Name','benchmark_poiseuille_betarepair_logs');
subplot(2,2,1); semilogy(M.step, max(abs(M.betaRepairDen),1e-30), 'LineWidth', 1.2); grid on; title('abs(betaRepairDen)'); xlabel('step');
subplot(2,2,2); plot(M.step, M.betaRepairOpt, 'LineWidth', 1.2); grid on; title('betaRepairOpt'); xlabel('step');
subplot(2,2,3); plot(M.step, M.rmsRepairDU, 'LineWidth', 1.2); grid on; title('rmsRepairDU'); xlabel('step');
subplot(2,2,4); plot(M.step, M.maxRepairDU, 'LineWidth', 1.2); grid on; title('maxRepairDU'); xlabel('step');

end
