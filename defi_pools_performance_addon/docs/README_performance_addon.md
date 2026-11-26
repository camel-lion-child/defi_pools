## Volume, SQL avancé et performance

**Problématique métier :** « Quels pools DeFi présentent le meilleur compromis entre rendement (APY), liquidité (TVL) et indicateurs de risque, selon les blockchains et les protocoles ? »

Le dataset initial est structuré suivant l'architecture Medallion : `bronze` → `silver` → `gold` (schéma en étoile).
Les six requêtes métier de `sql/02_requetes_avancees.sql` portent uniquement sur les **données Gold réelles** et mettent en pratique : CTE, `DENSE_RANK`, `LAG`, `AVG OVER`, `NTILE`, `SUM OVER`, `WITH RECURSIVE` et jointures.

Pour étudier les performances PostgreSQL, une table de **10 millions de lignes synthétiques** est créée dans le schéma indépendant `benchmark` avec une PK et quatre FK vers les dimensions Gold. Les valeurs sont répliquées à partir de faits Gold existants : ce n'est ni une collecte supplémentaire ni un enrichissement des données métier.

### Fichiers complémentaires

- `sql/01_generation_volume.sql` : génération des 10 M de lignes, PK/FK et `ANALYZE`.
- `sql/02_requetes_avancees.sql` : six questions métier, chacune introduisant une requête avancée.
- `sql/03_index.sql` : index de benchmark, à exécuter **après** les mesures initiales.
- `sql/04_benchmark_queries.sql` : les trois requêtes inchangées pour le test avant/après.
- `scripts/02_benchmark.py` : mesure 3 fois chaque requête via `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` et export des plans JSON et CSV.
- `scripts/03_make_report.py` : rédaction du rapport à partir des résultats réels.
- `docs/rapport_performance.md` : rapport de comparaison et analyse des plans (généré localement).

### Exécution (dans cet ordre)

1. Confirmer dans Database Client que `SELECT current_database()` renvoie **`defi_pools`**.
2. Exécuter `sql/01_generation_volume.sql` **une seule fois**. Vérifier `COUNT(*) = 10000000`.
3. Dans le Terminal VS Code, lancer `python scripts/02_benchmark.py --phase before`.
4. Exécuter `sql/03_index.sql` ; les index sont créés et `ANALYZE` est lancé.
5. Lancer `python scripts/02_benchmark.py --phase after`.
6. Lancer `python scripts/03_make_report.py` et interpréter les plans dans `docs/rapport_performance.md`.
7. Exécuter les requêtes de `sql/02_requetes_avancees.sql` sur les données Gold.
8. Vérifier `git status`, committer les fichiers, pousser sur GitHub avant l'échéance.

**Attention :** la génération et l'indexation peuvent être longues et nécessiter plusieurs Go libres. Les mesures sur PostgreSQL local ne sont pas inventées dans le dépôt. Ne pas committer `.env`, `.env.save`, mots de passe ou fichiers contenant des identifiants. Conserver les sorties `docs/benchmark_*.csv` et les plans JSON pour la vérifiabilité.
