"""Génère docs/rapport_performance.md à partir des DEUX campagnes réelles.
Pas de résultats inventés. Pas de connexion à PostgreSQL pour ce script.
"""
from pathlib import Path
import csv
import json
from statistics import median

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / 'docs'


def load(phase):
    path = DOCS / f'benchmark_{phase}.csv'
    if not path.exists():
        raise SystemExit(f'Mesures manquantes : {path}. Lancer benchmark --phase {phase}')
    with path.open(newline='', encoding='utf-8') as stream:
        rows = list(csv.DictReader(stream))
    return rows


def summarize(rows):
    times = {}
    for query in ['Q1', 'Q2', 'Q3']:
        matches = [r for r in rows if r['query'] == query]
        if len(matches) != 3:
            raise SystemExit(f'Il faut EXACTEMENT 3 mesures par requête ({query})')
        times[query] = median(float(r['execution_ms']) for r in matches)
    return times


def node_types(obj):
    res = []
    if isinstance(obj, dict):
        if 'Node Type' in obj:
            res.append(obj['Node Type'])
            if obj.get('Index Name'):
                res[-1] += f" ({obj['Index Name']})"
        for value in obj.values():
            if isinstance(value, (dict, list)):
                res.extend(node_types(value))
    elif isinstance(obj, list):
        for item in obj:
            res.extend(node_types(item))
    return res


def main():
    before = summarize(load('before'))
    after = summarize(load('after'))
    rows = []
    plan_notes = []
    for q in ['Q1', 'Q2', 'Q3']:
        b, a = before[q], after[q]
        reduction = 100 * (b - a) / b if b else 0
        speedup = b / a if a else float('inf')
        rows.append(f'| {q} | {b:.3f} | {a:.3f} | {reduction:+.1f} % | {speedup:.2f}× |')
        for phase in ['before', 'after']:
            planpath = DOCS / f'plan_{phase}_{q}_run3.json'
            plan = json.loads(planpath.read_text(encoding='utf-8'))
            plan_notes.append(f'- **{q} ({phase})** : ' + ', '.join(node_types(plan['Plan'])[:12]))

    content = '''# Rapport de performance — PostgreSQL (10 millions de lignes)

## Objectif et périmètre

Comparer trois requêtes sur un jeu de données **synthétique** de 10 000 000 de lignes dans
`benchmark.fact_yield_10m`. Les identifiants proviennent de clés valides du modèle Gold ;
la table `gold.fact_yield_daily` d'origine reste inchangée.

Les chiffres ci-dessous proviennent de `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`
exécuté trois fois par requête et par phase sur la machine locale.
Les mesures sont exprimées en **millisecondes de temps d'exécution PostgreSQL**.

## Méthodologie

1. Générer le volume avec `sql/01_generation_volume.sql`.
2. Exécuter `python scripts/02_benchmark.py --phase before` sans les index dédiés.
3. Créer les index et actualiser les statistiques avec `sql/03_index.sql`.
4. Exécuter `python scripts/02_benchmark.py --phase after`, avec les requêtes inchangées.
5. Calculer la **médiane de trois mesures** pour limiter l'effet d'une valeur extrême.
6. Conserver les plans JSON et les mesures CSV dans `docs/`.

Les conditions ne sont pas parfaitement contrôlées (cache disque, chauffage des pages,
charge machine) : la comparaison est indicative, non un benchmark scientifique.

## Résultats

| Requête | Avant (médiane, ms) | Après (médiane, ms) | Réduction du temps | Accélération |
|---|---:|---:|---:|---:|
''' + '\n'.join(rows) + '''

Une réduction **négative** signifie que la requête est plus lente après indexation.
Un index n'est pas toujours utilisé si le planificateur estime qu'un parcours séquentiel est moins coûteux.

## Analyse des plans d'exécution

Principaux nœuds rencontrés (parcours récursif du plan de la troisième mesure) :

''' + '\n'.join(plan_notes) + '''

### Interprétation à compléter après lecture des plans

- **Q1 — classement TVL pour un bucket :** comparer `Seq Scan`, `Index Scan` / `Bitmap Heap Scan`, et `Sort` / `Limit`.
- **Q2 — agrégat par chaîne sur un cycle :** vérifier le filtrage, la jointure vers `dim_chain` et l'agrégation.
- **Q3 — agrégat par protocole sur des buckets :** comparer les accès aux lignes et les jointures vers `dim_project`.
- Dans chaque plan, relever `Actual Rows`, `Rows Removed by Filter`, `Shared Hit Blocks` et `Shared Read Blocks`.
- Indiquer explicitement si les index sont utilisés et pourquoi une requête a progressé ou régressé.

## Index testés

- `idx_bench_bucket_tvl (scenario_bucket, tvl_usd DESC NULLS LAST)`
- `idx_bench_cycle_chain (load_cycle, chain_key) INCLUDE (apy)`
- `idx_bench_bucket_project (scenario_bucket, project_key) INCLUDE (apy)`

Les index consomment de l'espace de stockage et peuvent ralentir les écritures.
Leur utilité doit être jugée **requête par requête**.

## Limites

- Les 10 M de lignes sont des **réplications synthétiques** de faits valides, pas 10 M événements blockchain indépendants.
- `scenario_bucket` et `load_cycle` sont des variables artificielles de benchmark, pas des attributs métier.
- Ne pas utiliser cette table comme source des KPI ou dashboards Power BI réels.
- Les valeurs réelles d'APY/TVL doivent uniquement provenir des tables Gold.

## Traces de reproductibilité

- CSV : `docs/benchmark_before.csv` et `docs/benchmark_after.csv`
- JSON : `docs/plan_before_Q*_run*.json` et `docs/plan_after_Q*_run*.json`
- Génération, requêtes et index : voir le dossier `sql/`.
'''
    target = DOCS / 'rapport_performance.md'
    target.write_text(content, encoding='utf-8')
    print(f'Rapport généré : {target}')


if __name__ == '__main__':
    main()
