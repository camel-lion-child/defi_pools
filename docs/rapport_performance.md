# Rapport de performance — PostgreSQL (10 millions de lignes)

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
| Q1 | 1371.604 | 0.038 | +100.0 % | 36094.84× |
| Q2 | 1231.131 | 14.177 | +98.8 % | 86.84× |
| Q3 | 1283.701 | 8.198 | +99.4 % | 156.59× |

Une réduction **négative** signifie que la requête est plus lente après indexation.
Un index n'est pas toujours utilisé si le planificateur estime qu'un parcours séquentiel est moins coûteux.

## Analyse des plans d'exécution

Principaux nœuds rencontrés (parcours récursif du plan de la troisième mesure) :

- **Q1 (before)** : Limit, Gather Merge, Sort, Seq Scan
- **Q1 (after)** : Limit, Index Scan (idx_bench_bucket_tvl)
- **Q2 (before)** : Sort, Aggregate, Gather Merge, Sort, Aggregate, Hash Join, Seq Scan, Hash, Seq Scan
- **Q2 (after)** : Sort, Aggregate, Gather Merge, Sort, Aggregate, Hash Join, Index Only Scan (idx_bench_cycle_chain), Hash, Seq Scan
- **Q3 (before)** : Sort, Aggregate, Gather Merge, Aggregate, Sort, Hash Join, Seq Scan, Hash, Seq Scan
- **Q3 (after)** : Sort, Aggregate, Hash Join, Index Only Scan (idx_bench_bucket_project), Hash, Seq Scan

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
