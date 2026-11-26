-- Indices POUR LE BENCHMARK UNIQUEMENT : ne pas modifier les tables Gold.
-- Executer SEULEMENT apres les 3 mesures initiales (phase before).
DO $$ BEGIN
    IF current_database() <> 'defi_pools' THEN
        RAISE EXCEPTION 'Mauvaise base : %', current_database();
    END IF;
    IF to_regclass('benchmark.fact_yield_10m') IS NULL THEN
        RAISE EXCEPTION 'Generer benchmark.fact_yield_10m avant de creer les index';
    END IF;
END $$;

-- Q1: filtre sur un bucket, classement des TVL.
CREATE INDEX IF NOT EXISTS idx_bench_bucket_tvl
    ON benchmark.fact_yield_10m (scenario_bucket, tvl_usd DESC NULLS LAST);

-- Q2: filtre sur lot/cycle et regroupement par blockchain.
CREATE INDEX IF NOT EXISTS idx_bench_cycle_chain
    ON benchmark.fact_yield_10m (load_cycle, chain_key) INCLUDE (apy);

-- Q3: filtre sur bucket, aggregation par protocole.
CREATE INDEX IF NOT EXISTS idx_bench_bucket_project
    ON benchmark.fact_yield_10m (scenario_bucket, project_key) INCLUDE (apy);

ANALYZE benchmark.fact_yield_10m;

SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname = 'benchmark'
  AND tablename = 'fact_yield_10m'
ORDER BY indexname;
