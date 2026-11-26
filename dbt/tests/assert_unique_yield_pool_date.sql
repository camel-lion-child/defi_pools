
-- Test métier : une seule observation par pool et par date
-- Le test échoue si des doublons sont détectés.

SELECT
    snapshot_date,
    pool_id,
    COUNT(*) AS nb_occurrences
FROM {{ ref('stg_bronze__yield_pools_snapshots') }}
GROUP BY snapshot_date, pool_id
HAVING COUNT(*) > 1
