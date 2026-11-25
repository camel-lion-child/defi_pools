-- PERFORMANCE: compare BEFORE and AFTER indexes on same dataset / same query.
-- Run query EXPLAIN first; note Planning Time & Execution Time.
EXPLAIN (ANALYZE, BUFFERS)
SELECT f.pool_key, d.full_date, f.apy
FROM gold.fact_yield_daily f
JOIN gold.dim_date d ON d.date_key = f.date_key
WHERE f.pool_key = 1 AND d.full_date >= DATE '2026-10-01'
ORDER BY d.full_date;

-- Create index, update statistics; benchmark the same EXPLAIN once more.
CREATE INDEX IF NOT EXISTS idx_fact_yield_pool_date
    ON gold.fact_yield_daily (pool_key, date_key);
ANALYZE gold.fact_yield_daily;

EXPLAIN (ANALYZE, BUFFERS)
SELECT f.pool_key, d.full_date, f.apy
FROM gold.fact_yield_daily f
JOIN gold.dim_date d ON d.date_key = f.date_key
WHERE f.pool_key = 1 AND d.full_date >= DATE '2026-10-01'
ORDER BY d.full_date;

-- Note: indexes are not always faster for small tables or low-selectivity queries.
-- Keep actual timings and explain the plan (Seq Scan / Index Scan / Join).
