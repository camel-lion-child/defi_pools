"""Mesurer 3 requetes via EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON), trois fois.

Executer AVANT indices : python scripts/02_benchmark.py --phase before
Puis APRES indices : python scripts/02_benchmark.py --phase after

Ne publie jamais la chaine de connexion ni le mot de passe.
Les temps mesures sont ceux retournes par PostgreSQL, pas le temps Python.
"""
from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from statistics import median
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / '.env', override=True)
REPORT_DIR = ROOT / 'docs'
SQL_FILE = ROOT / 'sql' / '04_benchmark_queries.sql'


def get_queries():
    raw = SQL_FILE.read_text(encoding='utf-8')
    regex = re.compile(r'^-- name: (Q[1-3])\s*$', re.MULTILINE)
    positions = list(regex.finditer(raw))
    if [m.group(1) for m in positions] != ['Q1', 'Q2', 'Q3']:
        raise ValueError('Les marqueurs Q1, Q2, Q3 de sql/04_benchmark_queries.sql sont manquants')
    queries = {}
    for i, m in enumerate(positions):
        end = positions[i + 1].start() if i + 1 < len(positions) else len(raw)
        query = raw[m.end():end].strip().removesuffix(';').strip()
        if not query.upper().startswith('SELECT '):
            raise ValueError(f'{m.group(1)} doit etre un SELECT')
        queries[m.group(1)] = query
    return queries


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--phase', required=True, choices=['before', 'after'])
    args = parser.parse_args()

    db_name = os.getenv('PGDATABASE', '')
    if db_name != 'defi_pools':
        raise SystemExit('STOP : PGDATABASE doit etre defi_pools dans .env')

    uri = URL.create(
        'postgresql+psycopg', username=os.getenv('PGUSER', 'postgres'),
        password=os.getenv('PGPASSWORD') or None,
        host=os.getenv('PGHOST', '127.0.0.1'),
        port=int(os.getenv('PGPORT', '2018')),
        database=db_name,
    )
    engine = create_engine(uri, pool_pre_ping=True)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    results = []
    with engine.connect() as conn:
        actual_db = conn.execute(text('SELECT current_database()')).scalar_one()
        count = conn.execute(text('SELECT COUNT(*) FROM benchmark.fact_yield_10m')).scalar_one()
        if actual_db != 'defi_pools' or count != 10_000_000:
            raise SystemExit(f'STOP : base={actual_db}, rows={count}; il faut 10 M lignes')

        queries = get_queries()
        for key, query in queries.items():
            trials = []
            for trial in range(1, 4):
                explain = 'EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ' + query
                payload = conn.exec_driver_sql(explain).scalar_one()
                if isinstance(payload, str):
                    payload = json.loads(payload)
                if not isinstance(payload, list) or not payload:
                    raise ValueError(f'Format EXPLAIN inattendu: {type(payload)}')
                plan = payload[0]
                elapsed = float(plan['Execution Time'])
                planning = float(plan.get('Planning Time', 0))
                trials.append(elapsed)
                # Conserver LE PLAN COMPLET pour rendre les analyses verifiables.
                plan_path = REPORT_DIR / f'plan_{args.phase}_{key}_run{trial}.json'
                plan_path.write_text(json.dumps(plan, indent=2, ensure_ascii=False), encoding='utf-8')
                results.append({
                    'phase': args.phase, 'query': key, 'run': trial,
                    'execution_ms': round(elapsed, 3),
                    'planning_ms': round(planning, 3),
                    'plan_root': plan['Plan'].get('Node Type', ''),
                    'plan_file': str(plan_path.relative_to(ROOT))
                })
                print(f'{args.phase:<6} {key} passage {trial} : {elapsed:.3f} ms')
            print(f'      {key} mediane 3 passages : {median(trials):.3f} ms')

    csv_path = REPORT_DIR / f'benchmark_{args.phase}.csv'
    with csv_path.open('w', encoding='utf-8', newline='') as fh:
        writer = csv.DictWriter(fh, fieldnames=list(results[0]))
        writer.writeheader()
        writer.writerows(results)
    engine.dispose()
    print(f'Mesures enregistrees : {csv_path.relative_to(ROOT)}')


if __name__ == '__main__':
    main()
