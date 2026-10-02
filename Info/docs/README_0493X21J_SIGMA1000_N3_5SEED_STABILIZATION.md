# 0493x21j — sigma=1000 n=3 five-seed stabilization

Purpose: test whether the x21i INVALID status is caused by insufficient ensemble averaging, without changing any physical or fitting parameter.

Reused completed cases: seeds 4932501, 4933501, 4934501.
New cases only: seeds 4935501, 4936501.
Mode: n=3. sigmaDeclared=1000. amplitudeCells=2.0.

The unchanged x12cal analyzer is applied to the five-seed ensemble with fitPeriods=1.0 and sensitivityPeriods=0.75,1.0,1.25.

Decision rule is unchanged. No solver source is modified and no compilation is performed.

If the five-seed ensemble is PASS, a subsequent runner may complete n=2,n=4. If it remains REVIEW/INVALID, sigma=1000 is not formally qualified under the frozen protocol, even if the central frequency follows sqrt(sigma) well.
