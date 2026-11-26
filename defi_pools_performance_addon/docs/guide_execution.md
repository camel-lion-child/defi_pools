# Guide d'intégration à `defi_pools`

Ce complément s'ajoute à votre projet existant. **Il ne remplace pas vos fichiers existants.**

1. Décompresser le ZIP **dans** `~/Desktop/ynov m1/sql_pipelines/defi_pools/` de manière à obtenir les nouveaux fichiers sous `sql/`, `scripts/`, `docs/`.
2. Vérifier que le schéma Gold existe déjà et que `gold.fact_yield_daily` contient des lignes. Ne pas relancer `sql/02_build_star.sql` une fois le benchmark créé, car cela supprimerait les dimensions référencées par les FK.
3. Coller le contenu de `docs/README_performance_addon.md` à la fin du `README.md` existant.
4. Vérifier `.gitignore` pour exclure `.env`, `.env.*` sauf `.env.example`, `.venv/`, et les fichiers volumineux dans `data/`.
5. Ouvrir `sql/01_generation_volume.sql` avec Database Client **connecté à `defi_pools`**, exécuter une fois (attention volume).
6. Puis Terminal (venv active) : `python scripts/02_benchmark.py --phase before`.
7. Ouvrir et exécuter `sql/03_index.sql`, puis `python scripts/02_benchmark.py --phase after`.
8. Exécuter `python scripts/03_make_report.py`. Lire le rapport, compléter l'interprétation des plans et les limites.
9. Exécuter séparément les six SELECT de `sql/02_requetes_avancees.sql`.
10. `git status` puis `git add README.md sql/ scripts/ docs/ .gitignore`, `git commit -m "Add volume generation, advanced SQL and PostgreSQL performance report"`, `git push origin main`.

**Important** : les tables PostgreSQL locales ne sont pas sur GitHub. Le correcteur pourra reproduire l'expérience avec le dataset cité dans le README et les scripts SQL.
