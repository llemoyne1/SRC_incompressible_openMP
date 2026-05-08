function S = compare_step04_liquid_closure(prep, Gref, Gred, Grepair, Gout, Praw, Psmooth, duRepairX, duRepairY, duEOSX, duEOSY, M, xOut, vOut)
%COMPARE_STEP04_LIQUID_CLOSURE Inspect tranche 4 liquid-closure outputs.

if nargin < 13
    error('compare_step04_liquid_closure requires prep, fields, grids, runout, xOut, vOut.');
end

meanDx = mean(abs(xOut - prep.xRed0), 1);
meanDv = mean(abs(vOut - prep.vRed0), 1);
meanVref = mean(prep.vRef0, 1);
meanVred = mean(prep.vRed0, 1);
meanVout = mean(vOut, 1);
meanKEref = mean(0.5*sum(prep.vRef0.^2,2));
meanKEred = mean(0.5*sum(prep.vRed0.^2,2));
meanKEout = mean(0.5*sum(vOut.^2,2));

fprintf('\n=== compare_step04_liquid_closure ===\n');
fprintf('mean dx red -> out             : [%g, %g]\n', meanDx(1), meanDx(2));
fprintf('mean dv red -> out             : [%g, %g]\n', meanDv(1), meanDv(2));
fprintf('mean velocity ref/red/out      : [%g, %g] / [%g, %g] / [%g, %g]\n', ...
    meanVref(1), meanVref(2), meanVred(1), meanVred(2), meanVout(1), meanVout(2));
fprintf('mean kinetic energy ref/red/out: %g / %g / %g\n', meanKEref, meanKEred, meanKEout);
fprintf('mean Pdrive raw / smooth       : %g / %g\n', mean(Praw.A(:)), mean(Psmooth.A(:)));
fprintf('repair rms/max grid norm       : %g / %g\n', ...
    sqrt(mean((duRepairX.A(:).^2 + duRepairY.A(:).^2))), ...
    max(sqrt(duRepairX.A(:).^2 + duRepairY.A(:).^2)));
fprintf('EOS rms/max grid norm          : %g / %g\n', ...
    sqrt(mean((duEOSX.A(:).^2 + duEOSY.A(:).^2))), ...
    max(sqrt(duEOSX.A(:).^2 + duEOSY.A(:).^2)));
if isstruct(M)
    if isfield(M, 'betaRepairApplied')
        fprintf('betaRepair opt / applied       : %g / %g\n', str2double(M.betaRepairOpt), str2double(M.betaRepairApplied));
    end
    if isfield(M, 'nMaskedInterzoneCells')
        fprintf('nMaskedInterzoneCells          : %g\n', str2double(M.nMaskedInterzoneCells));
    end
end
fprintf('======================================\n');

figure('Name','tranche4_liquidclosure_fields');
subplot(2,3,1); imagesc(Gref.P); axis equal tight; set(gca,'YDir','normal'); title('P ref'); colorbar;
subplot(2,3,2); imagesc(Gred.P); axis equal tight; set(gca,'YDir','normal'); title('P red'); colorbar;
subplot(2,3,3); imagesc(Gout.P); axis equal tight; set(gca,'YDir','normal'); title('P out'); colorbar;
subplot(2,3,4); imagesc(Praw.A); axis equal tight; set(gca,'YDir','normal'); title('Pdrive raw'); colorbar;
subplot(2,3,5); imagesc(Psmooth.A); axis equal tight; set(gca,'YDir','normal'); title('Pdrive smooth'); colorbar;
subplot(2,3,6); imagesc(sqrt(duEOSX.A.^2 + duEOSY.A.^2)); axis equal tight; set(gca,'YDir','normal'); title('|duEOS|'); colorbar;

S = struct();
S.meanDx = meanDx;
S.meanDv = meanDv;
S.meanVref = meanVref;
S.meanVred = meanVred;
S.meanVout = meanVout;
S.meanKEref = meanKEref;
S.meanKEred = meanKEred;
S.meanKEout = meanKEout;
end
