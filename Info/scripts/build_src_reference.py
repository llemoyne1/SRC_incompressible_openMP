#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sqlite3
import subprocess
from collections import defaultdict
from pathlib import Path


def merge_text(a: str | None, b: str | None) -> str:
    vals: list[str] = []
    for x in (a, b):
        x = (x or '').strip()
        if x and x not in vals:
            vals.append(x)
    return ' | '.join(vals)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def tex_plain(s: str) -> str:
    s = s.strip()
    replacements = {
        r'\textasciitilde{}': '~', r'\_': '_', r'\%': '%',
        r'\Delta': 'Δ', r'\sigma': 'σ', r'\rho': 'ρ', r'\tau': 'τ', r'\kappa': 'κ',
        r'\simeq': '≈', r'\quad': ' '
    }
    for a, b in replacements.items():
        s = s.replace(a, b)
    for _ in range(4):
        s2 = re.sub(r'\\(?:texttt|textbf|emph|mathrm|mathbf|hbox)\{([^{}]*)\}', r'\1', s)
        if s2 == s:
            break
        s = s2
    s = s.replace('$', '')
    s = re.sub(r'\\[A-Za-z]+\*?(?:\[[^\]]*\])?', '', s)
    s = s.replace('{', '').replace('}', '')
    return re.sub(r'\s+', ' ', s).strip()


def ensure_object(db: sqlite3.Connection, object_id: str, object_type: str, display_name: str, source: str = '') -> None:
    db.execute(
        'INSERT OR IGNORE INTO objects(object_id,object_type,display_name,created_from) VALUES(?,?,?,?)',
        (object_id, object_type, display_name, source),
    )


def reference_milestone_key(mid: str) -> str:
    if re.fullmatch(r'x\d+[A-Za-z0-9-]*', mid):
        return '0493' + mid.lower()
    return 'reference:' + mid


def canonical_mid(mid: str) -> str | None:
    if re.fullmatch(r'x\d+[A-Za-z0-9-]*', mid):
        return '0493' + mid.lower()
    return None


def milestone_nature(name: str, summary: str, status: str) -> str:
    t = ' '.join((name, summary, status)).lower()
    rules = [
        ('ANALYZER', ('analyseur', 'analyse offline', 'pod + sondes')),
        ('CALIBRATOR', ('calibrateur', 'calibration mécanique', 'calibration dynamique')),
        ('BENCHMARK', ('benchmark', 'couette', 'taylor-culick', 'piston', 'impact/splash', 'goutte oscillante')),
        ('DIAGNOSTIC', ('diagnostic', 'audit ', 'télémétrie', 'screening')),
        ('ABLATION', ('ablation', 'rejeté', 'rejetée', 'off production', 'prototype')),
        ('PERF', ('optimisation', 'performance', 'coût', 'cg coopératif', 'déflation')),
        ('FIX', ('correctif', 'fix')),
        ('INFRA', ('infrastructure', 'factorisation', 'registre', 'tooling')),
        ('RUNNER', ('runner',)),
        ('QUALIFICATION', ('qualification', 'qualifie', 'validation')),
    ]
    for nature, keys in rules:
        if any(k in t for k in keys):
            return nature
    return 'CODE'


def milestone_domain(group: str) -> str:
    g = group.lower()
    if 'x14' in g: return 'LIQUID_GAS'
    if 'x13' in g: return 'TRANSPORT_SURFACE'
    if 'x10' in g or 'x12' in g: return 'FREE_SURFACE_KINETICS'
    if 'x9' in g: return 'SURFACE_TENSION'
    if 'x8' in g: return 'OPEN_BOUNDARY'
    if 'x3' in g or 'x7' in g: return 'Q6_GF'
    if 'socle' in g: return 'CORE'
    return 'GENERAL'


def resolve_milestone_label(db: sqlite3.Connection, label: str) -> str | None:
    rows = db.execute(
        'SELECT object_id FROM milestones WHERE lower(milestone_id)=lower(?) OR lower(canonical_id)=lower(?) OR lower(milestone_key)=lower(?)',
        (label, label, label),
    ).fetchall()
    return rows[0][0] if len(rows) == 1 else None


def import_milestones(db: sqlite3.Connection, path: Path) -> int:
    group = ''
    source = path.name
    count = 0
    for lineno, line in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        m = re.search(r'\\rowcolor\{groupgray\}\\multicolumn\{4\}\{l\}\{\\textbf\{(.*)\}\}\\\\', line)
        if m:
            group = tex_plain(m.group(1))
            continue
        if not line.lstrip().startswith(r'\texttt{'):
            continue
        parts = line.rsplit(r'\\', 1)[0].split(' & ')
        if len(parts) != 4:
            continue
        mid, name, summary, status = map(tex_plain, parts)
        db.execute(
            'INSERT INTO raw_milestone_rows VALUES(?,?,?,?,?,?,?,?)',
            (source, lineno, group, mid, name, summary, status, line),
        )
        mkey = reference_milestone_key(mid)
        oid = 'milestone:' + mkey
        ensure_object(db, oid, 'MILESTONE', mid, source)
        confidence = 'C' if mid == 'x1' else 'B'
        db.execute(
            '''INSERT INTO milestones(
                 object_id,milestone_key,milestone_id,canonical_id,group_name,name,summary,
                 nature,domain,status,confidence,source_file,source_row)
               VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)''',
            (oid, mkey, mid, canonical_mid(mid), group, name, summary,
             milestone_nature(name, summary, status), milestone_domain(group), status,
             confidence, source, lineno),
        )
        db.execute(
            'INSERT INTO evidence(object_id,evidence_type,path,line_hint,confidence,notes) VALUES(?,?,?,?,?,?)',
            (oid, 'REFERENCE_TEX', source, str(lineno), confidence, 'Imported from current milestone reference'),
        )
        count += 1
    return count


def split_aliases(text: str) -> list[str]:
    return [x.strip() for x in re.split(r'[;|,]', text or '') if x.strip()]


def upsert_symbol(db: sqlite3.Connection, namespace: str, canonical_name: str, row: dict) -> str:
    oid = f'symbol:{namespace.lower()}:{canonical_name}'
    ensure_object(db, oid, 'SYMBOL', canonical_name, row.get('_source_file', ''))
    incoming = (
        row.get('category', ''), row.get('status', ''), row.get('expected_type', ''),
        row.get('default', ''), row.get('values_constraints', ''), row.get('effect_role', ''),
        row.get('remarks', ''), row.get('source_inventory', ''),
    )
    old = db.execute(
        '''SELECT category,status,expected_type,default_value,constraints_text,effect_role,remarks,source_inventory
           FROM symbols WHERE object_id=?''', (oid,)
    ).fetchone()
    if old:
        merged = tuple(merge_text(old[i], incoming[i]) for i in range(8))
        db.execute(
            '''UPDATE symbols SET category=?,status=?,expected_type=?,default_value=?,constraints_text=?,
               effect_role=?,remarks=?,source_inventory=? WHERE object_id=?''', (*merged, oid)
        )
    else:
        db.execute(
            '''INSERT INTO symbols(object_id,namespace,canonical_name,category,status,expected_type,
               default_value,constraints_text,effect_role,remarks,source_inventory)
               VALUES(?,?,?,?,?,?,?,?,?,?,?)''',
            (oid, namespace, canonical_name, *incoming),
        )
    return oid


def add_symbol_name(db: sqlite3.Connection, oid: str, name: str, kind: str, canonical: bool, source: str, rownum: int) -> None:
    if not name:
        return
    db.execute(
        '''INSERT OR IGNORE INTO symbol_names(symbol_object_id,name,name_kind,is_canonical,source_file,source_row)
           VALUES(?,?,?,?,?,?)''',
        (oid, name, kind, 1 if canonical else 0, source, rownum),
    )


def import_params(db: sqlite3.Connection, path: Path) -> int:
    source = path.name
    count = 0
    with path.open(newline='', encoding='utf-8-sig') as f:
        for rownum, raw in enumerate(csv.DictReader(f), 2):
            db.execute(
                'INSERT INTO raw_params_inventory VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
                (source, rownum, raw['name'], raw['entry_type'], raw['category'], raw['status'],
                 raw['expected_type'], raw['default'], raw['values_constraints'], raw['canonical_field_target'],
                 raw['aliases'], raw['effect_role'], raw['remarks'], raw['sources'], raw['source_inventory']),
            )
            r = dict(raw)
            r['_source_file'] = source
            et = r['entry_type']
            name = r['name']
            target = r['canonical_field_target'].strip()
            if et == 'control_file_key':
                oid = upsert_symbol(db, 'CONTROL', name, r)
                add_symbol_name(db, oid, name, 'CONTROL_KEY', True, source, rownum)
            elif et == 'output_metadata_key':
                oid = upsert_symbol(db, 'OUTPUT', name, r)
                add_symbol_name(db, oid, name, 'OUTPUT_KEY', True, source, rownum)
            elif et in {'script_alias', 'param_or_script_alias', 'params_or_script_alias'} and name.upper() == name and re.search(r'[A-Z]', name):
                oid = upsert_symbol(db, 'ENV', name, r)
                add_symbol_name(db, oid, name, 'RUNNER_ALIAS', True, source, rownum)
            else:
                canon = target or name
                oid = upsert_symbol(db, 'PARAM', canon, r)
                kind = {
                    'params_canonical_field': 'CPP_FIELD',
                    'params_key': 'PARAM_KEY',
                    'kv_param': 'PARAM_KEY',
                    'params_key_pattern': 'PARAM_PATTERN',
                }.get(et, 'PARAM_ALIAS')
                add_symbol_name(db, oid, name, kind, name == canon, source, rownum)
                for alias in split_aliases(r['aliases']):
                    add_symbol_name(db, oid, alias, 'PARAM_ALIAS', False, source, rownum)
            count += 1
    return count


def import_env(db: sqlite3.Connection, path: Path) -> int:
    source = path.name
    count = 0
    with path.open(newline='', encoding='utf-8-sig') as f:
        for rownum, raw in enumerate(csv.DictReader(f), 2):
            db.execute(
                'INSERT INTO raw_env_inventory VALUES(?,?,?,?,?,?,?,?,?,?,?,?)',
                (source, rownum, raw['name'], raw['entry_type'], raw['category'], raw['status'],
                 raw['expected_type'], raw['default'], raw['effect_role'], raw['remarks'], raw['sources'], raw['source_inventory']),
            )
            r = dict(raw)
            r['_source_file'] = source
            r['values_constraints'] = ''
            oid = upsert_symbol(db, 'ENV', r['name'], r)
            kind = 'ENV_FLAG' if r['entry_type'] == 'env_flag' else 'RUNNER_ALIAS'
            add_symbol_name(db, oid, r['name'], kind, True, source, rownum)
            count += 1
    return count


def normalized_name(s: str) -> str:
    return re.sub(r'[^a-z0-9]', '', s.lower())


def infer_env_param_links(db: sqlite3.Connection) -> int:
    params = db.execute("SELECT object_id,canonical_name FROM symbols WHERE namespace='PARAM'").fetchall()
    by_norm: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for oid, name in params:
        by_norm[normalized_name(name)].append((oid, name))
    count = 0
    for eoid, ename, effect, remarks in db.execute(
        "SELECT object_id,canonical_name,effect_role,remarks FROM symbols WHERE namespace='ENV'"
    ):
        candidates: dict[str, tuple[str, str]] = {}
        same = by_norm.get(normalized_name(ename), [])
        if len(same) == 1:
            candidates[same[0][0]] = (same[0][1], 'normalized-name')
        text = ' '.join((effect or '', remarks or ''))
        for poid, pname in params:
            if len(pname) >= 5 and re.search(r'(?<![A-Za-z0-9_])' + re.escape(pname) + r'(?![A-Za-z0-9_])', text, re.I):
                candidates[poid] = (pname, 'effect/remarks')
        for poid, (_, why) in candidates.items():
            db.execute(
                '''INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                   VALUES(?,?,?,?,?)''',
                (eoid, 'SETS_PARAMETER', poid, 'B', why),
            )
            count += 1
    return count


X_MILESTONE_RE = re.compile(
    r'(?i)(?<![A-Za-z0-9])(0493)?(x\d+(?:[a-z]+\d*)?(?:-[a-z0-9]+)*)(?![A-Za-z0-9])'
)
# Historical numeric milestones are contextual, but their suffix grammar evolved:
# 0490A/0491H use a single letter, while later pre-x cycles use letter+index
# forms such as 0493O1 and 0493W8.  Exclude x explicitly: 0493x... belongs to
# the globally identified X family handled by X_MILESTONE_RE above.
NUMERIC_HINT_RE = re.compile(
    r'(?i)(?<!\d)(0\d{3}(?:(?!x)[a-z](?:\d+)?)?(?:(?:-|_)(?:fix\d+|doc))?)(?![A-Za-z0-9])'
)


def normalize_candidate_label(label: str) -> str:
    return label.strip().replace('_', '-').lower()


def extract_candidate_mentions(text: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for m in X_MILESTONE_RE.finditer(text or ''):
        explicit_0493 = bool(m.group(1))
        label = normalize_candidate_label(m.group(2))
        # Bare numeric X tokens such as x0/x1 are common geometric shorthand
        # (e.g. a boundary at x=0) and are not globally unique milestone IDs.
        # Accept them only when Git spells the project milestone explicitly as
        # 0493xN.  Letter-qualified X labels (x7q, x14ai, ...) remain globally
        # recognizable with or without the 0493 prefix.
        core = label.split('-', 1)[0]
        if re.fullmatch(r'x\d+', core, re.I) and not explicit_0493:
            continue
        item = (label, 'X')
        if item not in seen:
            seen.add(item)
            out.append(item)
    for m in NUMERIC_HINT_RE.finditer(text or ''):
        label = normalize_candidate_label(m.group(1))
        item = (label, 'NUMERIC')
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def extract_hints(text: str) -> list[str]:
    return [label for label, _family in extract_candidate_mentions(text)]

def artifact_kind(path: str) -> str:
    b = Path(path).name.lower()
    ext = Path(path).suffix.lower()
    p = path.lower()
    if b.startswith('run') and ext in {'.sh', '.py'}: return 'RUNNER'
    if b.startswith(('analyze', 'analyse')): return 'ANALYZER'
    if b.startswith(('generate', 'prepare')): return 'GENERATOR'
    if b.startswith(('check', 'validate')): return 'CHECKER'
    if b.startswith('build') and ext in {'.sh', '.py', '.m'}: return 'BUILD'
    if 'livevis' in b or b.startswith('play_'): return 'VISUALIZER'
    if p.startswith(('src/', 'include/')): return 'SOURCE'
    if p.startswith(('doc/', 'docs/')) or b.startswith('readme'): return 'DOCUMENTATION'
    if p.startswith('matlab/'): return 'MATLAB_TOOL'
    if p.startswith('tools/'): return 'TOOL'
    if p.startswith('scripts/'): return 'SCRIPT'
    return 'FILE'


def artifact_language(path: str) -> str:
    return {
        '.sh': 'bash', '.py': 'python', '.m': 'matlab', '.cu': 'cuda', '.cpp': 'cpp',
        '.h': 'cpp-header', '.hpp': 'cpp-header', '.md': 'markdown', '.tex': 'latex',
        '.csv': 'csv', '.kv': 'kv',
    }.get(Path(path).suffix.lower(), '')


def scan_artifacts(db: sqlite3.Connection, repo: Path) -> tuple[int, int]:
    count = links = 0
    for dirname in ('scripts', 'matlab', 'src', 'include', 'doc', 'docs', 'examples', 'external_benchmarks', 'tools'):
        root = repo / dirname
        if not root.exists():
            continue
        for path in root.rglob('*'):
            if not path.is_file():
                continue
            rel = path.relative_to(repo).as_posix()
            oid = 'artifact:' + rel
            ensure_object(db, oid, 'ARTIFACT', rel, 'repository-scan')
            hints = extract_hints(rel)
            db.execute(
                '''INSERT OR REPLACE INTO artifacts(object_id,path,basename,kind,language,status,milestone_hint,description,sha256)
                   VALUES(?,?,?,?,?,?,?,?,?)''',
                (oid, rel, path.name, artifact_kind(rel), artifact_language(rel), 'present', ';'.join(hints), '', sha256_file(path)),
            )
            # Only x... identifiers are safe enough for filename-only automatic links.
            # Bare 0xxx identifiers are historically reused and require stronger evidence.
            for hint in hints:
                if not hint.startswith('x'):
                    continue
                moid = resolve_milestone_label(db, hint)
                if moid:
                    db.execute(
                        '''INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                           VALUES(?,?,?,?,?)''',
                        (oid, 'ASSOCIATED_WITH', moid, 'B', 'x-milestone id inferred from artifact filename'),
                    )
                    links += 1
            count += 1
    return count, links


def ensure_artifact_placeholder(db: sqlite3.Connection, path: str, kind: str, status: str, description: str) -> str:
    oid = 'artifact:' + path
    ensure_object(db, oid, 'ARTIFACT', path, 'curated')
    if not db.execute('SELECT 1 FROM artifacts WHERE object_id=?', (oid,)).fetchone():
        db.execute(
            '''INSERT INTO artifacts(object_id,path,basename,kind,language,status,milestone_hint,description,sha256)
               VALUES(?,?,?,?,?,?,?,?,?)''',
            (oid, path, Path(path).name, kind, artifact_language(path), status, '', description, ''),
        )
    return oid


def link_inventory_sources(db: sqlite3.Connection) -> int:
    by_path = {path: oid for path, oid in db.execute('SELECT path,object_id FROM artifacts')}
    by_base: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for path, oid in by_path.items():
        by_base[Path(path).name].append((path, oid))
    count = 0
    queries = [
        ('raw_params_inventory', "name,entry_type,canonical_field_target,sources"),
        ('raw_env_inventory', "name,entry_type,'' AS canonical_field_target,sources"),
    ]
    for table, columns in queries:
        for name, entry_type, target, sources in db.execute(f'SELECT {columns} FROM {table}'):
            if table == 'raw_env_inventory' or (
                entry_type in {'script_alias', 'param_or_script_alias', 'params_or_script_alias'}
                and name.upper() == name and re.search(r'[A-Z]', name)
            ):
                soid = 'symbol:env:' + name
            elif entry_type == 'control_file_key':
                soid = 'symbol:control:' + name
            elif entry_type == 'output_metadata_key':
                soid = 'symbol:output:' + name
            else:
                soid = 'symbol:param:' + (target or name)
            if not db.execute('SELECT 1 FROM objects WHERE object_id=?', (soid,)).fetchone():
                continue
            for token in re.split(r'[;|]', sources or ''):
                token = token.strip()
                if not token:
                    continue
                token = re.sub(r':\d+(?:[-–]\d+)?(?:,\d+(?:[-–]\d+)?)?$', '', token)
                if token == 'simulation_params.h': token = 'include/simulation_params.h'
                if token == 'params_io_base.cpp': token = 'src/params_io_base.cpp'
                aoid = by_path.get(token)
                if not aoid:
                    matches = by_base.get(Path(token).name, [])
                    if len(matches) == 1:
                        aoid = matches[0][1]
                if aoid:
                    db.execute(
                        '''INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                           VALUES(?,?,?,?,?)''',
                        (soid, 'DEFINED_OR_USED_IN', aoid, 'A', token),
                    )
                    count += 1
    return count


def infer_milestone_links(db: sqlite3.Connection) -> int:
    count = 0
    for oid, mid, summary, status in db.execute('SELECT object_id,milestone_id,summary,status FROM milestones'):
        text = ' '.join((summary or '', status or ''))
        for hint in extract_hints(text):
            if not hint.startswith('x') or hint.lower() == mid.lower():
                continue
            target = resolve_milestone_label(db, hint)
            if not target:
                continue
            rel = 'REFERENCES'
            low = text.lower()
            if re.search(r'supplant(?:é|e|ée|és|ées) par\s+' + re.escape(hint), low):
                rel = 'SUPERSEDED_BY'
            elif re.search(r'm[eè]ne à\s+' + re.escape(hint), low):
                rel = 'LEADS_TO'
            db.execute(
                'INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES(?,?,?,?,?)',
                (oid, rel, target, 'C', 'inferred from milestone summary/status'),
            )
            count += 1
    # Stronger structural relation for -fixN names.
    for oid, mid in db.execute("SELECT object_id,milestone_id FROM milestones WHERE milestone_id LIKE '%-fix%'"):
        base = re.sub(r'-fix\d+.*$', '', mid, flags=re.I)
        target = resolve_milestone_label(db, base)
        if target:
            db.execute(
                'INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES(?,?,?,?,?)',
                (oid, 'FIXES', target, 'B', 'fix suffix relationship'),
            )
            count += 1
    return count


def infer_symbol_milestone_links(db: sqlite3.Connection) -> int:
    count = 0
    rows = db.execute(
        "SELECT object_id,namespace,canonical_name,category,status,effect_role,remarks,source_inventory FROM symbols"
    ).fetchall()
    for oid, namespace, name, category, status, effect, remarks, source_inventory in rows:
        text = ' '.join(x or '' for x in (category, status, effect, remarks, source_inventory))
        seen = set()
        for hint in extract_hints(text):
            if not hint.startswith('x'):
                continue
            target = resolve_milestone_label(db, hint)
            if not target or target in seen:
                continue
            seen.add(target)
            db.execute(
                'INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES(?,?,?,?,?)',
                (oid, 'ASSOCIATED_WITH', target, 'B', f'{namespace} metadata mentions {hint}'),
            )
            count += 1
    return count


def git_available(repo: Path) -> bool:
    cp = subprocess.run(
        ['git', '-C', str(repo), 'rev-parse', '--is-inside-work-tree'],
        text=True, capture_output=True,
    )
    return cp.returncode == 0 and cp.stdout.strip().lower() == 'true'


def git_run(repo: Path, args: list[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ['git', '-C', str(repo), *args],
        text=True, capture_output=True, check=check,
    )


def resolve_mainline_ref(repo: Path, requested: str | None) -> str:
    candidates: list[str] = []
    if requested and requested != 'auto':
        candidates.append(requested)
    candidates.extend(['origin/surf', 'surf', 'HEAD'])
    seen: set[str] = set()
    for ref in candidates:
        if ref in seen:
            continue
        seen.add(ref)
        cp = git_run(repo, ['rev-parse', '--verify', '--quiet', f'{ref}^{{commit}}'], check=False)
        if cp.returncode == 0 and cp.stdout.strip():
            return ref
    raise RuntimeError('unable to resolve Git mainline ref (tried requested ref, origin/surf, surf, HEAD)')


def candidate_id_for(label: str, family: str, commit_hash: str | None, anchor_text: str) -> str:
    norm = normalize_candidate_label(label)
    if family == 'X':
        return f'candidate:x:{norm}'
    if commit_hash:
        anchor = 'commit-' + commit_hash[:12]
    else:
        anchor = 'evidence-' + hashlib.sha1(anchor_text.encode('utf-8')).hexdigest()[:12]
    return f'candidate:numeric:{norm}:{anchor}'


def add_git_candidate_evidence(
    db: sqlite3.Connection,
    label: str,
    family: str,
    evidence_type: str,
    confidence: str,
    commit_hash: str | None = None,
    ref_name: str | None = None,
    path: str | None = None,
    evidence_text: str | None = None,
) -> str:
    norm = normalize_candidate_label(label)
    anchor_text = '|'.join(x or '' for x in (evidence_type, ref_name, path, evidence_text))
    cid = candidate_id_for(norm, family, commit_hash, anchor_text)
    linked = resolve_milestone_label(db, norm) if family == 'X' else None
    status = 'LINKED' if linked else 'CANDIDATE'
    db.execute(
        """INSERT OR IGNORE INTO git_milestone_candidates(
             candidate_id,label,normalized_label,candidate_family,anchor_commit,status,linked_milestone_object_id)
           VALUES(?,?,?,?,?,?,?)""",
        (cid, norm, norm, family, commit_hash, status, linked),
    )
    if linked:
        db.execute(
            """UPDATE git_milestone_candidates
               SET status='LINKED', linked_milestone_object_id=COALESCE(linked_milestone_object_id,?)
               WHERE candidate_id=?""",
            (linked, cid),
        )
    db.execute(
        """INSERT INTO git_candidate_evidence(
             candidate_id,evidence_type,commit_hash,ref_name,path,evidence_text,confidence)
           VALUES(?,?,?,?,?,?,?)""",
        (cid, evidence_type, commit_hash, ref_name, path, evidence_text, confidence),
    )
    return cid


def refresh_candidate_rollups(db: sqlite3.Connection) -> None:
    db.execute(
        """UPDATE git_milestone_candidates
           SET evidence_count=(SELECT count(*) FROM git_candidate_evidence e WHERE e.candidate_id=git_milestone_candidates.candidate_id),
               max_confidence=COALESCE((
                 SELECT CASE min(CASE e.confidence WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END)
                          WHEN 1 THEN 'A' WHEN 2 THEN 'B' ELSE 'C' END
                 FROM git_candidate_evidence e WHERE e.candidate_id=git_milestone_candidates.candidate_id
               ),'C'),
               first_date=(
                 SELECT min(c.authored_date) FROM git_candidate_evidence e
                 JOIN git_commits c ON c.hash=e.commit_hash
                 WHERE e.candidate_id=git_milestone_candidates.candidate_id
               ),
               last_date=(
                 SELECT max(c.authored_date) FROM git_candidate_evidence e
                 JOIN git_commits c ON c.hash=e.commit_hash
                 WHERE e.candidate_id=git_milestone_candidates.candidate_id
               ),
               anchor_commit=CASE WHEN candidate_family='X' THEN COALESCE((
                 SELECT e.commit_hash FROM git_candidate_evidence e
                 JOIN git_commits c ON c.hash=e.commit_hash
                 WHERE e.candidate_id=git_milestone_candidates.candidate_id
                   AND e.commit_hash IS NOT NULL
                 ORDER BY c.authored_date ASC,
                          CASE
                            WHEN e.evidence_type='COMMIT_SUBJECT' THEN 1
                            WHEN e.evidence_type='COMMIT_PATH' AND e.evidence_text LIKE 'A %' THEN 2
                            WHEN e.evidence_type='COMMIT_PATH' AND (e.evidence_text LIKE 'R%' OR e.evidence_text LIKE 'C%') THEN 3
                            WHEN e.evidence_type='TAG_NAME' THEN 4
                            ELSE 5
                          END ASC,
                          CASE e.confidence WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END ASC,
                          e.id ASC
                 LIMIT 1
               ), anchor_commit) ELSE anchor_commit END"""
    )



def reconcile_unique_numeric_candidates(db: sqlite3.Connection) -> int:
    """Link curated numeric milestones to their introduction Git candidate conservatively.

    Historical 0xxx labels are not globally unique, so raw numeric candidates are never
    auto-linked during Git import.  After curation, reconciliation uses two safe cases:

    1. exactly one canonical milestone and exactly one NUMERIC candidate share the label;
    2. several candidates share the label, but exactly one of them *introduced the
       source file named by the curation* (README, implementation file or qualification runner).

    Case (2) is important for later documentation snapshots such as
    ``src_mpcd_*_0490p.csv``: those files legitimately mention 0490P but do not create a
    second 0490P milestone.  Conversely, reused labels such as historical/current 0414
    remain unresolved unless the curation supplies a source file whose introduction
    identifies one candidate unambiguously.
    """

    def curated_source_intro_candidates(norm: str, source_file: str) -> list[tuple[str, str | None, str | None]]:
        if not source_file:
            return []
        basename = Path(source_file).name.lower()
        if not basename:
            return []
        rows = db.execute(
            """SELECT DISTINCT c.candidate_id,c.anchor_commit,c.first_date
               FROM git_milestone_candidates c
               JOIN git_candidate_evidence e ON e.candidate_id=c.candidate_id
               WHERE c.candidate_family='NUMERIC'
                 AND c.normalized_label=?
                 AND e.evidence_type='COMMIT_PATH'
                 AND (lower(e.path)=? OR lower(e.path) LIKE ?)""",
            (norm, basename, '%/' + basename),
        ).fetchall()
        return rows

    linked = 0
    rows = db.execute(
        """SELECT lower(m.milestone_id) AS norm, m.object_id, COALESCE(m.source_file,'')
           FROM milestones m
           WHERE m.milestone_id GLOB '[0-9][0-9][0-9][0-9]*'
           GROUP BY lower(m.milestone_id)
           HAVING count(*)=1"""
    ).fetchall()
    for norm, moid, source_file in rows:
        cands = db.execute(
            """SELECT candidate_id,anchor_commit,first_date
               FROM git_milestone_candidates
               WHERE candidate_family='NUMERIC' AND normalized_label=?""",
            (norm,),
        ).fetchall()

        resolution = ''
        chosen: tuple[str, str | None, str | None] | None = None
        if len(cands) == 1:
            chosen = cands[0]
            resolution = 'unique numeric-label curation'
        elif len(cands) > 1:
            intro = curated_source_intro_candidates(norm, source_file)
            if len(intro) == 1:
                chosen = intro[0]
                resolution = 'curated source-file introduction evidence'

        if chosen is None:
            continue

        cid, anchor, first_date = chosen
        db.execute(
            """UPDATE git_milestone_candidates
               SET status='CURATED', linked_milestone_object_id=?,
                   notes=trim(COALESCE(notes,'') || CASE WHEN COALESCE(notes,'')='' THEN '' ELSE '; ' END || ?)
               WHERE candidate_id=?""",
            (moid, 'linked by ' + resolution, cid),
        )
        if anchor:
            coid = 'git:' + anchor
            if db.execute('SELECT 1 FROM objects WHERE object_id=?', (coid,)).fetchone():
                db.execute(
                    """INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                       VALUES(?,?,?,?,?)""",
                    (moid, 'EVIDENCED_BY_COMMIT', coid, 'A', resolution),
                )
                if not db.execute(
                    "SELECT 1 FROM evidence WHERE object_id=? AND evidence_type='GIT_COMMIT' AND commit_hash=?",
                    (moid, anchor),
                ).fetchone():
                    db.execute(
                        "INSERT INTO evidence(object_id,evidence_type,commit_hash,confidence,notes) VALUES(?,?,?,?,?)",
                        (moid, 'GIT_COMMIT', anchor, 'A', resolution),
                    )
        db.execute(
            """UPDATE milestones
               SET introduced_commit=COALESCE(NULLIF(introduced_commit,''),?),
                   introduced_date=COALESCE(NULLIF(introduced_date,''),substr(?,1,10))
               WHERE object_id=?""",
            (anchor, first_date, moid),
        )
        linked += 1

    # V4.24: exact reconciliation for a deliberately reused numeric label.
    # 0414 appears in several historical contexts, so the generic numeric matcher
    # must remain conservative.  The 2026-09-07 surf commit is nevertheless
    # unambiguous: its subject names the segmented x/y generalization and it adds
    # run_0414_segmented_xy_neumann_qualification.sh.  Keep this as an exact triple
    # rather than broadening the numeric-label heuristic.
    exact_reused_numeric = (
        (
            '0414',
            'e2fe1ca29042c2391cd5b6ee7f9eb7fe9a2065a8',
            'milestone:20260907-0414-segmented-xy',
            'exact reused-label curation: 2026-09-07 segmented x/y CUDA-resident 0414',
        ),
    )
    for norm, anchor, moid, resolution in exact_reused_numeric:
        if not db.execute('SELECT 1 FROM milestones WHERE object_id=?', (moid,)).fetchone():
            continue
        row = db.execute(
            """SELECT candidate_id,first_date,status,linked_milestone_object_id
               FROM git_milestone_candidates
               WHERE candidate_family='NUMERIC' AND normalized_label=? AND anchor_commit=?""",
            (norm, anchor),
        ).fetchone()
        if row is None:
            continue
        cid, first_date, old_status, old_link = row
        already = old_status == 'CURATED' and old_link == moid
        db.execute(
            """UPDATE git_milestone_candidates
               SET status='CURATED', linked_milestone_object_id=?,
                   notes=trim(COALESCE(notes,'') ||
                     CASE WHEN instr(COALESCE(notes,''),?)>0 THEN ''
                          WHEN COALESCE(notes,'')='' THEN ? ELSE '; ' || ? END)
               WHERE candidate_id=?""",
            (moid, resolution, 'linked by ' + resolution, 'linked by ' + resolution, cid),
        )
        coid = 'git:' + anchor
        if db.execute('SELECT 1 FROM objects WHERE object_id=?', (coid,)).fetchone():
            db.execute(
                """INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                   VALUES(?,?,?,?,?)""",
                (moid, 'EVIDENCED_BY_COMMIT', coid, 'A', resolution),
            )
            if not db.execute(
                "SELECT 1 FROM evidence WHERE object_id=? AND evidence_type='GIT_COMMIT' AND commit_hash=?",
                (moid, anchor),
            ).fetchone():
                db.execute(
                    "INSERT INTO evidence(object_id,evidence_type,commit_hash,confidence,notes) VALUES(?,?,?,?,?)",
                    (moid, 'GIT_COMMIT', anchor, 'A', resolution),
                )
        db.execute(
            """UPDATE milestones
               SET introduced_commit=COALESCE(NULLIF(introduced_commit,''),?),
                   introduced_date=COALESCE(NULLIF(introduced_date,''),substr(?,1,10))
               WHERE object_id=?""",
            (anchor, first_date, moid),
        )
        if not already:
            linked += 1

    return linked

def import_git_commits(db: sqlite3.Connection, repo: Path) -> tuple[int, int]:
    fmt = '%H%x1f%aI%x1f%cI%x1f%an%x1f%ae%x1f%P%x1f%s'
    cp = git_run(repo, ['log', '--all', f'--format={fmt}'])
    commits = links = 0
    for line in cp.stdout.splitlines():
        parts = line.split('\x1f', 6)
        if len(parts) != 7:
            continue
        commit_hash, authored, committed, author_name, author_email, parents, subject = parts
        parent_count = len([p for p in parents.split() if p])
        db.execute(
            """INSERT OR REPLACE INTO git_commits(
                 hash,authored_date,committed_date,author_name,author_email,subject,parent_count,is_merge)
               VALUES(?,?,?,?,?,?,?,?)""",
            (commit_hash, authored, committed, author_name, author_email, subject, parent_count, int(parent_count > 1)),
        )
        coid = 'git:' + commit_hash
        ensure_object(db, coid, 'GIT_COMMIT', commit_hash[:10] + ' ' + subject, 'git')
        for label, family in extract_candidate_mentions(subject):
            confidence = 'A' if re.search(r'^\s*(?:0493)?' + re.escape(label) + r'(?:\b|[:_ -])', subject, re.I) else 'B'
            add_git_candidate_evidence(
                db, label, family, 'COMMIT_SUBJECT', confidence,
                commit_hash=commit_hash, evidence_text=subject,
            )
            if family == 'X':
                moid = resolve_milestone_label(db, label)
                if moid:
                    db.execute(
                        """INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text)
                           VALUES(?,?,?,?,?)""",
                        (moid, 'EVIDENCED_BY_COMMIT', coid, confidence, subject),
                    )
                    db.execute(
                        'INSERT INTO evidence(object_id,evidence_type,commit_hash,confidence,notes) VALUES(?,?,?,?,?)',
                        (moid, 'GIT_COMMIT', commit_hash, confidence, subject),
                    )
                    links += 1
        commits += 1
    return commits, links


def import_git_commit_files(db: sqlite3.Connection, repo: Path) -> tuple[int, int]:
    """Import changed paths and derive conservative milestone evidence.

    Numeric milestone labels are contextual by design.  A path containing e.g.
    ``0414`` is evidence for a *new* numeric candidate only when that labelled
    path is introduced (A), or when a rename/copy introduces the label in the
    destination name.  Later M/D operations and pure relocations of an already
    labelled path are retained in ``git_commit_files`` but must not manufacture
    fresh candidates.  This prevents README moves and later edits of historical
    runners from becoming false milestones.

    X-family labels remain global identities, so path touches may safely add
    evidence to the existing X candidate.
    """
    cp = git_run(repo, ['log', '--all', '--format=%x1e%H', '--name-status', '--find-renames'])
    count = 0
    skipped_numeric_path_mentions = 0
    for record in cp.stdout.split('\x1e'):
        lines = [line for line in record.splitlines() if line.strip()]
        if not lines:
            continue
        commit_hash = lines[0].strip()
        if not re.fullmatch(r'[0-9a-fA-F]{40}', commit_hash):
            continue
        if not db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
            continue
        for line in lines[1:]:
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            change = parts[0]
            old_path = ''
            if change.startswith(('R', 'C')) and len(parts) >= 3:
                old_path, path = parts[1], parts[2]
            else:
                path = parts[1]
            db.execute(
                'INSERT OR REPLACE INTO git_commit_files(commit_hash,path,change_type,old_path) VALUES(?,?,?,?)',
                (commit_hash, path, change, old_path),
            )
            # Info/ documents the project but must not recursively generate historical candidates.
            if path.startswith('Info/') or old_path.startswith('Info/'):
                count += 1
                continue

            new_mentions = set(extract_candidate_mentions(path))
            old_mentions = set(extract_candidate_mentions(old_path)) if old_path else set()
            mentions = new_mentions | old_mentions
            for label, family in sorted(mentions):
                if family == 'NUMERIC':
                    introduced = False
                    if change.startswith('A') and (label, family) in new_mentions:
                        introduced = True
                    elif change.startswith(('R', 'C')):
                        # A rename/copy only introduces a numeric milestone label
                        # if the destination gains a label absent from the source.
                        introduced = ((label, family) in new_mentions and
                                      (label, family) not in old_mentions)
                    if not introduced:
                        skipped_numeric_path_mentions += 1
                        continue

                base = Path(path).name.lower()
                confidence = 'A' if base.startswith(('readme_' + label.lower(), 'readme-' + label.lower())) else 'B'
                add_git_candidate_evidence(
                    db, label, family, 'COMMIT_PATH', confidence,
                    commit_hash=commit_hash, path=path,
                    evidence_text=f'{change} {old_path + " -> " if old_path else ""}{path}',
                )
            count += 1
    return count, skipped_numeric_path_mentions


def prune_info_only_commit_candidates(db: sqlite3.Connection) -> int:
    info_only = [r[0] for r in db.execute(
        '''SELECT commit_hash FROM git_commit_files
           GROUP BY commit_hash
           HAVING sum(CASE WHEN path NOT LIKE 'Info/%' AND old_path NOT LIKE 'Info/%' THEN 1 ELSE 0 END)=0'''
    ).fetchall()]
    removed = 0
    for commit_hash in info_only:
        cur = db.execute(
            "DELETE FROM git_candidate_evidence WHERE evidence_type='COMMIT_SUBJECT' AND commit_hash=?",
            (commit_hash,),
        )
        removed += cur.rowcount
    db.execute(
        '''DELETE FROM git_milestone_candidates
           WHERE NOT EXISTS (SELECT 1 FROM git_candidate_evidence e WHERE e.candidate_id=git_milestone_candidates.candidate_id)'''
    )
    return removed


def import_git_tags(db: sqlite3.Connection, repo: Path) -> int:
    cp = git_run(
        repo,
        ['for-each-ref', 'refs/tags', '--format=%(refname:short)%00%(objecttype)%00%(*objectname)%00%(objectname)%00%(creatordate:iso-strict)'],
    )
    count = 0
    for line in cp.stdout.splitlines():
        parts = line.split('\x00')
        if len(parts) < 5:
            continue
        tag, object_type, peeled, direct, date = parts[:5]
        commit_hash = peeled or direct
        if not db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
            continue
        tag_type = 'ANNOTATED' if object_type == 'tag' else 'LIGHTWEIGHT'
        message = ''
        if tag_type == 'ANNOTATED':
            msg = git_run(repo, ['for-each-ref', f'refs/tags/{tag}', '--format=%(contents)'], check=False)
            if msg.returncode == 0:
                message = msg.stdout.strip()
        db.execute(
            'INSERT OR REPLACE INTO git_tags(tag,commit_hash,tagged_date,tag_type,tag_message) VALUES(?,?,?,?,?)',
            (tag, commit_hash, date, tag_type, message),
        )
        db.execute(
            """INSERT OR REPLACE INTO git_refs(ref_name,ref_type,commit_hash,remote_name,is_symbolic)
               VALUES(?,?,?,?,0)""",
            (tag, 'TAG', commit_hash, None),
        )
        for label, family in extract_candidate_mentions(tag):
            add_git_candidate_evidence(
                db, label, family, 'TAG_NAME', 'A', commit_hash=commit_hash,
                ref_name=tag, evidence_text=tag,
            )
        for label, family in extract_candidate_mentions(message):
            add_git_candidate_evidence(
                db, label, family, 'TAG_MESSAGE', 'A', commit_hash=commit_hash,
                ref_name=tag, evidence_text=message,
            )
        count += 1
    return count


def import_git_refs(db: sqlite3.Connection, repo: Path) -> tuple[int, int]:
    cp = git_run(
        repo,
        ['for-each-ref', 'refs/heads', 'refs/remotes', '--format=%(refname:short)%00%(refname)%00%(objectname)%00%(symref)'],
    )
    refs: list[tuple[str, str, str, str | None, int]] = []
    for line in cp.stdout.splitlines():
        parts = line.split('\x00')
        if len(parts) < 4:
            continue
        short, full, commit_hash, symref = parts[:4]
        if not db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
            continue
        if full.startswith('refs/remotes/'):
            ref_type = 'REMOTE_BRANCH'
            remote = short.split('/', 1)[0] if '/' in short else None
        else:
            ref_type = 'LOCAL_BRANCH'
            remote = None
        symbolic = int(bool(symref))
        db.execute(
            """INSERT OR REPLACE INTO git_refs(ref_name,ref_type,commit_hash,remote_name,is_symbolic)
               VALUES(?,?,?,?,?)""",
            (short, ref_type, commit_hash, remote, symbolic),
        )
        refs.append((short, ref_type, commit_hash, remote, symbolic))
        if not symbolic:
            for label, family in extract_candidate_mentions(short):
                add_git_candidate_evidence(
                    db, label, family, 'BRANCH_REF', 'C', commit_hash=commit_hash,
                    ref_name=short, evidence_text=short,
                )
    memberships = 0
    for short, _ref_type, _tip, _remote, symbolic in refs:
        if symbolic:
            continue
        revs = git_run(repo, ['rev-list', short], check=False)
        if revs.returncode != 0:
            continue
        for commit_hash in revs.stdout.splitlines():
            if db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
                db.execute(
                    'INSERT OR IGNORE INTO git_commit_refs(commit_hash,ref_name) VALUES(?,?)',
                    (commit_hash, short),
                )
                memberships += 1
    return len(refs), memberships


def audit_git_branches(db: sqlite3.Connection, repo: Path, requested_mainline: str | None) -> tuple[int, int, int, str]:
    mainline = resolve_mainline_ref(repo, requested_mainline)
    mainline_hash = git_run(repo, ['rev-parse', f'{mainline}^{{commit}}']).stdout.strip()
    db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('git_mainline_ref', mainline))
    mainline_commits = git_run(repo, ['rev-list', mainline]).stdout.splitlines()
    for commit_hash in mainline_commits:
        if db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
            db.execute(
                """INSERT OR REPLACE INTO git_commit_mainline_status(
                     commit_hash,mainline_ref,status,observed_branch,notes) VALUES(?,?,?,?,?)""",
                (commit_hash, mainline, 'IN_MAINLINE', mainline, ''),
            )

    remote_rows = db.execute(
        "SELECT ref_name,commit_hash FROM git_refs WHERE ref_type='REMOTE_BRANCH' AND remote_name='origin' AND is_symbolic=0 ORDER BY ref_name"
    ).fetchall()
    rows = remote_rows or db.execute(
        "SELECT ref_name,commit_hash FROM git_refs WHERE ref_type='LOCAL_BRANCH' AND is_symbolic=0 ORDER BY ref_name"
    ).fetchall()
    audited = plus_total = minus_total = 0
    for branch, tip in rows:
        if branch == mainline:
            relation = 'MAINLINE'
            db.execute(
                """INSERT OR REPLACE INTO git_branch_audit(
                     branch_name,tip_commit,mainline_ref,relation_to_mainline,unique_commits,
                     patch_unique_commits,patch_equivalent_commits,notes)
                   VALUES(?,?,?,?,0,0,0,?)""",
                (branch, tip, mainline, relation, 'mainline ref'),
            )
            audited += 1
            continue
        unique_cp = git_run(repo, ['rev-list', f'{mainline}..{branch}'], check=False)
        if unique_cp.returncode != 0:
            db.execute(
                """INSERT OR REPLACE INTO git_branch_audit(
                     branch_name,tip_commit,mainline_ref,relation_to_mainline,notes)
                   VALUES(?,?,?,?,?)""",
                (branch, tip, mainline, 'AUDIT_ERROR', unique_cp.stderr.strip()[:500]),
            )
            audited += 1
            continue
        unique_hashes = [x for x in unique_cp.stdout.splitlines() if x]
        if not unique_hashes:
            db.execute(
                """INSERT OR REPLACE INTO git_branch_audit(
                     branch_name,tip_commit,mainline_ref,relation_to_mainline,unique_commits,
                     patch_unique_commits,patch_equivalent_commits,notes)
                   VALUES(?,?,?,?,0,0,0,?)""",
                (branch, tip, mainline, 'ANCESTOR_OF_MAINLINE', ''),
            )
            audited += 1
            continue
        cherry = git_run(repo, ['cherry', '-v', mainline, branch], check=False)
        if cherry.returncode != 0:
            db.execute(
                """INSERT OR REPLACE INTO git_branch_audit(
                     branch_name,tip_commit,mainline_ref,relation_to_mainline,unique_commits,notes)
                   VALUES(?,?,?,?,?,?)""",
                (branch, tip, mainline, 'AUDIT_ERROR', len(unique_hashes), cherry.stderr.strip()[:500]),
            )
            audited += 1
            continue
        plus = minus = 0
        for line in cherry.stdout.splitlines():
            m = re.match(r'^([+-])\s+([0-9a-fA-F]{40})\s*(.*)$', line)
            if not m:
                continue
            sign, commit_hash, subject = m.groups()
            if sign == '+':
                status = 'UNIQUE_OUTSIDE_MAINLINE'
                plus += 1
            else:
                status = 'PATCH_EQUIVALENT_IN_MAINLINE'
                minus += 1
            db.execute(
                '''INSERT OR REPLACE INTO git_branch_commit_status(branch_name,commit_hash,status,subject)
                   VALUES(?,?,?,?)''',
                (branch, commit_hash, status, subject),
            )
            existing = db.execute(
                'SELECT status FROM git_commit_mainline_status WHERE commit_hash=?', (commit_hash,)
            ).fetchone()
            if not existing or existing[0] != 'IN_MAINLINE':
                final_status = status
                if existing and existing[0] == 'UNIQUE_OUTSIDE_MAINLINE':
                    final_status = existing[0]
                db.execute(
                    """INSERT OR REPLACE INTO git_commit_mainline_status(
                         commit_hash,mainline_ref,status,observed_branch,notes) VALUES(?,?,?,?,?)""",
                    (commit_hash, mainline, final_status, branch, subject),
                )
        placeholders = ','.join('?' for _ in unique_hashes)
        dates = [
            r[0] for r in db.execute(
                f'SELECT authored_date FROM git_commits WHERE hash IN ({placeholders}) AND authored_date IS NOT NULL ORDER BY authored_date',
                unique_hashes,
            ).fetchall()
        ]
        relation = 'PATCH_EQUIVALENT_IN_MAINLINE' if plus == 0 else 'HAS_UNIQUE_PATCHES'
        unclassified = len(unique_hashes) - plus - minus
        note = f'cherry_unclassified={unclassified}' if unclassified else ''
        db.execute(
            """INSERT OR REPLACE INTO git_branch_audit(
                 branch_name,tip_commit,mainline_ref,relation_to_mainline,unique_commits,
                 patch_unique_commits,patch_equivalent_commits,first_unique_date,last_unique_date,notes)
               VALUES(?,?,?,?,?,?,?,?,?,?)""",
            (branch, tip, mainline, relation, len(unique_hashes), plus, minus,
             dates[0] if dates else None, dates[-1] if dates else None, note),
        )
        plus_total += plus
        minus_total += minus
        audited += 1
    return audited, plus_total, minus_total, mainline


def import_git(db: sqlite3.Connection, repo: Path, requested_mainline: str | None) -> dict[str, int | str]:
    if not git_available(repo):
        return {
            'git_commits': 0, 'git_links': 0, 'git_commit_files': 0, 'git_tags': 0,
            'git_refs': 0, 'git_ref_memberships': 0, 'git_branches_audited': 0,
            'git_unique_patches': 0, 'git_patch_equivalent': 0, 'git_candidates': 0,
            'git_candidate_evidence': 0, 'git_info_candidate_evidence_pruned': 0,
            'git_numeric_path_mentions_skipped': 0,
            'git_unique_outside_commits': 0, 'git_patch_equivalent_commits': 0,
            'git_mainline_ref': '', 'git_import_status': 'skipped:no-git-worktree',
        }
    commits, links = import_git_commits(db, repo)
    commit_files, skipped_numeric_paths = import_git_commit_files(db, repo)
    pruned_info_candidates = prune_info_only_commit_candidates(db)
    tags = import_git_tags(db, repo)
    refs, memberships = import_git_refs(db, repo)
    branches, plus, minus, mainline = audit_git_branches(db, repo, requested_mainline)
    refresh_candidate_rollups(db)
    return {
        'git_commits': commits,
        'git_links': links,
        'git_commit_files': commit_files,
        'git_tags': tags,
        'git_refs': db.execute('SELECT count(*) FROM git_refs').fetchone()[0],
        'git_ref_memberships': memberships,
        'git_branches_audited': branches,
        'git_unique_patches': plus,
        'git_patch_equivalent': minus,
        'git_candidates': db.execute('SELECT count(*) FROM git_milestone_candidates').fetchone()[0],
        'git_candidate_evidence': db.execute('SELECT count(*) FROM git_candidate_evidence').fetchone()[0],
        'git_info_candidate_evidence_pruned': pruned_info_candidates,
        'git_numeric_path_mentions_skipped': skipped_numeric_paths,
        'git_unique_outside_commits': db.execute("SELECT count(*) FROM git_commit_mainline_status WHERE status='UNIQUE_OUTSIDE_MAINLINE'").fetchone()[0],
        'git_patch_equivalent_commits': db.execute("SELECT count(*) FROM git_commit_mainline_status WHERE status='PATCH_EQUIVALENT_IN_MAINLINE'").fetchone()[0],
        'git_mainline_ref': mainline,
        'git_import_status': 'imported',
    }

def apply_curations(db: sqlite3.Connection, curations_dir: Path) -> int:
    if not curations_dir.exists():
        return 0
    count = 0
    for path in sorted(curations_dir.glob('*.sql')):
        sql = path.read_text(encoding='utf-8')
        digest = hashlib.sha256(sql.encode('utf-8')).hexdigest()
        db.executescript(sql)
        db.execute(
            'INSERT OR REPLACE INTO curations_applied(name,sha256,applied_utc) VALUES(?,?,?)',
            (path.name, digest, dt.datetime.now(dt.timezone.utc).isoformat()),
        )
        count += 1
    return count


def refresh_search(db: sqlite3.Connection) -> None:
    db.execute('DELETE FROM search_fts')
    for oid, mid, name, summary, status, domain, nature in db.execute(
        'SELECT object_id,milestone_id,name,summary,status,domain,nature FROM milestones'
    ):
        db.execute(
            'INSERT INTO search_fts VALUES(?,?,?,?)',
            (oid, 'MILESTONE', f'{mid} {name}', ' '.join(x or '' for x in (summary, status, domain, nature))),
        )
    for oid, ns, name, cat, status, typ, default, effect, remarks in db.execute(
        '''SELECT object_id,namespace,canonical_name,category,status,expected_type,default_value,effect_role,remarks
           FROM symbols'''
    ):
        aliases = ' '.join(x[0] for x in db.execute('SELECT name FROM symbol_names WHERE symbol_object_id=?', (oid,)))
        db.execute(
            'INSERT INTO search_fts VALUES(?,?,?,?)',
            (oid, 'SYMBOL', f'{name} {aliases}', ' '.join(x or '' for x in (ns, cat, status, typ, default, effect, remarks))),
        )
    for oid, path, kind, hint, description in db.execute(
        'SELECT object_id,path,kind,milestone_hint,description FROM artifacts'
    ):
        db.execute(
            'INSERT INTO search_fts VALUES(?,?,?,?)',
            (oid, 'ARTIFACT', path, ' '.join(x or '' for x in (kind, hint, description))),
        )
    for cid, label, family, status, confidence, count in db.execute(
        'SELECT candidate_id,label,candidate_family,status,max_confidence,evidence_count FROM git_milestone_candidates'
    ):
        ev = ' '.join(
            (x[0] or '') for x in db.execute(
                'SELECT evidence_text FROM git_candidate_evidence WHERE candidate_id=? ORDER BY id LIMIT 12', (cid,)
            )
        )
        db.execute(
            'INSERT INTO search_fts VALUES(?,?,?,?)',
            (cid, 'GIT_CANDIDATE', label, f'{family} {status} confidence={confidence} evidence={count} {ev}'),
        )



def remove_path(path: Path) -> None:
    if not path.exists() and not path.is_symlink():
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()


def atomic_replace_many(pairs: list[tuple[Path, Path]]) -> None:
    """Replace a set of generated files/directories as one rollback-capable batch."""
    installed: list[tuple[Path, Path | None]] = []
    try:
        for tmp, dest in pairs:
            dest.parent.mkdir(parents=True, exist_ok=True)
            backup = dest.with_name(dest.name + '.__bak__')
            remove_path(backup)
            had_dest = dest.exists() or dest.is_symlink()
            if had_dest:
                os.replace(dest, backup)
            try:
                os.replace(tmp, dest)
            except Exception:
                if had_dest and backup.exists():
                    os.replace(backup, dest)
                raise
            installed.append((dest, backup if had_dest else None))
    except Exception:
        for dest, backup in reversed(installed):
            remove_path(dest)
            if backup is not None and backup.exists():
                os.replace(backup, dest)
        raise
    else:
        for _dest, backup in installed:
            if backup is not None:
                remove_path(backup)


def export_dump(db: sqlite3.Connection, path: Path) -> None:
    with path.open('w', encoding='utf-8') as f:
        for line in db.iterdump():
            if line in ('BEGIN TRANSACTION;', 'COMMIT;'):
                continue
            f.write(line + '\n')


def build(args: argparse.Namespace) -> dict[str, int | str]:
    args.db.parent.mkdir(parents=True, exist_ok=True)
    tmp_db = args.db.with_name(args.db.name + '.tmp')
    if tmp_db.exists():
        tmp_db.unlink()
    publish_tmp = None
    if args.publish_dir is not None:
        publish_tmp = args.publish_dir.with_name(args.publish_dir.name + '.__tmp__')
        remove_path(publish_tmp)

    db = sqlite3.connect(tmp_db)
    db.executescript(args.schema.read_text(encoding='utf-8'))
    with db:
        db.execute('INSERT INTO meta VALUES(?,?)', ('schema_version', '4'))
        db.execute('INSERT INTO meta VALUES(?,?)', ('reference_version', 'V4.26'))
        db.execute('INSERT INTO meta VALUES(?,?)', ('built_utc', dt.datetime.now(dt.timezone.utc).isoformat()))
        db.execute('INSERT INTO meta VALUES(?,?)', ('repo_root', '.'))
        db.execute('INSERT INTO meta VALUES(?,?)', ('info_root', repo_relative_label(args.repo_root, args.info_root)))
        db.execute('INSERT INTO meta VALUES(?,?)', ('source_config', repo_relative_label(args.repo_root, args.config)))
        n_milestones = import_milestones(db, args.milestones_tex)
        n_params = import_params(db, args.params_inventory)
        n_env = import_env(db, args.env_inventory)
        n_artifacts, artifact_links = scan_artifacts(db, args.repo_root)
        curations_applied = apply_curations(db, args.curations)
        source_links = link_inventory_sources(db)
        env_links = infer_env_param_links(db)
        milestone_links = infer_milestone_links(db)
        symbol_milestone_links = infer_symbol_milestone_links(db)
        git_stats = import_git(db, args.repo_root, args.mainline_ref)
        git_candidates_reconciled = reconcile_unique_numeric_candidates(db)
        db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('git_import_status', str(git_stats['git_import_status'])))
        refresh_search(db)

    publish_stats: dict[str, int] = {}
    if publish_tmp is not None:
        from publish_src_reference import publish_reference
        publish_stats = publish_reference(db, publish_tmp)

    quick = db.execute('PRAGMA quick_check').fetchone()[0]
    fk = db.execute('PRAGMA foreign_key_check').fetchall()
    if quick != 'ok' or fk:
        db.close()
        raise RuntimeError(f'database integrity failure: quick_check={quick}, fk={fk[:5]}')

    stats = {
        'milestones': db.execute('SELECT count(*) FROM milestones').fetchone()[0],
        'symbols': db.execute('SELECT count(*) FROM symbols').fetchone()[0],
        'symbol_names': db.execute('SELECT count(*) FROM symbol_names').fetchone()[0],
        'artifacts': db.execute('SELECT count(*) FROM artifacts').fetchone()[0],
        'relations': db.execute('SELECT count(*) FROM relations').fetchone()[0],
        'evidence': db.execute('SELECT count(*) FROM evidence').fetchone()[0],
        'raw_params': db.execute('SELECT count(*) FROM raw_params_inventory').fetchone()[0],
        'raw_env': db.execute('SELECT count(*) FROM raw_env_inventory').fetchone()[0],
        **git_stats,
        'git_candidates_reconciled': git_candidates_reconciled,
        'curations_applied': curations_applied,
        'artifact_links': artifact_links,
        'source_links': source_links,
        'env_param_links': env_links,
        'milestone_links': milestone_links,
        'symbol_milestone_links': symbol_milestone_links,
        **publish_stats,
        'quick_check': quick,
        'foreign_key_violations': len(fk),
    }

    dump_tmp = None
    if args.sql_dump:
        args.sql_dump.parent.mkdir(parents=True, exist_ok=True)
        dump_tmp = args.sql_dump.with_name(args.sql_dump.name + '.tmp')
        export_dump(db, dump_tmp)
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
    db.close()
    replacements: list[tuple[Path, Path]] = [(tmp_db, args.db)]
    if dump_tmp:
        replacements.append((dump_tmp, args.sql_dump))
    if publish_tmp is not None:
        replacements.append((publish_tmp, args.publish_dir))
    atomic_replace_many(replacements)
    return stats


def discover_repo_root(info_root: Path) -> Path:
    cp = subprocess.run(
        ['git', '-C', str(info_root), 'rev-parse', '--show-toplevel'],
        text=True, capture_output=True,
    )
    if cp.returncode == 0 and cp.stdout.strip():
        return Path(cp.stdout.strip()).resolve()
    # Snapshot/archive fallback: Info is expected directly under repository root.
    return info_root.parent.resolve()


def repo_relative_label(repo_root: Path, path: Path) -> str:
    try:
        rel = path.resolve().relative_to(repo_root.resolve())
        return '.' if str(rel) == '.' else rel.as_posix()
    except ValueError:
        # Explicit external overrides are allowed, but mark them clearly.
        return f'external:{path.resolve()}'


def load_source_config(path: Path) -> dict[str, str]:
    data = json.loads(path.read_text(encoding='utf-8'))
    required = ('milestones', 'params_inventory', 'env_inventory')
    missing = [k for k in required if not isinstance(data.get(k), str) or not data[k].strip()]
    if missing:
        raise ValueError(f'missing/invalid source config keys: {", ".join(missing)}')
    return data


def resolve_info_path(info_root: Path, value: str | Path) -> Path:
    p = Path(value)
    return p.resolve() if p.is_absolute() else (info_root / p).resolve()


def main() -> None:
    info_root = Path(__file__).resolve().parents[1]
    default_config = info_root / 'reference_sources.json'

    ap = argparse.ArgumentParser(description='Build/update the SRC_GPU-SURF Info reference database atomically.')
    ap.add_argument('--repo-root', type=Path, default=None,
                    help='SRC_GPU-SURF repository root; auto-detected from Git, otherwise parent of Info/.')
    ap.add_argument('--config', type=Path, default=default_config,
                    help='JSON source manifest; relative source paths are resolved from Info/.')
    ap.add_argument('--schema', type=Path, default=None)
    ap.add_argument('--db', type=Path, default=None)
    ap.add_argument('--sql-dump', type=Path, default=None)
    ap.add_argument('--params-inventory', type=Path, default=None)
    ap.add_argument('--env-inventory', type=Path, default=None)
    ap.add_argument('--milestones-tex', type=Path, default=None)
    ap.add_argument('--curations', type=Path, default=None)
    ap.add_argument('--publish-dir', type=Path, default=None,
                    help='Generated human-readable views; default Info/generated/.')
    ap.add_argument('--no-publish', action='store_true',
                    help='Build the database without regenerating Info/generated/.')
    ap.add_argument('--mainline-ref', default='origin/surf',
                    help='Git mainline used for branch audit; falls back to surf then HEAD if unavailable.')
    args = ap.parse_args()

    args.info_root = info_root
    args.config = args.config.resolve()
    cfg = load_source_config(args.config)
    args.repo_root = (args.repo_root.resolve() if args.repo_root else discover_repo_root(info_root))
    args.schema = (args.schema.resolve() if args.schema else info_root / 'db/schema.sql')
    args.db = (args.db.resolve() if args.db else info_root / 'db/src_reference.sqlite')
    args.sql_dump = (args.sql_dump.resolve() if args.sql_dump else info_root / 'db/src_reference_dump.sql')
    args.params_inventory = (args.params_inventory.resolve() if args.params_inventory
                             else resolve_info_path(info_root, cfg['params_inventory']))
    args.env_inventory = (args.env_inventory.resolve() if args.env_inventory
                          else resolve_info_path(info_root, cfg['env_inventory']))
    args.milestones_tex = (args.milestones_tex.resolve() if args.milestones_tex
                           else resolve_info_path(info_root, cfg['milestones']))
    args.curations = (args.curations.resolve() if args.curations else info_root / 'curations')
    if args.no_publish:
        args.publish_dir = None
    else:
        args.publish_dir = (args.publish_dir.resolve() if args.publish_dir else info_root / 'generated')

    required_paths = {
        'repository root': args.repo_root,
        'schema': args.schema,
        'source config': args.config,
        'params inventory': args.params_inventory,
        'env inventory': args.env_inventory,
        'milestones tex': args.milestones_tex,
    }
    missing = [f'{label}: {path}' for label, path in required_paths.items() if not path.exists()]
    if missing:
        raise FileNotFoundError('required reference inputs not found:\n  ' + '\n  '.join(missing))

    stats = build(args)
    print(f'repo_root={args.repo_root}')
    print(f'info_root={info_root}')
    for key, value in stats.items():
        print(f'{key}={value}')


if __name__ == '__main__':
    main()
