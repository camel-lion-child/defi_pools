-- Projet DeFi Pools | Generation d'un jeu SYNTHETIQUE pour benchmark (~10 M lignes).
-- A executer dans la base defi_pools uniquement, APRES sql/02_build_star.sql.
-- NE MODIFIE PAS bronze, silver ni gold.
-- IMPORTANT : execution longue, plusieurs Go d'espace disque peuvent etre necessaires.
-- Ne pas relancer si benchmark.fact_yield_10m existe deja.

DO $$
BEGIN
    IF current_database() <> 'defi_pools' THEN
        RAISE EXCEPTION 'STOP : database %, attendu defi_pools', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM gold.fact_yield_daily) THEN
        RAISE EXCEPTION 'STOP : gold.fact_yield_daily est vide. Construire Gold avant le benchmark.';
    END IF;
END $$;

CREATE SCHEMA IF NOT EXISTS benchmark;

DO $$
BEGIN
    IF to_regclass('benchmark.fact_yield_10m') IS NOT NULL THEN
        RAISE EXCEPTION 'Table benchmark.fact_yield_10m deja presente. Ne pas regenerer a l aveugle.';
    END IF;
END $$;

-- La table est creee par CTAS pour accelerer le chargement massif.
-- Les FK sont posees ENSUITE et validees par PostgreSQL.
-- Chaque ligne est issue d'une observation Gold valide : dates, chains, projets, pools
-- restent referentiellement coherents. Les copies sont STRICTEMENT pour les tests.
CREATE TABLE benchmark.fact_yield_10m AS
WITH seed AS MATERIALIZED (
    SELECT
        ROW_NUMBER() OVER (ORDER BY date_key, pool_key) AS rn,
        date_key, chain_key, project_key, pool_key, tvl_usd, apy
    FROM gold.fact_yield_daily
    ORDER BY date_key, pool_key
    LIMIT 50000
),
seed_count AS (SELECT COUNT(*) AS n FROM seed)
SELECT
    g.n::BIGINT AS benchmark_id,
    s.date_key::INTEGER AS date_key,
    s.chain_key::BIGINT AS chain_key,
    s.project_key::BIGINT AS project_key,
    s.pool_key::BIGINT AS pool_key,
    s.tvl_usd::NUMERIC AS tvl_usd,
    s.apy::NUMERIC AS apy,
    ((g.n - 1) % 1000)::INTEGER AS scenario_bucket,
    ((g.n - 1) / 100000)::INTEGER AS load_cycle
FROM generate_series(1::BIGINT, 10000000::BIGINT) AS g(n)
CROSS JOIN seed_count sc
JOIN seed s ON s.rn = 1 + ((g.n - 1) % sc.n);

-- Integrite : 1 PK et 4 FK physiques, validees par la base.
ALTER TABLE benchmark.fact_yield_10m
    ADD CONSTRAINT pk_benchmark_fact PRIMARY KEY (benchmark_id),
    ADD CONSTRAINT fk_benchmark_date
        FOREIGN KEY (date_key) REFERENCES gold.dim_date(date_key),
    ADD CONSTRAINT fk_benchmark_chain
        FOREIGN KEY (chain_key) REFERENCES gold.dim_chain(chain_key),
    ADD CONSTRAINT fk_benchmark_project
        FOREIGN KEY (project_key) REFERENCES gold.dim_project(project_key),
    ADD CONSTRAINT fk_benchmark_pool
        FOREIGN KEY (pool_key) REFERENCES gold.dim_pool(pool_key);

ANALYZE benchmark.fact_yield_10m;

-- Controle final : 10 M exactement ; contraintes FK et PK presentes.
SELECT COUNT(*) AS nb_lignes, COUNT(DISTINCT benchmark_id) AS nb_ids
FROM benchmark.fact_yield_10m;

SELECT conname, contype, convalidated
FROM pg_constraint
WHERE conrelid = 'benchmark.fact_yield_10m'::regclass
ORDER BY contype, conname;
