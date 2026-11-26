
-- Staging des données Yield Pools
-- Nettoyage et typage des données Bronze

SELECT
    NULLIF(TRIM(snapshot_date), '')::timestamp AS snapshot_date,
    NULLIF(TRIM(pool_id), '') AS pool_id,
    NULLIF(TRIM(chain), '') AS chain,
    NULLIF(TRIM(project), '') AS project,
    NULLIF(TRIM(symbol), '') AS symbol,
    NULLIF(TRIM(pool_meta), '') AS pool_meta,

    CASE
        WHEN TRIM(tvl_usd) ~
            '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
        THEN TRIM(tvl_usd)::numeric
    END AS tvl_usd,

    CASE
        WHEN TRIM(apy) ~
            '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
        THEN TRIM(apy)::numeric
    END AS apy,

    CASE
        WHEN TRIM(apy_base) ~
            '^[+-]?([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?$'
        THEN TRIM(apy_base)::numeric
    END AS apy_base

FROM {{ source('bronze', 'yield_pools_snapshots') }}

