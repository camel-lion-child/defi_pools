
-- Intermediate : préparation des rendements DeFi
-- Grain : une observation par pool et par date

WITH yield_pools AS (

    SELECT
        snapshot_date,
        pool_id,
        chain,
        project,
        symbol,
        tvl_usd,
        apy,
        apy_base
    FROM {{ ref('stg_bronze__yield_pools_snapshots') }}

)

SELECT
    snapshot_date,
    pool_id,
    chain,
    project,
    symbol,
    tvl_usd,
    apy,
    apy_base,

    -- Rendement hors composante de base
    CASE
        WHEN apy IS NOT NULL AND apy_base IS NOT NULL
        THEN apy - apy_base
    END AS apy_reward,

    -- Indicateur métier de liquidité
    CASE
        WHEN tvl_usd >= 1000000 THEN 'high'
        WHEN tvl_usd >= 100000 THEN 'medium'
        ELSE 'low'
    END AS liquidity_segment

FROM yield_pools
