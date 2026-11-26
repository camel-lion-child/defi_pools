-- PostgreSQL / Gold star schema | Six requetes SQL avancees pour UNE question metier.
-- Question centrale : quels pools DeFi ont un bon compromis APY/TVL selon chain/projet ?
-- Ces requetes utilisent les VRAIES donnees Gold, jamais la table synthetique benchmark.
-- Executer chaque SELECT separement dans VS Code. APY est en points de pourcentage.

-- Q1 QUESTION METIER : Quels sont les trois pools avec les plus hauts APY par blockchain,
-- sous condition TVL >= 10 M USD, pour la derniere date ?
-- Techniques : CTE, JOIN, DENSE_RANK, PARTITION BY.
WITH latest AS (
    SELECT MAX(date_key) AS date_key FROM gold.fact_yield_daily
), ranked AS (
    SELECT c.chain, p.pool_id, p.symbol, f.tvl_usd, f.apy,
           DENSE_RANK() OVER (
               PARTITION BY c.chain ORDER BY f.apy DESC
           ) AS rang_apy
    FROM gold.fact_yield_daily f
    JOIN latest ld ON ld.date_key = f.date_key
    JOIN gold.dim_chain c ON c.chain_key = f.chain_key
    JOIN gold.dim_pool p ON p.pool_key = f.pool_key
    WHERE f.tvl_usd >= 10000000 AND f.apy IS NOT NULL
)
SELECT * FROM ranked
WHERE rang_apy <= 3
ORDER BY chain, rang_apy, pool_id;

-- Q2 QUESTION METIER : Comment l'APY d'un pool evolue-t-il entre deux observations ?
-- Techniques : LAG, PARTITION BY, CTE, JOIN.
WITH evolution AS (
    SELECT p.pool_id, d.full_date, f.apy,
           LAG(f.apy) OVER (
               PARTITION BY f.pool_key ORDER BY d.full_date
           ) AS apy_precedent,
           LAG(d.full_date) OVER (
               PARTITION BY f.pool_key ORDER BY d.full_date
           ) AS date_precedente
    FROM gold.fact_yield_daily f
    JOIN gold.dim_pool p ON p.pool_key = f.pool_key
    JOIN gold.dim_date d ON d.date_key = f.date_key
)
SELECT pool_id, full_date, apy, apy_precedent,
       ROUND((apy - apy_precedent)::numeric, 3) AS variation_points,
       full_date - date_precedente AS ecart_jours
FROM evolution
WHERE date_precedente IS NOT NULL
ORDER BY pool_id, full_date;

-- Q3 QUESTION METIER : Les rendements d'un pool sont-ils stables sur sept observations ?
-- Techniques : AVG() OVER, ROWS BETWEEN, PARTITION BY.
-- 7 observations ne signifient PAS toujours 7 jours calendaires.
SELECT p.pool_id, d.full_date, f.apy, f.tvl_usd,
       ROUND(AVG(f.apy) OVER (
           PARTITION BY f.pool_key ORDER BY d.full_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       )::numeric, 3) AS apy_moyenne_7_observations
FROM gold.fact_yield_daily f
JOIN gold.dim_pool p ON p.pool_key = f.pool_key
JOIN gold.dim_date d ON d.date_key = f.date_key
ORDER BY p.pool_id, d.full_date;

-- Q4 QUESTION METIER : Comment segmenter les pools par quartiles de liquidite (TVL)
-- pour chaque blockchain, a la date la plus recente ?
-- Techniques : NTILE(4), PARTITION BY, sous-requete scalaire, JOIN.
SELECT c.chain, p.pool_id, f.tvl_usd, f.apy,
       NTILE(4) OVER (
           PARTITION BY c.chain ORDER BY f.tvl_usd DESC, f.pool_key
       ) AS quartile_tvl
FROM gold.fact_yield_daily f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
JOIN gold.dim_pool p ON p.pool_key = f.pool_key
WHERE f.date_key = (SELECT MAX(date_key) FROM gold.fact_yield_daily)
  AND f.tvl_usd IS NOT NULL
ORDER BY c.chain, quartile_tvl, f.tvl_usd DESC;

-- Q5 QUESTION METIER : Quelle part de la TVL des pools chaque pool represente-t-il
-- dans sa blockchain, a la date la plus recente ?
-- Techniques : SUM() OVER(PARTITION BY), NULLIF, JOIN.
-- La TVL ici est la SOMME DES POOLS du dataset, PAS la TVL totale de la blockchain.
SELECT c.chain, p.pool_id, f.tvl_usd, f.apy,
       ROUND(100.0 * f.tvl_usd / NULLIF(
           SUM(f.tvl_usd) OVER (PARTITION BY f.date_key, f.chain_key), 0
       ), 3) AS part_tvl_pools_pct
FROM gold.fact_yield_daily f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
JOIN gold.dim_pool p ON p.pool_key = f.pool_key
WHERE f.date_key = (SELECT MAX(date_key) FROM gold.fact_yield_daily)
ORDER BY c.chain, part_tvl_pools_pct DESC NULLS LAST;

-- Q6 QUESTION METIER : Quels jours sans observation manquent sur les 45 derniers
-- jours calendaires disponibles pour analyser la tendance des rendements ?
-- Techniques : WITH RECURSIVE, LEFT JOIN, GROUP BY, CASE.
-- La recursion parcourt un CALENDRIER, pas une hierarchie de protocoles.
WITH RECURSIVE calendrier AS (
    SELECT MAX(full_date) AS jour, 1 AS n FROM gold.dim_date
    UNION ALL
    SELECT jour - 1, n + 1 FROM calendrier
    WHERE n < 45
)
SELECT cal.jour,
       COUNT(f.pool_key) AS nb_observations,
       CASE WHEN COUNT(f.pool_key) = 0 THEN 'MANQUANT' ELSE 'OK' END AS statut
FROM calendrier cal
LEFT JOIN gold.dim_date d ON d.full_date = cal.jour
LEFT JOIN gold.fact_yield_daily f ON f.date_key = d.date_key
GROUP BY cal.jour
ORDER BY cal.jour;
