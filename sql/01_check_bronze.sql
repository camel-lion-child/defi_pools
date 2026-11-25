-- Execute in VS Code Database Client with a connection to `defi_pools`.
SELECT current_database();

-- Check imported tables. 
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'bronze' AND table_type = 'BASE TABLE'
ORDER BY table_name;

-- Check the number of rows, unique pools, and unique days in the `bronze.yield_pools_snapshots` table. 
SELECT COUNT(*) AS source_rows,
       COUNT(DISTINCT pool_id) AS unique_pools,
       COUNT(DISTINCT LEFT(snapshot_date, 10)) AS unique_days,
       MIN(LEFT(snapshot_date, 10)) AS first_day,
       MAX(LEFT(snapshot_date, 10)) AS last_day
FROM bronze.yield_pools_snapshots;

-- Check duplicate pool observations per calendar day before building the star.
SELECT LEFT(snapshot_date, 10) AS observation_day,
       pool_id, COUNT(*) AS duplicates
FROM bronze.yield_pools_snapshots
GROUP BY 1, 2
HAVING COUNT(*) > 1
ORDER BY duplicates DESC
LIMIT 20;
