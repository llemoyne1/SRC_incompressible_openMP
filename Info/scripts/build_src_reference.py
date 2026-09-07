#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import json
import os
import re
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


X_MILESTONE_RE = re.compile(r'(?i)(?:0493)?(x\d+[a-z][a-z0-9-]*)')
NUMERIC_HINT_RE = re.compile(r'(?<!\d)(0\d{3}[A-Za-z0-9_-]*)')


def extract_hints(text: str) -> list[str]:
    out: list[str] = []
    for m in X_MILESTONE_RE.finditer(text):
        x = m.group(1).lower()
        if x not in out:
            out.append(x)
    for m in NUMERIC_HINT_RE.finditer(text):
        x = m.group(1)
        if x not in out:
            out.append(x)
    return out


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


def import_git(db: sqlite3.Connection, repo: Path) -> tuple[int, int, str]:
    if not git_available(repo):
        return 0, 0, 'skipped:no-git-worktree'
    fmt = '%H%x1f%aI%x1f%s'
    cp = subprocess.run(
        ['git', '-C', str(repo), 'log', '--all', f'--format={fmt}'],
        text=True, capture_output=True, check=True,
    )
    commits = links = 0
    for line in cp.stdout.splitlines():
        parts = line.split('\x1f', 2)
        if len(parts) != 3:
            continue
        commit_hash, date, subject = parts
        db.execute('INSERT OR REPLACE INTO git_commits VALUES(?,?,?)', (commit_hash, date, subject))
        coid = 'git:' + commit_hash
        ensure_object(db, coid, 'GIT_COMMIT', commit_hash[:10] + ' ' + subject, 'git')
        for hint in extract_hints(subject):
            if not hint.startswith('x'):
                continue
            moid = resolve_milestone_label(db, hint)
            if moid:
                db.execute(
                    'INSERT OR IGNORE INTO relations(source_object_id,relation_type,target_object_id,confidence,evidence_text) VALUES(?,?,?,?,?)',
                    (moid, 'EVIDENCED_BY_COMMIT', coid, 'B', subject),
                )
                db.execute(
                    'INSERT INTO evidence(object_id,evidence_type,commit_hash,confidence,notes) VALUES(?,?,?,?,?)',
                    (moid, 'GIT_COMMIT', commit_hash, 'B', subject),
                )
                links += 1
        commits += 1
    tags = subprocess.run(
        ['git', '-C', str(repo), 'for-each-ref', 'refs/tags', '--format=%(refname:short)%00%(*objectname)%00%(objectname)%00%(creatordate:iso-strict)'],
        text=True, capture_output=True, check=True,
    )
    for line in tags.stdout.splitlines():
        parts = line.split('\x00')
        if len(parts) < 3:
            continue
        tag, peeled, direct = parts[:3]
        date = parts[3] if len(parts) > 3 else ''
        commit_hash = peeled or direct
        if db.execute('SELECT 1 FROM git_commits WHERE hash=?', (commit_hash,)).fetchone():
            db.execute('INSERT OR REPLACE INTO git_tags VALUES(?,?,?)', (tag, commit_hash, date))
    return commits, links, 'imported'


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
    db = sqlite3.connect(tmp_db)
    db.executescript(args.schema.read_text(encoding='utf-8'))
    with db:
        db.execute('INSERT INTO meta VALUES(?,?)', ('schema_version', '3'))
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
        git_commits, git_links, git_status = import_git(db, args.repo_root)
        db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('git_import_status', git_status))
        refresh_search(db)

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
        'git_commits': db.execute('SELECT count(*) FROM git_commits').fetchone()[0],
        'git_import_status': git_status,
        'curations_applied': curations_applied,
        'artifact_links': artifact_links,
        'source_links': source_links,
        'env_param_links': env_links,
        'milestone_links': milestone_links,
        'symbol_milestone_links': symbol_milestone_links,
        'git_links': git_links,
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
    os.replace(tmp_db, args.db)
    if dump_tmp:
        os.replace(dump_tmp, args.sql_dump)
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
