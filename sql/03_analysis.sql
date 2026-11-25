-- The queries below use the Gold star schema built by 02_build_star.sql.
-- Run each numbered query separately to inspect its results.
-- All analytics stay focused on the SAME question (APY vs TVL by chain/project).

-- Q1. JOIN + GROUP BY + HAVING: average APY and TVL by chain, latest day.
-- APY is a rate, so AVG or TVL-weighted average is meaningful; SUM(apy) is not.
SELECT c.chain, COUNT(DISTINCT f.pool_key) AS pools,
       SUM(f.tvl_usd) AS total_pool_tvl_usd,
       ROUND(AVG(f.apy), 2) AS mean_apy,
       ROUND(SUM(f.apy * f.tvl_usd) /
             NULLIF(SUM(f.tvl_usd) FILTER (WHERE f.apy IS NOT NULL), 0), 2)
             AS tvl_weighted_apy
FROM gold.fact_yield_daily f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
JOIN gold.dim_date d ON d.date_key = f.date_key
WHERE d.full_date = (SELECT MAX(full_date) FROM gold.dim_date)
  AND f.tvl_usd >= 10000000
GROUP BY c.chain
HAVING COUNT(DISTINCT f.pool_key) >= 2
ORDER BY tvl_weighted_apy DESC NULLS LAST;

-- Q2. CTE + RANK(): top APY pools by chain (minimum TVL = $10m).
WITH ranked AS (
    SELECT c.chain, l.pool_id, l.symbol, f.tvl_usd, f.apy,
           RANK() OVER (PARTITION BY c.chain ORDER BY f.apy DESC) AS rank_apy
    FROM gold.fact_yield_daily f
    JOIN gold.dim_chain c ON c.chain_key = f.chain_key
    JOIN gold.dim_pool l ON l.pool_key = f.pool_key
    JOIN gold.dim_date d ON d.date_key = f.date_key
    WHERE d.full_date = (SELECT MAX(full_date) FROM gold.dim_date)
      AND f.tvl_usd >= 10000000 AND f.apy IS NOT NULL
)
SELECT * FROM ranked WHERE rank_apy <= 3 ORDER BY chain, rank_apy, pool_id;

-- Q3. Correlated subquery: pools exceeding their blockchain's average APY.
SELECT c.chain, l.pool_id, f.apy, f.tvl_usd
FROM gold.fact_yield_daily f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
JOIN gold.dim_pool l ON l.pool_key = f.pool_key
WHERE f.date_key = (SELECT MAX(date_key) FROM gold.fact_yield_daily)
  AND f.apy > (
      SELECT AVG(f2.apy) FROM gold.fact_yield_daily f2
      WHERE f2.date_key = f.date_key AND f2.chain_key = f.chain_key
  )
ORDER BY c.chain, f.apy DESC;

-- Q4. LAG(): APY change in percentage points between observed dates.
WITH history AS (
    SELECT l.pool_id, d.full_date, f.apy,
           LAG(f.apy) OVER (PARTITION BY f.pool_key ORDER BY d.full_date) AS prev_apy,
           LAG(d.full_date) OVER (PARTITION BY f.pool_key ORDER BY d.full_date) AS prev_date
    FROM gold.fact_yield_daily f
    JOIN gold.dim_date d ON d.date_key = f.date_key
    JOIN gold.dim_pool l ON l.pool_key = f.pool_key
)
SELECT pool_id, full_date, apy, prev_apy,
       ROUND(apy - prev_apy, 3) AS change_percentage_points,
       full_date - prev_date AS days_between_observations
FROM history
ORDER BY pool_id, full_date;

-- Q5. AVG OVER: rolling average over 7 OBSERVATIONS (not necessarily 7 calendar days).
SELECT l.pool_id, d.full_date, f.apy,
       ROUND(AVG(f.apy) OVER (
           PARTITION BY f.pool_key ORDER BY d.full_date
           ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
       ), 3) AS apy_moving_avg_7_observations
FROM gold.fact_yield_daily f
JOIN gold.dim_date d ON d.date_key = f.date_key
JOIN gold.dim_pool l ON l.pool_key = f.pool_key
ORDER BY l.pool_id, d.full_date;

-- Q6. NTILE(4): segment pools into TVL quartiles, within each blockchain.
SELECT c.chain, l.pool_id, f.tvl_usd, f.apy,
       NTILE(4) OVER (PARTITION BY c.chain ORDER BY f.tvl_usd DESC) AS tvl_quartile
FROM gold.fact_yield_daily f
JOIN gold.dim_chain c ON c.chain_key = f.chain_key
JOIN gold.dim_pool l ON l.pool_key = f.pool_key
WHERE f.date_key = (SELECT MAX(date_key) FROM gold.fact_yield_daily)
  AND f.tvl_usd IS NOT NULL
ORDER BY c.chain, tvl_quartile, f.tvl_usd DESC;

-- Q7. APY components: base vs reward by project (latest day).
SELECT p.project,
       COUNT(*) AS pool_observations,
       ROUND(AVG(f.apy_base), 2) AS avg_base_apy,
       ROUND(AVG(f.apy_reward), 2) AS avg_reward_apy
FROM gold.fact_yield_daily f
JOIN gold.dim_project p ON p.project_key = f.project_key
WHERE f.date_key = (SELECT MAX(date_key) FROM gold.fact_yield_daily)
GROUP BY p.project
ORDER BY avg_base_apy DESC NULLS LAST;

-- Q8. WITH RECURSIVE + LEFT JOIN: detect missing dates in the LAST 45 calendar days.
WITH RECURSIVE days AS (
    SELECT MAX(full_date) AS day, 1 AS n FROM gold.dim_date
    UNION ALL
    SELECT day - 1, n + 1 FROM days WHERE n < 45
)
SELECT days.day AS calendar_day, COUNT(f.pool_key) AS pool_observations,
       CASE WHEN COUNT(f.pool_key) = 0 THEN 'MISSING' ELSE 'OK' END AS status
FROM days
LEFT JOIN gold.dim_date d ON d.full_date = days.day
LEFT JOIN gold.fact_yield_daily f ON f.date_key = d.date_key
GROUP BY days.day
ORDER BY calendar_day;
