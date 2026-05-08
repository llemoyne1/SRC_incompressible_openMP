function S = compare_step05_full_step(prep, Sref, Sbase, Sred, Sout, Gref, Gbase, Gred, Gout, Praw, Psmooth, M)
%COMPARE_STEP05_FULL_STEP Inspect tranche 5 full-step outputs.

meanDx0Ref = mean(abs(Sref.x - prep.x0), 1);
meanDv0Ref = mean(abs(Sref.v - prep.v0), 1);
meanDxRefBase = mean(abs(Sbase.x - Sref.x), 1);
meanDvRefBase = mean(abs(Sbase.v - Sref.v), 1);
meanDxBaseRed = mean(abs(Sred.x - Sbase.x), 1);
meanDvBaseRed = mean(abs(Sred.v - Sbase.v), 1);
meanDxRedOut = mean(abs(Sout.x - Sred.x), 1);
meanDvRedOut = mean(abs(Sout.v - Sred.v), 1);

meanVin = mean(prep.v0, 1);
meanVref = mean(Sref.v, 1);
meanVbase = mean(Sbase.v, 1);
meanVred = mean(Sred.v, 1);
meanVout = mean(Sout.v, 1);

meanKEin = mean(0.5*sum(prep.v0.^2,2));
meanKEref = mean(0.5*sum(Sref.v.^2,2));
meanKEbase = mean(0.5*sum(Sbase.v.^2,2));
meanKEred = mean(0.5*sum(Sred.v.^2,2));
meanKEout = mean(0.5*sum(Sout.v.^2,2));

fprintf('\n=== compare_step05_full_step ===\n');
fprintf('mean dx in->ref / ref->base     : [%g, %g] / [%g, %g]\n', meanDx0Ref(1), meanDx0Ref(2), meanDxRefBase(1), meanDxRefBase(2));
fprintf('mean dx base->red / red->out    : [%g, %g] / [%g, %g]\n', meanDxBaseRed(1), meanDxBaseRed(2), meanDxRedOut(1), meanDxRedOut(2));
fprintf('mean dv in->ref / ref->base     : [%g, %g] / [%g, %g]\n', meanDv0Ref(1), meanDv0Ref(2), meanDvRefBase(1), meanDvRefBase(2));
fprintf('mean dv base->red / red->out    : [%g, %g] / [%g, %g]\n', meanDvBaseRed(1), meanDvBaseRed(2), meanDvRedOut(1), meanDvRedOut(2));
fprintf('mean velocity in/ref/base/red/out: [%g,%g] / [%g,%g] / [%g,%g] / [%g,%g] / [%g,%g]\n', ...
    meanVin(1), meanVin(2), meanVref(1), meanVref(2), meanVbase(1), meanVbase(2), meanVred(1), meanVred(2), meanVout(1), meanVout(2));
fprintf('mean kinetic in/ref/base/red/out : %g / %g / %g / %g / %g\n', meanKEin, meanKEref, meanKEbase, meanKEred, meanKEout);
if isstruct(M)
    fprintf('base occStd before / after      : %g / %g\n', str2double(M.base_occStdBefore), str2double(M.base_occStdAfter));
    fprintf('shifted occStd before / after   : %g / %g\n', str2double(M.shifted_occStdBefore), str2double(M.shifted_occStdAfter));
    fprintf('base outBand before / after     : %g / %g\n', str2double(M.base_outBandBefore), str2double(M.base_outBandAfter));
    fprintf('shifted outBand before / after  : %g / %g\n', str2double(M.shifted_outBandBefore), str2double(M.shifted_outBandAfter));
    fprintf('closure betaRepair opt/applied  : %g / %g\n', str2double(M.closure_betaRepairOpt), str2double(M.closure_betaRepairApplied));
    fprintf('closure Pdrive raw/smooth mean  : %g / %g\n', str2double(M.closure_meanPdriveRaw), str2double(M.closure_meanPdrive));
    fprintf('nParticlesMoved total d/s       : %g / %g\n', str2double(M.totalParticlesMovedDense), str2double(M.totalParticlesMovedSparse));
end
fprintf('=================================\n');

figure('Name','tranche5_fullstep_compare');
subplot(2,4,1); imagesc(Gref.N); axis equal tight; set(gca,'YDir','normal'); title('N ref'); colorbar;
subplot(2,4,2); imagesc(Gbase.N); axis equal tight; set(gca,'YDir','normal'); title('N after base'); colorbar;
subplot(2,4,3); imagesc(Gred.N); axis equal tight; set(gca,'YDir','normal'); title('N red'); colorbar;
subplot(2,4,4); imagesc(Gout.P); axis equal tight; set(gca,'YDir','normal'); title('P out'); colorbar;
subplot(2,4,5); imagesc(Praw.A); axis equal tight; set(gca,'YDir','normal'); title('Pdrive raw'); colorbar;
subplot(2,4,6); imagesc(Psmooth.A); axis equal tight; set(gca,'YDir','normal'); title('Pdrive smooth'); colorbar;
subplot(2,4,7); imagesc(Gout.Ux); axis equal tight; set(gca,'YDir','normal'); title('Ux out'); colorbar;
subplot(2,4,8); imagesc(Gout.Uy); axis equal tight; set(gca,'YDir','normal'); title('Uy out'); colorbar;

S = struct();
S.meanDx0Ref = meanDx0Ref;
S.meanDv0Ref = meanDv0Ref;
S.meanDxRefBase = meanDxRefBase;
S.meanDvRefBase = meanDvRefBase;
S.meanDxBaseRed = meanDxBaseRed;
S.meanDvBaseRed = meanDvBaseRed;
S.meanDxRedOut = meanDxRedOut;
S.meanDvRedOut = meanDvRedOut;
S.meanVin = meanVin;
S.meanVout = meanVout;
S.meanKEin = meanKEin;
S.meanKEout = meanKEout;
end
