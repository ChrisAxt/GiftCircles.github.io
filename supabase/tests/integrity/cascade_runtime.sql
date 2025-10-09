\ir ../helpers/00_enable_extensions.sql

-- We expect 3 cascades:
--   events -> lists        (ON DELETE CASCADE)
--   lists  -> items        (ON DELETE CASCADE)
--   items  -> claims       (ON DELETE CASCADE)  (skip if 'claims' table doesn't exist)

SELECT plan(3);

-- helper: does a CASCADE FK exist between given tables?
WITH fk AS (
  SELECT
    tc.constraint_name,
    tc.table_schema   AS src_schema,
    tc.table_name     AS src_table,
    ccu.table_schema  AS dst_schema,
    ccu.table_name    AS dst_table,
    rc.delete_rule
  FROM information_schema.table_constraints tc
  JOIN information_schema.referential_constraints rc
    ON rc.constraint_schema = tc.constraint_schema
   AND rc.constraint_name   = tc.constraint_name
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_schema = tc.constraint_schema
   AND ccu.constraint_name   = tc.constraint_name
  WHERE tc.constraint_type = 'FOREIGN KEY'
)
SELECT ok(
  EXISTS (
    SELECT 1 FROM fk
    WHERE src_schema='public' AND src_table='lists'
      AND dst_schema='public' AND dst_table='events'
      AND delete_rule='CASCADE'
  ),
  'events -> lists uses ON DELETE CASCADE'
);

WITH fk AS (
  SELECT
    tc.constraint_name,
    tc.table_schema   AS src_schema,
    tc.table_name     AS src_table,
    ccu.table_schema  AS dst_schema,
    ccu.table_name    AS dst_table,
    rc.delete_rule
  FROM information_schema.table_constraints tc
  JOIN information_schema.referential_constraints rc
    ON rc.constraint_schema = tc.constraint_schema
   AND rc.constraint_name   = tc.constraint_name
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_schema = tc.constraint_schema
   AND ccu.constraint_name   = tc.constraint_name
  WHERE tc.constraint_type = 'FOREIGN KEY'
)
SELECT ok(
  EXISTS (
    SELECT 1 FROM fk
    WHERE src_schema='public' AND src_table='items'
      AND dst_schema='public' AND dst_table='lists'
      AND delete_rule='CASCADE'
  ),
  'lists -> items uses ON DELETE CASCADE'
);

-- items -> claims is optional in some schemas; pass if table absent OR cascade present
WITH fk AS (
  SELECT
    tc.constraint_name,
    tc.table_schema   AS src_schema,
    tc.table_name     AS src_table,
    ccu.table_schema  AS dst_schema,
    ccu.table_name    AS dst_table,
    rc.delete_rule
  FROM information_schema.table_constraints tc
  JOIN information_schema.referential_constraints rc
    ON rc.constraint_schema = tc.constraint_schema
   AND rc.constraint_name   = tc.constraint_name
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_schema = tc.constraint_schema
   AND ccu.constraint_name   = tc.constraint_name
  WHERE tc.constraint_type = 'FOREIGN KEY'
)
SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema='public' AND table_name='claims'
  )
  OR EXISTS (
    SELECT 1 FROM fk
    WHERE src_schema='public' AND src_table='claims'
      AND dst_schema='public' AND dst_table='items'
      AND delete_rule='CASCADE'
  ),
  'items -> claims uses ON DELETE CASCADE (or claims table absent)'
);

SELECT * FROM finish();
