

-- Dimension des projets DeFi
-- Grain : un projet par ligne

SELECT
    ROW_NUMBER() OVER (ORDER BY project) AS project_key,
    project

FROM (
    SELECT DISTINCT project
    FROM {{ ref('int_yield_pools_enriched') }}
    WHERE project IS NOT NULL
) AS projects

