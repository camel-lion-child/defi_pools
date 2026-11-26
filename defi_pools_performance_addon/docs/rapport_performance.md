# Rapport de performance — PostgreSQL (à compléter par des mesures réelles)

Les résultats ne sont **pas encore mesurés** dans le PostgreSQL local de l'étudiante.

## Protocole

1. Créer `benchmark.fact_yield_10m` (10 millions de lignes et FK cohérentes).
2. Exécuter les **trois** requêtes avec `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` **trois fois chacune**, avant indexation.
3. Créer les index depuis `sql/03_index.sql`, puis lancer `ANALYZE`.
4. Relancer exactement les mêmes requêtes trois fois chacune après indexation.
5. Comparer les médianes et analyser les plans d'exécution avant/après.

Le script `scripts/03_make_report.py` remplacera ce fichier par les résultats **effectivement mesurés** et les plans enregistrés. Il ne faut pas soumettre ce fichier provisoire comme s'il s'agissait d'un résultat final.
