#!/usr/bin/env python3
from __future__ import annotations

import argparse
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


def stats(db: sqlite3.Connection) -> None:
    for table in (
        'milestones', 'symbols', 'symbol_names', 'artifacts', 'relations', 'evidence',
        'raw_params_inventory', 'raw_env_inventory', 'git_commits', 'git_tags',
        'schema_migrations', 'curations_applied',
    ):
        n = db.execute(f'SELECT count(*) FROM {table}').fetchone()[0]
        print(f'{table:24s} {n}')
    print('\nmeta:')
    for r in db.execute('SELECT key,value FROM meta ORDER BY key'):
        print(f"  {r['key']:24s} {r['value']}")


def doctor(db: sqlite3.Connection) -> bool:
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
    print(f'orphan_relations={orphan_rel}')
    return quick == 'ok' and not fk and orphan_rel == 0


def main() -> None:
    info_root = Path(__file__).resolve().parents[1]
    ap = argparse.ArgumentParser(description='Query the SRC_GPU-SURF reference database.')
    ap.add_argument('--db', type=Path, default=info_root / 'db/src_reference.sqlite')
    sub = ap.add_subparsers(dest='command', required=True)
    for name in ('milestone', 'param', 'flag', 'symbol', 'artifact', 'search'):
        p = sub.add_parser(name)
        p.add_argument('query')
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
    elif args.command == 'search': ok = search(db, args.query)
    elif args.command == 'stats': stats(db)
    elif args.command == 'doctor': ok = doctor(db)
    if not ok:
        raise SystemExit(f'Aucun résultat / intégrité non satisfaite pour {args.command}: {getattr(args, "query", "")}')


if __name__ == '__main__':
    main()
