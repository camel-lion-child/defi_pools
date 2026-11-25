-- STAR SCHEMA Gold for the ONE business question:
-- Which DeFi pools balance yield (APY) and liquidity (TVL) by chain/project?
-- Source: bronze.yield_pools_snapshots. 

SELECT current_database(); 
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- Source attributes such as il_risk, stablecoin and protocol category are NOT assumed here: they were not visible in the source screenshot.
-- Cast numeric values safely; invalid values become NULL for review.
CREATE OR REPLACE VIEW silver.yield_pools_clean AS
SELECT
    LEFT(snapshot_date, 10)::date AS full_date,
    NULLIF(BTRIM(pool_id), '') AS pool_id,
    NULLIF(BTRIM(chain), '') AS chain,
    NULLIF(BTRIM(project), '') AS project,
    NULLIF(BTRIM(symbol), '') AS symbol,
    CASE WHEN BTRIM(tvl_usd) ~ '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
         THEN BTRIM(tvl_usd)::numeric END AS tvl_usd,
    CASE WHEN BTRIM(apy) ~ '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
         THEN BTRIM(apy)::numeric END AS apy,
    CASE WHEN BTRIM(apy_base) ~ '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
         THEN BTRIM(apy_base)::numeric END AS apy_base,
    CASE WHEN BTRIM(apy_reward) ~ '^[-+]?[0-9]+([.][0-9]+)?([eE][-+]?[0-9]+)?$'
         THEN BTRIM(apy_reward)::numeric END AS apy_reward
FROM bronze.yield_pools_snapshots
WHERE LEFT(snapshot_date, 10) ~ '^\d{4}-\d{2}-\d{2}$';

-- Fail instead of silently dropping or duplicating observations.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM silver.yield_pools_clean
        WHERE pool_id IS NULL OR chain IS NULL OR project IS NULL OR full_date IS NULL
    ) THEN
        RAISE EXCEPTION 'Some rows lack pool_id, chain, project or date. Inspect Silver first.';
    END IF;
    IF EXISTS (
        SELECT 1 FROM silver.yield_pools_clean
        GROUP BY full_date, pool_id HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION 'Multiple observations for the same (date,pool_id). Resolve grain before Gold.';
    END IF;
END $$;

-- Re-running this script recreates ONLY Gold model tables.
DROP TABLE IF EXISTS gold.fact_yield_daily;
DROP TABLE IF EXISTS gold.dim_date;
DROP TABLE IF EXISTS gold.dim_chain;
DROP TABLE IF EXISTS gold.dim_project;
DROP TABLE IF EXISTS gold.dim_pool;

CREATE TABLE gold.dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    year SMALLINT NOT NULL,
    month SMALLINT NOT NULL,
    day SMALLINT NOT NULL
);
INSERT INTO gold.dim_date
SELECT DISTINCT TO_CHAR(full_date, 'YYYYMMDD')::integer,
       full_date,
       EXTRACT(YEAR FROM full_date)::smallint,
       EXTRACT(MONTH FROM full_date)::smallint,
       EXTRACT(DAY FROM full_date)::smallint
FROM silver.yield_pools_clean;

CREATE TABLE gold.dim_chain (
    chain_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    chain TEXT NOT NULL UNIQUE
);
INSERT INTO gold.dim_chain(chain)
SELECT DISTINCT chain FROM silver.yield_pools_clean ORDER BY chain;

CREATE TABLE gold.dim_project (
    project_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    project TEXT NOT NULL UNIQUE
);
INSERT INTO gold.dim_project(project)
SELECT DISTINCT project FROM silver.yield_pools_clean ORDER BY project;

CREATE TABLE gold.dim_pool (
    pool_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    pool_id TEXT NOT NULL UNIQUE,
    symbol TEXT
);
-- If a pool's symbol changed over time, use its latest available value.
INSERT INTO gold.dim_pool(pool_id, symbol)
SELECT DISTINCT ON (pool_id) pool_id, symbol
FROM silver.yield_pools_clean
ORDER BY pool_id, full_date DESC, symbol DESC NULLS LAST;

CREATE TABLE gold.fact_yield_daily (
    date_key INTEGER NOT NULL REFERENCES gold.dim_date(date_key),
    chain_key BIGINT NOT NULL REFERENCES gold.dim_chain(chain_key),
    project_key BIGINT NOT NULL REFERENCES gold.dim_project(project_key),
    pool_key BIGINT NOT NULL REFERENCES gold.dim_pool(pool_key),
    tvl_usd NUMERIC CHECK (tvl_usd >= 0),
    apy NUMERIC,
    apy_base NUMERIC,
    apy_reward NUMERIC,
    PRIMARY KEY(date_key, pool_key)
);

INSERT INTO gold.fact_yield_daily
    (date_key, chain_key, project_key, pool_key,
     tvl_usd, apy, apy_base, apy_reward)
SELECT d.date_key, c.chain_key, p.project_key, l.pool_key,
       s.tvl_usd, s.apy, s.apy_base, s.apy_reward
FROM silver.yield_pools_clean AS s
JOIN gold.dim_date AS d ON d.full_date = s.full_date
JOIN gold.dim_chain AS c ON c.chain = s.chain
JOIN gold.dim_project AS p ON p.project = s.project
JOIN gold.dim_pool AS l ON l.pool_id = s.pool_id;

-- Verify that no valid source rows have disappeared in the fact table.
SELECT (SELECT COUNT(*) FROM silver.yield_pools_clean) AS silver_rows,
       (SELECT COUNT(*) FROM gold.fact_yield_daily) AS gold_rows;
