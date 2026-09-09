#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import sqlite3
from pathlib import Path


def open_db(path: Path) -> sqlite3.Connection:
    db = sqlite3.connect(path)
    db.row_factory = sqlite3.Row
    return db


def show_relations(db: sqlite3.Connection, object_id: str, limit: int = 80) -> None:
    outgoing = db.execute(
        '''SELECT r.relation_type,r.confidence,o.object_type,o.display_name,o.object_id
           FROM relations r JOIN objects o ON o.object_id=r.target_object_id
           WHERE r.source_object_id=? ORDER BY r.relation_type,o.display_name LIMIT ?''',
        (object_id, limit),
    ).fetchall()
    incoming = db.execute(
        '''SELECT r.relation_type,r.confidence,o.object_type,o.display_name,o.object_id
           FROM relations r JOIN objects o ON o.object_id=r.source_object_id
           WHERE r.target_object_id=? ORDER BY r.relation_type,o.display_name LIMIT ?''',
        (object_id, limit),
    ).fetchall()
    if outgoing:
        print('\nRelations sortantes:')
        for r in outgoing:
            print(f"  {r['relation_type']:24s} -> [{r['object_type']}] {r['display_name']} ({r['confidence']})")
    if incoming:
        print('\nRelations entrantes:')
        for r in incoming:
            print(f"  [{r['object_type']}] {r['display_name']} --{r['relation_type']}--> ({r['confidence']})")


def query_milestone(db: sqlite3.Connection, q: str) -> bool:
    rows = db.execute(
        '''SELECT * FROM milestones
           WHERE lower(milestone_id)=lower(?) OR lower(canonical_id)=lower(?) OR lower(milestone_key)=lower(?)
           ORDER BY confidence DESC,milestone_key''',
        (q, q, q),
    ).fetchall()
    if not rows:
        return False
    if len(rows) > 1:
        print(f'Label de jalon ambigu: {q!r}. Utiliser la clé/canonical_id:')
        for r in rows:
            print(f"  {r['milestone_key']:38s} {r['milestone_id']:14s} {r['name']}")
        return True
    r = rows[0]
    print(f"{r['milestone_id']} — {r['name']}")
    print(f"Key        : {r['milestone_key']}")
    print(f"ID canon.  : {r['canonical_id'] or '-'}")
    print(f"Nature     : {r['nature'] or '-'}")
    print(f"Domaine    : {r['domain'] or '-'}")
    print(f"Statut     : {r['status'] or '-'}")
    print(f"Confiance  : {r['confidence']}")
    print(f"Cycle      : {r['group_name'] or '-'}")
    print(f"Fonction   : {r['summary'] or '-'}")
    if r['introduced_date']:
        print(f"Date       : {r['introduced_date']}")
    if r['source_file']:
        print(f"Source     : {r['source_file']}{':' + str(r['source_row']) if r['source_row'] else ''}")
    show_relations(db, r['object_id'])
    return True


def query_symbol(db: sqlite3.Connection, q: str, namespace: str | None = None) -> bool:
    sql = '''SELECT DISTINCT s.* FROM symbols s
             LEFT JOIN symbol_names n ON n.symbol_object_id=s.object_id
             WHERE (lower(s.canonical_name)=lower(?) OR lower(n.name)=lower(?))'''
    params: list[object] = [q, q]
    if namespace:
        sql += ' AND s.namespace=?'
        params.append(namespace)
    sql += ' ORDER BY s.namespace,s.canonical_name'
    rows = db.execute(sql, params).fetchall()
    if not rows:
        return False
    for i, r in enumerate(rows):
        if i:
            print('\n' + '-' * 78)
        print(f"{r['canonical_name']} [{r['namespace']}]")
        print(f"Catégorie  : {r['category'] or '-'}")
        print(f"Statut     : {r['status'] or '-'}")
        print(f"Type       : {r['expected_type'] or '-'}")
        print(f"Défaut     : {r['default_value'] or '-'}")
        print(f"Contraintes: {r['constraints_text'] or '-'}")
        print(f"Rôle       : {r['effect_role'] or '-'}")
        if r['remarks']:
            print(f"Remarques  : {r['remarks']}")
        names = db.execute(
            '''SELECT name,name_kind,is_canonical FROM symbol_names
               WHERE symbol_object_id=? ORDER BY is_canonical DESC,name_kind,name''',
            (r['object_id'],),
        ).fetchall()
        if names:
            print('Noms       : ' + ', '.join(f"{x['name']} ({x['name_kind']})" for x in names))
        show_relations(db, r['object_id'])
    return True


def query_artifact(db: sqlite3.Connection, q: str) -> bool:
    rows = db.execute(
        '''SELECT * FROM artifacts
           WHERE lower(path)=lower(?) OR lower(basename)=lower(?) OR lower(path) LIKE lower(?)
           ORDER BY path LIMIT 80''',
        (q, q, '%' + q + '%'),
    ).fetchall()
    if not rows:
        return False
    for r in rows:
        print(f"{r['path']} [{r['kind']}] lang={r['language'] or '-'} status={r['status'] or '-'} hint={r['milestone_hint'] or '-'}")
        show_relations(db, r['object_id'], limit=30)
    return True


def query_candidate(db: sqlite3.Connection, q: str) -> bool:
    norm = q.strip().replace('_', '-').lower()
    rows = db.execute(
        '''SELECT c.*, gc.subject AS anchor_subject
           FROM git_milestone_candidates c
           LEFT JOIN git_commits gc ON gc.hash=c.anchor_commit
           WHERE lower(c.normalized_label)=lower(?) OR lower(c.candidate_id)=lower(?)
           ORDER BY c.max_confidence,c.first_date,c.candidate_id''',
        (norm, q),
    ).fetchall()
    if not rows:
        return False
    if len(rows) > 1:
        print(f"{len(rows)} candidats pour le label {q!r}; les labels numériques restent volontairement contextualisés:")
    for i, r in enumerate(rows):
        if i:
            print('\n' + '-' * 90)
        print(f"{r['candidate_id']}")
        print(f"Label      : {r['label']} [{r['candidate_family']}]")
        print(f"Statut     : {r['status']}")
        print(f"Confiance  : {r['max_confidence']}")
        print(f"Preuves    : {r['evidence_count']}")
        print(f"Ancre      : {r['anchor_commit'] or '-'}")
        if r['anchor_subject']:
            print(f"Commit     : {r['anchor_subject']}")
        print(f"Dates      : {r['first_date'] or '-'} -> {r['last_date'] or '-'}")
        if r['linked_milestone_object_id']:
            linked = db.execute(
                'SELECT milestone_key,milestone_id,name FROM milestones WHERE object_id=?',
                (r['linked_milestone_object_id'],),
            ).fetchone()
            if linked:
                print(f"Lié à      : {linked['milestone_key']} ({linked['milestone_id']} — {linked['name']})")
        ev = db.execute(
            '''SELECT e.*, c.subject FROM git_candidate_evidence e
               LEFT JOIN git_commits c ON c.hash=e.commit_hash
               WHERE e.candidate_id=? ORDER BY
                 CASE e.confidence WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END,
                 e.evidence_type,e.id''',
            (r['candidate_id'],),
        ).fetchall()
        for e in ev[:80]:
            where = []
            if e['commit_hash']: where.append(e['commit_hash'][:10])
            if e['ref_name']: where.append(e['ref_name'])
            if e['path']: where.append(e['path'])
            loc = ' | '.join(where) or '-'
            text = (e['evidence_text'] or e['subject'] or '').replace('\n', ' ')[:220]
            print(f"  [{e['confidence']}] {e['evidence_type']:16s} {loc} :: {text}")
    return True


def query_commit(db: sqlite3.Connection, q: str) -> bool:
    rows = db.execute(
        '''SELECT c.*, s.status AS mainline_status,s.mainline_ref,s.observed_branch,s.notes AS mainline_notes
           FROM git_commits c LEFT JOIN git_commit_mainline_status s ON s.commit_hash=c.hash
           WHERE c.hash LIKE ? ORDER BY c.authored_date''',
        (q + '%',),
    ).fetchall()
    if not rows:
        return False
    if len(rows) > 1:
        print(f"Préfixe ambigu {q!r}: {len(rows)} commits")
    for r in rows:
        print(f"{r['hash']}  {r['subject']}")
        print(f"Auteur     : {r['author_name'] or '-'} <{r['author_email'] or '-'}>")
        print(f"Date       : {r['authored_date'] or '-'}")
        print(f"Mainline   : {r['mainline_status'] or 'NON_CLASSIFIE'} ({r['mainline_ref'] or '-'})")
        if r['observed_branch']:
            print(f"Observé via: {r['observed_branch']}")
        refs = [x[0] for x in db.execute(
            'SELECT ref_name FROM git_commit_refs WHERE commit_hash=? ORDER BY ref_name', (r['hash'],)
        )]
        if refs:
            print('Refs       : ' + ', '.join(refs[:40]))
        files = db.execute(
            'SELECT change_type,old_path,path FROM git_commit_files WHERE commit_hash=? ORDER BY path LIMIT 120',
            (r['hash'],),
        ).fetchall()
        if files:
            print('Fichiers   :')
            for f in files:
                move = f"{f['old_path']} -> " if f['old_path'] else ''
                print(f"  {f['change_type']:6s} {move}{f['path']}")
        cand = db.execute(
            '''SELECT DISTINCT c.candidate_id,c.label,c.max_confidence
               FROM git_candidate_evidence e JOIN git_milestone_candidates c ON c.candidate_id=e.candidate_id
               WHERE e.commit_hash=? ORDER BY c.label,c.candidate_id''',
            (r['hash'],),
        ).fetchall()
        if cand:
            print('Candidats  : ' + ', '.join(f"{x['label']}[{x['max_confidence']}]" for x in cand))
    return True


def query_branch(db: sqlite3.Connection, q: str) -> bool:
    rows = db.execute(
        '''SELECT * FROM git_branch_audit
           WHERE lower(branch_name)=lower(?) OR lower(branch_name) LIKE lower(?)
           ORDER BY branch_name''',
        (q, '%' + q + '%'),
    ).fetchall()
    if not rows:
        return False
    for i, r in enumerate(rows):
        if i:
            print('\n' + '-' * 90)
        print(r['branch_name'])
        print(f"Relation   : {r['relation_to_mainline']} -> {r['mainline_ref']}")
        print(f"Tip        : {r['tip_commit'] or '-'}")
        print(f"Hors arbre : {r['unique_commits']}")
        print(f"Patch +    : {r['patch_unique_commits']}")
        print(f"Patch equiv: {r['patch_equivalent_commits']}")
        print(f"Dates      : {r['first_unique_date'] or '-'} -> {r['last_unique_date'] or '-'}")
        if r['notes']:
            print(f"Notes      : {r['notes']}")
        unique = db.execute(
            '''SELECT c.hash,c.authored_date,c.subject,s.status
               FROM git_branch_commit_status s JOIN git_commits c ON c.hash=s.commit_hash
               WHERE s.branch_name=?
               ORDER BY c.authored_date,c.hash LIMIT 120''',
            (r['branch_name'],),
        ).fetchall()
        for c in unique:
            mark = '+' if c['status'] == 'UNIQUE_OUTSIDE_MAINLINE' else '-'
            print(f"  {mark} {c['hash'][:10]} {c['subject']}")
    return True


def list_branches(db: sqlite3.Connection) -> bool:
    rows = db.execute(
        '''SELECT * FROM git_branch_audit ORDER BY
             CASE relation_to_mainline
               WHEN 'HAS_UNIQUE_PATCHES' THEN 1
               WHEN 'PATCH_EQUIVALENT_IN_MAINLINE' THEN 2
               WHEN 'ANCESTOR_OF_MAINLINE' THEN 3
               WHEN 'MAINLINE' THEN 4 ELSE 5 END,
             branch_name'''
    ).fetchall()
    if not rows:
        return False
    print(f"{'branch':58s} {'relation':30s} {'tree':>5s} {'+':>4s} {'-':>4s}")
    for r in rows:
        print(f"{r['branch_name'][:58]:58s} {r['relation_to_mainline'][:30]:30s} "
              f"{r['unique_commits']:5d} {r['patch_unique_commits']:4d} {r['patch_equivalent_commits']:4d}")
    return True

def search(db: sqlite3.Connection, q: str) -> bool:
    terms = [t for t in q.split() if t]
    if not terms:
        return False
    fts_q = ' '.join(t.replace('"', '') + '*' for t in terms)
    rows = db.execute(
        '''SELECT object_id,object_type,title,highlight(search_fts,3,'[',']') AS body
           FROM search_fts WHERE search_fts MATCH ? LIMIT 50''',
        (fts_q,),
    ).fetchall()
    for r in rows:
        print(f"[{r['object_type']}] {r['title']}\n  {(r['body'] or '')[:260]}")
    return bool(rows)



def list_publications(info_root: Path) -> bool:
    root = info_root / 'generated'
    if not root.exists():
        return False
    files = [p for p in root.rglob('*') if p.is_file()]
    if not files:
        return False
    for p in sorted(files):
        print(p.relative_to(info_root).as_posix())
    return True


def stats(db: sqlite3.Connection) -> None:
    for table in (
        'milestones', 'symbols', 'symbol_names', 'artifacts', 'relations', 'evidence',
        'raw_params_inventory', 'raw_env_inventory', 'git_commits', 'git_tags',
        'git_refs', 'git_commit_refs', 'git_commit_files', 'git_commit_mainline_status',
        'git_branch_audit', 'git_branch_commit_status', 'git_milestone_candidates', 'git_candidate_evidence',
        'schema_migrations', 'curations_applied',
    ):
        n = db.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
        print(f'{table:24s} {n}')
    print('\nmeta:')
    for r in db.execute('SELECT key,value FROM meta ORDER BY key'):
        print(f"  {r['key']:24s} {r['value']}")


def doctor(db: sqlite3.Connection, info_root: Path) -> bool:
    quick = db.execute('PRAGMA quick_check').fetchone()[0]
    fk = db.execute('PRAGMA foreign_key_check').fetchall()
    orphan_rel = db.execute(
        '''SELECT count(*) FROM relations r
           LEFT JOIN objects s ON s.object_id=r.source_object_id
           LEFT JOIN objects t ON t.object_id=r.target_object_id
           WHERE s.object_id IS NULL OR t.object_id IS NULL'''
    ).fetchone()[0]
    print(f'quick_check={quick}')
    print(f'foreign_key_violations={len(fk)}')
    orphan_candidates = db.execute(
        '''SELECT count(*) FROM git_candidate_evidence e
           LEFT JOIN git_milestone_candidates c ON c.candidate_id=e.candidate_id
           WHERE c.candidate_id IS NULL'''
    ).fetchone()[0]
    orphan_git_files = db.execute(
        '''SELECT count(*) FROM git_commit_files f
           LEFT JOIN git_commits c ON c.hash=f.commit_hash WHERE c.hash IS NULL'''
    ).fetchone()[0]
    print(f'orphan_relations={orphan_rel}')
    print(f'orphan_candidate_evidence={orphan_candidates}')
    orphan_branch_status = db.execute(
        '''SELECT count(*) FROM git_branch_commit_status s
           LEFT JOIN git_refs r ON r.ref_name=s.branch_name
           LEFT JOIN git_commits c ON c.hash=s.commit_hash
           WHERE r.ref_name IS NULL OR c.hash IS NULL'''
    ).fetchone()[0]
    print(f'orphan_git_files={orphan_git_files}')
    print(f'orphan_branch_commit_status={orphan_branch_status}')

    generated = info_root / 'generated'
    expected = {
        'jalons': (generated / 'csv/jalons.csv', db.execute('SELECT count(*) FROM milestones').fetchone()[0]),
        'lexique_jalons': (generated / 'csv/lexique_jalons.csv', db.execute('SELECT count(*) FROM milestones').fetchone()[0]),
        'parametres': (generated / 'csv/parametres.csv', db.execute("SELECT count(*) FROM symbols WHERE namespace='PARAM'").fetchone()[0]),
        'flags': (generated / 'csv/flags.csv', db.execute("SELECT count(*) FROM symbols WHERE namespace='ENV'").fetchone()[0]),
    }
    publication_ok = True
    for label, (path, expected_rows) in expected.items():
        if not path.exists():
            print(f'publication_{label}=MISSING')
            publication_ok = False
            continue
        with path.open(newline='', encoding='utf-8') as f:
            actual_rows = max(0, sum(1 for _ in csv.reader(f)) - 1)
        ok = actual_rows == expected_rows
        print(f'publication_{label}_rows={actual_rows} expected={expected_rows} status={"ok" if ok else "MISMATCH"}')
        publication_ok = publication_ok and ok
    required_docs = [
        'README.md','lexique_jalons.md','jalons.md','jalons_par_nature.md','parametres.md','flags.md',
        'cles_controle_sorties.md','artefacts.md','audit_candidats_git.md'
    ]
    missing_docs = [name for name in required_docs if not (generated / name).exists()]
    print(f'publication_missing_docs={len(missing_docs)}')
    if missing_docs:
        print('publication_missing_list=' + ','.join(missing_docs))
        publication_ok = False

    return (quick == 'ok' and not fk and orphan_rel == 0 and orphan_candidates == 0
            and orphan_git_files == 0 and orphan_branch_status == 0 and publication_ok)


def main() -> None:
    info_root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description='Query the SRC_GPU-SURF reference database.')
    ap.add_argument('--db', type=Path, default=info_root / 'db/src_reference.sqlite')
    sub = ap.add_subparsers(dest='command', required=True)
    for name in ('milestone', 'param', 'flag', 'symbol', 'artifact', 'candidate', 'commit', 'branch', 'search'):
        p = sub.add_parser(name)
        p.add_argument('query')
    sub.add_parser('branches')
    sub.add_parser('publications')
    sub.add_parser('stats')
    sub.add_parser('doctor')
    args = ap.parse_args()
    db = open_db(args.db)
    ok = True
    if args.command == 'milestone': ok = query_milestone(db, args.query)
    elif args.command == 'param': ok = query_symbol(db, args.query, 'PARAM')
    elif args.command == 'flag': ok = query_symbol(db, args.query, 'ENV')
    elif args.command == 'symbol': ok = query_symbol(db, args.query, None)
    elif args.command == 'artifact': ok = query_artifact(db, args.query)
    elif args.command == 'candidate': ok = query_candidate(db, args.query)
    elif args.command == 'commit': ok = query_commit(db, args.query)
    elif args.command == 'branch': ok = query_branch(db, args.query)
    elif args.command == 'search': ok = search(db, args.query)
    elif args.command == 'branches': ok = list_branches(db)
    elif args.command == 'publications': ok = list_publications(info_root)
    elif args.command == 'stats': stats(db)
    elif args.command == 'doctor': ok = doctor(db, info_root)
    if not ok:
        raise SystemExit(f'Aucun résultat / intégrité non satisfaite pour {args.command}: {getattr(args, "query", "")}')


if __name__ == '__main__':
    main()
