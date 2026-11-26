-- Trois requetes a comparer AVANT / APRES indexation, sur 10 M lignes synthetiques.
-- Le script scripts/02_benchmark.py lit les marqueurs '-- name: Q1' etc.
-- Ne pas modifier la requete entre les deux campagnes.

-- name: Q1
SELECT f.benchmark_id, f.tvl_usd, f.apy
FROM benchmark.fact_yield_10m f
WHERE f.scenario_bucket = 417
ORDER BY f.tvl_usd DESC NULLS LAST
LIMIT 100;

-- name: Q2
SELECT c.chain, COUNT(*) AS nb_lignes, ROUND(AVG(f.apy), 2) AS apy_moyen
FROM benchmark.fact_yield_10m f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
WHERE f.load_cycle = 57
GROUP BY c.chain
ORDER BY nb_lignes DESC;

-- name: Q3
SELECT p.project, COUNT(*) AS nb_lignes, ROUND(AVG(f.apy), 2) AS apy_moyen
FROM benchmark.fact_yield_10m f
JOIN gold.dim_project p ON p.project_key = f.project_key
WHERE f.scenario_bucket BETWEEN 900 AND 902
GROUP BY p.project
ORDER BY nb_lignes DESC;
