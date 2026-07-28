#!/usr/bin/env python3
"""CPU reference checks for the 0493o1 greedy split planner."""

from __future__ import annotations

import heapq
import math
import random

SYNTHETIC = 1 << 63


def plan(masses: list[float], target: float, max_splits: int, retain: int | None) -> tuple[list[float], float]:
    total = sum(masses)
    s2 = sum(m * m for m in masses)
    entries = [(-m, i) for i, m in enumerate(masses)]
    entries.sort()
    if retain is not None:
        entries = entries[:retain]
    heapq.heapify(entries)
    parents: list[float] = []
    for j in range(max_splits):
        if total * total >= target * s2:
            break
        neg_m, token = heapq.heappop(entries)
        m = -neg_m
        half = 0.5 * m
        parents.append(m)
        s2 -= 0.5 * m * m
        heapq.heappush(entries, (-half, SYNTHETIC | j))
        heapq.heappush(entries, (-half, token))
        if retain is not None and len(entries) > retain:
            entries = heapq.nsmallest(retain, entries)
            heapq.heapify(entries)
    return parents, s2


def check_planner() -> None:
    rng = random.Random(49301)
    for _ in range(20_000):
        n = rng.randint(1, 96)
        max_splits = rng.randint(1, 24)
        target = float(rng.randint(2, 24))
        masses = [10.0 ** rng.uniform(-4.0, 2.0) for _ in range(n)]
        full_parents, full_s2 = plan(masses, target, max_splits, None)
        kept_parents, kept_s2 = plan(masses, target, max_splits, max_splits + 1)
        if full_parents != kept_parents or not math.isclose(full_s2, kept_s2, rel_tol=1e-14, abs_tol=1e-14):
            raise AssertionError("retained top-(maxSplits+1) plan differs from full greedy heap")


def check_split_invariants() -> None:
    rng = random.Random(49302)
    for _ in range(20_000):
        m = 10.0 ** rng.uniform(-8.0, 8.0)
        vx = rng.uniform(-1.0e4, 1.0e4)
        vy = rng.uniform(-1.0e4, 1.0e4)
        half = 0.5 * m
        mass_after = half + half
        px_before, py_before = m * vx, m * vy
        px_after, py_after = half * vx + half * vx, half * vy + half * vy
        e_before = 0.5 * m * (vx * vx + vy * vy)
        e_after = 2.0 * 0.5 * half * (vx * vx + vy * vy)
        assert math.isclose(mass_after, m, rel_tol=1e-15, abs_tol=0.0)
        assert math.isclose(px_after, px_before, rel_tol=1e-15, abs_tol=1e-15)
        assert math.isclose(py_after, py_before, rel_tol=1e-15, abs_tol=1e-15)
        assert math.isclose(e_after, e_before, rel_tol=1e-15, abs_tol=1e-15)


if __name__ == "__main__":
    check_planner()
    check_split_invariants()
    print("[0493o1-reference] planner and split invariants: PASS")
