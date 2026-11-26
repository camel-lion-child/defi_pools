
-- Dimension des blockchains
-- Une ligne par blockchain

SELECT
    ROW_NUMBER() OVER (ORDER BY chain) AS chain_key,
    chain

FROM (
    SELECT DISTINCT chain
    FROM {{ ref('int_yield_pools_enriched') }}
    WHERE chain IS NOT NULL
) AS chains
