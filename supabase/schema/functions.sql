schema,function,args,lang,security_definer,volatility,ddl
auth,email,,sql,false,s,"CREATE OR REPLACE FUNCTION auth.email()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$function$
"
auth,jwt,,sql,false,s,"CREATE OR REPLACE FUNCTION auth.jwt()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$function$
"
auth,role,,sql,false,s,"CREATE OR REPLACE FUNCTION auth.role()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$function$
"
auth,uid,,sql,false,s,"CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$
"
cron,alter_job,"job_id bigint, schedule text, command text, database text, username text, active boolean",c,false,v,"CREATE OR REPLACE FUNCTION cron.alter_job(job_id bigint, schedule text DEFAULT NULL::text, command text DEFAULT NULL::text, database text DEFAULT NULL::text, username text DEFAULT NULL::text, active boolean DEFAULT NULL::boolean)
 RETURNS void
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_alter_job$function$
"
cron,job_cache_invalidate,,c,false,v,"CREATE OR REPLACE FUNCTION cron.job_cache_invalidate()
 RETURNS trigger
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_job_cache_invalidate$function$
"
cron,schedule,"job_name text, schedule text, command text",c,false,v,"CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
 RETURNS bigint
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_schedule_named$function$
"
cron,schedule,"schedule text, command text",c,false,v,"CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text)
 RETURNS bigint
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_schedule$function$
"
cron,schedule_in_database,"job_name text, schedule text, command text, database text, username text, active boolean",c,false,v,"CREATE OR REPLACE FUNCTION cron.schedule_in_database(job_name text, schedule text, command text, database text, username text DEFAULT NULL::text, active boolean DEFAULT true)
 RETURNS bigint
 LANGUAGE c
AS '$libdir/pg_cron', $function$cron_schedule_named$function$
"
cron,unschedule,job_id bigint,c,false,v,"CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint)
 RETURNS boolean
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_unschedule$function$
"
cron,unschedule,job_name text,c,false,v,"CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
 RETURNS boolean
 LANGUAGE c
 STRICT
AS '$libdir/pg_cron', $function$cron_unschedule_named$function$
"
extensions,armor,bytea,c,false,i,"CREATE OR REPLACE FUNCTION extensions.armor(bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_armor$function$
"
extensions,armor,"bytea, text[], text[]",c,false,i,"CREATE OR REPLACE FUNCTION extensions.armor(bytea, text[], text[])
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_armor$function$
"
extensions,crypt,"text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.crypt(text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_crypt$function$
"
extensions,dearmor,text,c,false,i,"CREATE OR REPLACE FUNCTION extensions.dearmor(text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_dearmor$function$
"
extensions,decrypt,"bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.decrypt(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_decrypt$function$
"
extensions,decrypt_iv,"bytea, bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.decrypt_iv(bytea, bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_decrypt_iv$function$
"
extensions,digest,"bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.digest(bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_digest$function$
"
extensions,digest,"text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.digest(text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_digest$function$
"
extensions,encrypt,"bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.encrypt(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_encrypt$function$
"
extensions,encrypt_iv,"bytea, bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.encrypt_iv(bytea, bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_encrypt_iv$function$
"
extensions,gen_random_bytes,integer,c,false,v,"CREATE OR REPLACE FUNCTION extensions.gen_random_bytes(integer)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_random_bytes$function$
"
extensions,gen_random_uuid,,c,false,v,"CREATE OR REPLACE FUNCTION extensions.gen_random_uuid()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE
AS '$libdir/pgcrypto', $function$pg_random_uuid$function$
"
extensions,gen_salt,text,c,false,v,"CREATE OR REPLACE FUNCTION extensions.gen_salt(text)
 RETURNS text
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_gen_salt$function$
"
extensions,gen_salt,"text, integer",c,false,v,"CREATE OR REPLACE FUNCTION extensions.gen_salt(text, integer)
 RETURNS text
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_gen_salt_rounds$function$
"
extensions,grant_pg_cron_access,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.grant_pg_cron_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_cron'
  )
  THEN
    grant usage on schema cron to postgres with grant option;

    alter default privileges in schema cron grant all on tables to postgres with grant option;
    alter default privileges in schema cron grant all on functions to postgres with grant option;
    alter default privileges in schema cron grant all on sequences to postgres with grant option;

    alter default privileges for user supabase_admin in schema cron grant all
        on sequences to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on tables to postgres with grant option;
    alter default privileges for user supabase_admin in schema cron grant all
        on functions to postgres with grant option;

    grant all privileges on all tables in schema cron to postgres with grant option;
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  END IF;
END;
$function$
"
extensions,grant_pg_graphql_access,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.grant_pg_graphql_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    func_is_graphql_resolve bool;
BEGIN
    func_is_graphql_resolve = (
        SELECT n.proname = 'resolve'
        FROM pg_event_trigger_ddl_commands() AS ev
        LEFT JOIN pg_catalog.pg_proc AS n
        ON ev.objid = n.oid
    );

    IF func_is_graphql_resolve
    THEN
        -- Update public wrapper to pass all arguments through to the pg_graphql resolve func
        DROP FUNCTION IF EXISTS graphql_public.graphql;
        create or replace function graphql_public.graphql(
            ""operationName"" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language sql
        as $$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                ""operationName"" := ""operationName"",
                extensions := extensions
            );
        $$;

        -- This hook executes when `graphql.resolve` is created. That is not necessarily the last
        -- function in the extension so we need to grant permissions on existing entities AND
        -- update default permissions to any others that are created after `graphql.resolve`
        grant usage on schema graphql to postgres, anon, authenticated, service_role;
        grant select on all tables in schema graphql to postgres, anon, authenticated, service_role;
        grant execute on all functions in schema graphql to postgres, anon, authenticated, service_role;
        grant all on all sequences in schema graphql to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on tables to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on functions to postgres, anon, authenticated, service_role;
        alter default privileges in schema graphql grant all on sequences to postgres, anon, authenticated, service_role;

        -- Allow postgres role to allow granting usage on graphql and graphql_public schemas to custom roles
        grant usage on schema graphql_public to postgres with grant option;
        grant usage on schema graphql to postgres with grant option;
    END IF;

END;
$function$
"
extensions,grant_pg_net_access,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.grant_pg_net_access()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_event_trigger_ddl_commands() AS ev
    JOIN pg_extension AS ext
    ON ev.objid = ext.oid
    WHERE ext.extname = 'pg_net'
  )
  THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_roles
      WHERE rolname = 'supabase_functions_admin'
    )
    THEN
      CREATE USER supabase_functions_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION;
    END IF;

    GRANT USAGE ON SCHEMA net TO supabase_functions_admin, postgres, anon, authenticated, service_role;

    IF EXISTS (
      SELECT FROM pg_extension
      WHERE extname = 'pg_net'
      -- all versions in use on existing projects as of 2025-02-20
      -- version 0.12.0 onwards don't need these applied
      AND extversion IN ('0.2', '0.6', '0.7', '0.7.1', '0.8', '0.10.0', '0.11.0')
    ) THEN
      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

      ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
      ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

      REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
      REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

      GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
      GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO supabase_functions_admin, postgres, anon, authenticated, service_role;
    END IF;
  END IF;
END;
$function$
"
extensions,hmac,"bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.hmac(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_hmac$function$
"
extensions,hmac,"text, text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.hmac(text, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pg_hmac$function$
"
extensions,pg_stat_statements,"showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements(showtext boolean, OUT userid oid, OUT dbid oid, OUT toplevel boolean, OUT queryid bigint, OUT query text, OUT plans bigint, OUT total_plan_time double precision, OUT min_plan_time double precision, OUT max_plan_time double precision, OUT mean_plan_time double precision, OUT stddev_plan_time double precision, OUT calls bigint, OUT total_exec_time double precision, OUT min_exec_time double precision, OUT max_exec_time double precision, OUT mean_exec_time double precision, OUT stddev_exec_time double precision, OUT rows bigint, OUT shared_blks_hit bigint, OUT shared_blks_read bigint, OUT shared_blks_dirtied bigint, OUT shared_blks_written bigint, OUT local_blks_hit bigint, OUT local_blks_read bigint, OUT local_blks_dirtied bigint, OUT local_blks_written bigint, OUT temp_blks_read bigint, OUT temp_blks_written bigint, OUT shared_blk_read_time double precision, OUT shared_blk_write_time double precision, OUT local_blk_read_time double precision, OUT local_blk_write_time double precision, OUT temp_blk_read_time double precision, OUT temp_blk_write_time double precision, OUT wal_records bigint, OUT wal_fpi bigint, OUT wal_bytes numeric, OUT jit_functions bigint, OUT jit_generation_time double precision, OUT jit_inlining_count bigint, OUT jit_inlining_time double precision, OUT jit_optimization_count bigint, OUT jit_optimization_time double precision, OUT jit_emission_count bigint, OUT jit_emission_time double precision, OUT jit_deform_count bigint, OUT jit_deform_time double precision, OUT stats_since timestamp with time zone, OUT minmax_stats_since timestamp with time zone)
 RETURNS SETOF record
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_1_11$function$
"
extensions,pg_stat_statements_info,"OUT dealloc bigint, OUT stats_reset timestamp with time zone",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements_info(OUT dealloc bigint, OUT stats_reset timestamp with time zone)
 RETURNS record
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_info$function$
"
extensions,pg_stat_statements_reset,"userid oid, dbid oid, queryid bigint, minmax_only boolean",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pg_stat_statements_reset(userid oid DEFAULT 0, dbid oid DEFAULT 0, queryid bigint DEFAULT 0, minmax_only boolean DEFAULT false)
 RETURNS timestamp with time zone
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pg_stat_statements', $function$pg_stat_statements_reset_1_11$function$
"
extensions,pgp_armor_headers,"text, OUT key text, OUT value text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_armor_headers(text, OUT key text, OUT value text)
 RETURNS SETOF record
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_armor_headers$function$
"
extensions,pgp_key_id,bytea,c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_key_id(bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_key_id_w$function$
"
extensions,pgp_pub_decrypt,"bytea, bytea",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt,"bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt,"bytea, bytea, text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt(bytea, bytea, text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_text$function$
"
extensions,pgp_pub_decrypt_bytea,"bytea, bytea",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_decrypt_bytea,"bytea, bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_decrypt_bytea,"bytea, bytea, text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_decrypt_bytea(bytea, bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_decrypt_bytea$function$
"
extensions,pgp_pub_encrypt,"text, bytea",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt(text, bytea)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_text$function$
"
extensions,pgp_pub_encrypt,"text, bytea, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt(text, bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_text$function$
"
extensions,pgp_pub_encrypt_bytea,"bytea, bytea",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_bytea$function$
"
extensions,pgp_pub_encrypt_bytea,"bytea, bytea, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_pub_encrypt_bytea(bytea, bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_pub_encrypt_bytea$function$
"
extensions,pgp_sym_decrypt,"bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt(bytea, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_text$function$
"
extensions,pgp_sym_decrypt,"bytea, text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt(bytea, text, text)
 RETURNS text
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_text$function$
"
extensions,pgp_sym_decrypt_bytea,"bytea, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_bytea$function$
"
extensions,pgp_sym_decrypt_bytea,"bytea, text, text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_decrypt_bytea(bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_decrypt_bytea$function$
"
extensions,pgp_sym_encrypt,"text, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt(text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_text$function$
"
extensions,pgp_sym_encrypt,"text, text, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt(text, text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_text$function$
"
extensions,pgp_sym_encrypt_bytea,"bytea, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_bytea$function$
"
extensions,pgp_sym_encrypt_bytea,"bytea, text, text",c,false,v,"CREATE OR REPLACE FUNCTION extensions.pgp_sym_encrypt_bytea(bytea, text, text)
 RETURNS bytea
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/pgcrypto', $function$pgp_sym_encrypt_bytea$function$
"
extensions,pgrst_ddl_watch,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.pgrst_ddl_watch()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF cmd.command_tag IN (
      'CREATE SCHEMA', 'ALTER SCHEMA'
    , 'CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE'
    , 'CREATE FOREIGN TABLE', 'ALTER FOREIGN TABLE'
    , 'CREATE VIEW', 'ALTER VIEW'
    , 'CREATE MATERIALIZED VIEW', 'ALTER MATERIALIZED VIEW'
    , 'CREATE FUNCTION', 'ALTER FUNCTION'
    , 'CREATE TRIGGER'
    , 'CREATE TYPE', 'ALTER TYPE'
    , 'CREATE RULE'
    , 'COMMENT'
    )
    -- don't notify in case of CREATE TEMP table or other objects created on pg_temp
    AND cmd.schema_name is distinct from 'pg_temp'
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$
"
extensions,pgrst_drop_watch,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.pgrst_drop_watch()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  obj record;
BEGIN
  FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
  LOOP
    IF obj.object_type IN (
      'schema'
    , 'table'
    , 'foreign table'
    , 'view'
    , 'materialized view'
    , 'function'
    , 'trigger'
    , 'type'
    , 'rule'
    )
    AND obj.is_temporary IS false -- no pg_temp objects
    THEN
      NOTIFY pgrst, 'reload schema';
    END IF;
  END LOOP;
END; $function$
"
extensions,set_graphql_placeholder,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION extensions.set_graphql_placeholder()
 RETURNS event_trigger
 LANGUAGE plpgsql
AS $function$
    DECLARE
    graphql_is_dropped bool;
    BEGIN
    graphql_is_dropped = (
        SELECT ev.schema_name = 'graphql_public'
        FROM pg_event_trigger_dropped_objects() AS ev
        WHERE ev.schema_name = 'graphql_public'
    );

    IF graphql_is_dropped
    THEN
        create or replace function graphql_public.graphql(
            ""operationName"" text default null,
            query text default null,
            variables jsonb default null,
            extensions jsonb default null
        )
            returns jsonb
            language plpgsql
        as $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;
    END IF;

    END;
$function$
"
extensions,uuid_generate_v1,,c,false,v,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v1()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v1$function$
"
extensions,uuid_generate_v1mc,,c,false,v,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v1mc()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v1mc$function$
"
extensions,uuid_generate_v3,"namespace uuid, name text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v3(namespace uuid, name text)
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v3$function$
"
extensions,uuid_generate_v4,,c,false,v,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v4()
 RETURNS uuid
 LANGUAGE c
 PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v4$function$
"
extensions,uuid_generate_v5,"namespace uuid, name text",c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_generate_v5(namespace uuid, name text)
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_generate_v5$function$
"
extensions,uuid_nil,,c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_nil()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_nil$function$
"
extensions,uuid_ns_dns,,c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_dns()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_dns$function$
"
extensions,uuid_ns_oid,,c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_oid()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_oid$function$
"
extensions,uuid_ns_url,,c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_url()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_url$function$
"
extensions,uuid_ns_x500,,c,false,i,"CREATE OR REPLACE FUNCTION extensions.uuid_ns_x500()
 RETURNS uuid
 LANGUAGE c
 IMMUTABLE PARALLEL SAFE STRICT
AS '$libdir/uuid-ossp', $function$uuid_ns_x500$function$
"
graphql,_internal_resolve,"query text, variables jsonb, ""operationName"" text, extensions jsonb",c,false,v,"CREATE OR REPLACE FUNCTION graphql._internal_resolve(query text, variables jsonb DEFAULT '{}'::jsonb, ""operationName"" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE c
AS '$libdir/pg_graphql', $function$resolve_wrapper$function$
"
graphql,comment_directive,comment_ text,sql,false,i,"CREATE OR REPLACE FUNCTION graphql.comment_directive(comment_ text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
    /*
    comment on column public.account.name is '@graphql.name: myField'
    */
    select
        coalesce(
            (
                regexp_match(
                    comment_,
                    '@graphql\((.+)\)'
                )
            )[1]::jsonb,
            jsonb_build_object()
        )
$function$
"
graphql,exception,message text,plpgsql,false,v,"CREATE OR REPLACE FUNCTION graphql.exception(message text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
begin
    raise exception using errcode='22000', message=message;
end;
$function$
"
graphql,get_schema_version,,sql,true,v,"CREATE OR REPLACE FUNCTION graphql.get_schema_version()
 RETURNS integer
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
    select last_value from graphql.seq_schema_version;
$function$
"
graphql,increment_schema_version,,plpgsql,true,v,"CREATE OR REPLACE FUNCTION graphql.increment_schema_version()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
    perform pg_catalog.nextval('graphql.seq_schema_version');
end;
$function$
"
graphql,resolve,"query text, variables jsonb, ""operationName"" text, extensions jsonb",plpgsql,false,v,"CREATE OR REPLACE FUNCTION graphql.resolve(query text, variables jsonb DEFAULT '{}'::jsonb, ""operationName"" text DEFAULT NULL::text, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
    res jsonb;
    message_text text;
begin
  begin
    select graphql._internal_resolve(""query"" := ""query"",
                                     ""variables"" := ""variables"",
                                     ""operationName"" := ""operationName"",
                                     ""extensions"" := ""extensions"") into res;
    return res;
  exception
    when others then
    get stacked diagnostics message_text = message_text;
    return
    jsonb_build_object('data', null,
                       'errors', jsonb_build_array(jsonb_build_object('message', message_text)));
  end;
end;
$function$
"
graphql_public,graphql,"""operationName"" text, query text, variables jsonb, extensions jsonb",sql,false,v,"CREATE OR REPLACE FUNCTION graphql_public.graphql(""operationName"" text DEFAULT NULL::text, query text DEFAULT NULL::text, variables jsonb DEFAULT NULL::jsonb, extensions jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE sql
AS $function$
            select graphql.resolve(
                query := query,
                variables := coalesce(variables, '{}'),
                ""operationName"" := ""operationName"",
                extensions := extensions
            );
        $function$
"
pgbouncer,get_auth,p_usename text,plpgsql,true,v,"CREATE OR REPLACE FUNCTION pgbouncer.get_auth(p_usename text)
 RETURNS TABLE(username text, password text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
    raise debug 'PgBouncer auth request: %', p_usename;

    return query
    select 
        rolname::text, 
        case when rolvaliduntil < now() 
            then null 
            else rolpassword::text 
        end 
    from pg_authid 
    where rolname=$1 and rolcanlogin;
end;
$function$
"
public,_next_occurrence,"p_date date, p_freq text, p_interval integer",sql,false,i,"CREATE OR REPLACE FUNCTION public._next_occurrence(p_date date, p_freq text, p_interval integer DEFAULT 1)
 RETURNS date
 LANGUAGE sql
 IMMUTABLE
AS $function$
select case p_freq
  when 'weekly'  then p_date + (7 * p_interval)
  when 'monthly' then (p_date + (interval '1 month' * p_interval))::date
  when 'yearly'  then (p_date + (interval '1 year'  * p_interval))::date
  else p_date
end;
$function$
"
public,_pick_new_admin,p_event_id uuid,sql,false,s,"CREATE OR REPLACE FUNCTION public._pick_new_admin(p_event_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select user_id
  from public.event_members
  where event_id = p_event_id
  order by created_at nulls last, user_id
  limit 1
$function$
"
public,allowed_event_slots,p_user uuid,sql,false,s,"CREATE OR REPLACE FUNCTION public.allowed_event_slots(p_user uuid DEFAULT auth.uid())
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
  select case when public.is_pro(p_user) then 1000000 else 3 end;
$function$
"
public,autojoin_event_as_admin,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION public.autojoin_event_as_admin()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  insert into public.event_members(event_id, user_id, role)
  values (new.id, new.owner_id, 'admin')
  on conflict do nothing;
  return new;
end;$function$
"
public,can_claim_item,"p_item_id uuid, p_user uuid",sql,false,s,"CREATE OR REPLACE FUNCTION public.can_claim_item(p_item_id uuid, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  with i as (
    select i.id, i.list_id, l.event_id
    from public.items i
    join public.lists l on l.id = i.list_id
    where i.id = p_item_id
  )
  select
    exists (
      select 1 from i
      join public.event_members em
        on em.event_id = i.event_id and em.user_id = p_user
    )
    and not exists (
      select 1 from public.list_recipients lr
      join i on i.list_id = lr.list_id
      where lr.user_id = p_user
    );
$function$
"
public,can_create_event,p_user uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.can_create_event(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when public.is_pro(p_user, now()) then true
    else (select count(*) < 3 from public.event_members where user_id = p_user)
  end;
$function$
"
public,can_view_list,p_list uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.can_view_list(p_list uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT public.is_member_of_event(l.event_id)
     AND NOT EXISTS (
           SELECT 1
           FROM public.list_exclusions e
           WHERE e.list_id = p_list
             AND e.user_id = auth.uid()
         )
  FROM public.lists l
  WHERE l.id = p_list;
$function$
"
public,can_view_list,"uuid, uuid",sql,true,s,"CREATE OR REPLACE FUNCTION public.can_view_list(uuid, uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with l as (
  select event_id, visibility, created_by
  from public.lists
  where id = $1
),
excluded as (
  select exists(
    select 1 from public.list_exclusions
    where list_id = $1 and user_id = $2
  ) as x
)
select
  exists(select 1 from l)
  and (
    -- Creator always sees
    exists(select 1 from l where created_by = $2)
    or (
      not (select x from excluded) -- everyone else must NOT be excluded
      and (
        -- Recipient of this list
        exists(select 1 from public.list_recipients lr
               where lr.list_id = $1 and lr.user_id = $2)
        or
        -- Event-wide → any event member
        exists(select 1 from l where visibility = 'event'
               and exists (select 1 from public.event_members em
                           where em.event_id = l.event_id and em.user_id = $2))
        or
        -- Selected → explicit viewer
        exists(select 1 from l where visibility = 'selected'
               and exists (select 1 from public.list_viewers v
                           where v.list_id = $1 and v.user_id = $2))
      )
    )
  );
$function$
"
public,claim_counts_for_lists,p_list_ids uuid[],sql,true,s,"CREATE OR REPLACE FUNCTION public.claim_counts_for_lists(p_list_ids uuid[])
 RETURNS TABLE(list_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with items_by_list as (
    select i.id as item_id, i.list_id
    from public.items i
    where i.list_id = any(p_list_ids)
  )
  select ibl.list_id, count(c.id)::int as claim_count
  from items_by_list ibl
  left join public.claims c on c.item_id = ibl.item_id
  join public.lists l on l.id = ibl.list_id
  where public.can_view_list(l.id, auth.uid())  -- no leakage; only lists I can see
  group by ibl.list_id
$function$
"
public,claim_item,p_item_id uuid,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.claim_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid := auth.uid();
begin
  if u is null then
    raise exception 'not_authenticated';
  end if;

  if not can_claim_item(p_item_id, u) then
    raise exception 'not_authorized';
  end if;

  insert into public.claims(item_id, claimer_id)
  values (p_item_id, u)
  on conflict (item_id, claimer_id) do nothing;
end;
$function$
"
public,create_event_and_admin,"p_title text, p_event_date date, p_recurrence text, p_description text",plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.create_event_and_admin(p_title text, p_event_date date, p_recurrence text, p_description text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user uuid := auth.uid();
  v_event_id uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- If you’re enforcing the free limit, keep this; otherwise remove these 3 lines.
  if not public.can_create_event(v_user) then
    raise exception 'free_limit_reached';
  end if;

  -- IMPORTANT: set owner_id explicitly
  insert into public.events (title, description, event_date, owner_id, recurrence)
  values (p_title, p_description, p_event_date, v_user, coalesce(p_recurrence, 'none'))
  returning id into v_event_id;

  -- Make creator an admin member; avoid duplicate-key if user double-taps
  insert into public.event_members (event_id, user_id, role)
  values (v_event_id, v_user, 'admin')
  on conflict do nothing;

  return v_event_id;
end;
$function$
"
public,create_list_with_people,"p_event_id uuid, p_name text, p_visibility list_visibility, p_recipients uuid[], p_hidden_recipients uuid[], p_viewers uuid[]",plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_hidden_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  -- must be an event member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_an_event_member';
  end if;

  -- create the list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- recipients (per-recipient can_view flag)
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id, can_view)
    select v_list_id, r, not (r = any(coalesce(p_hidden_recipients, '{}')))
    from unnest(p_recipients) as r;
  end if;

  -- explicit viewers (only matters when visibility = 'selected')
  if coalesce(p_visibility, 'event') = 'selected'
     and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, v
    from unnest(p_viewers) as v;
  end if;

  return v_list_id;
end;
$function$
"
public,create_list_with_people,"p_event_id uuid, p_name text, p_visibility list_visibility, p_recipients uuid[], p_viewers uuid[]",plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.create_list_with_people(p_event_id uuid, p_name text, p_visibility list_visibility DEFAULT 'event'::list_visibility, p_recipients uuid[] DEFAULT '{}'::uuid[], p_viewers uuid[] DEFAULT '{}'::uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user    uuid := auth.uid();
  v_list_id uuid;
begin
  if v_user is null then
    raise exception 'not authenticated';
  end if;

  -- must be an event member
  if not public.is_event_member(p_event_id, v_user) then
    raise exception 'not_an_event_member';
  end if;

  -- create the list
  insert into public.lists (event_id, name, created_by, visibility)
  values (p_event_id, trim(p_name), v_user, coalesce(p_visibility, 'event'))
  returning id into v_list_id;

  -- recipients (required client-side, but we tolerate empty)
  if array_length(p_recipients, 1) is not null then
    insert into public.list_recipients (list_id, user_id)
    select v_list_id, unnest(p_recipients);
  end if;

  -- explicit viewers only when restricted
  if coalesce(p_visibility, 'event') = 'selected' and array_length(p_viewers, 1) is not null then
    insert into public.list_viewers (list_id, user_id)
    select v_list_id, unnest(p_viewers);
  end if;

  return v_list_id;
end;
$function$
"
public,delete_item,p_item_id uuid,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.delete_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_row record;
  v_is_admin boolean := false;
  v_is_list_owner boolean := false;
  v_is_item_owner boolean := false;
  v_has_claims boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select i.id, i.created_by as item_creator,
         l.id as list_id, l.created_by as list_creator, l.event_id
    into v_row
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = p_item_id;

  if not found then
    raise exception 'not_found';
  end if;

  v_is_item_owner := (v_row.item_creator = v_uid);
  v_is_list_owner := (v_row.list_creator = v_uid);
  v_is_admin := exists(
    select 1 from public.event_members em
    where em.event_id = v_row.event_id
      and em.user_id  = v_uid
      and em.role in ('admin','owner')
  );

  select exists(select 1 from public.claims c where c.item_id = p_item_id) into v_has_claims;

  if not (v_is_item_owner or v_is_list_owner or v_is_admin) then
    raise exception 'not_authorized';
  end if;

  if v_has_claims and not (v_is_admin or v_is_list_owner) then
    raise exception 'has_claims';
  end if;

  delete from public.claims where item_id = p_item_id;
  delete from public.items  where id      = p_item_id;
end
$function$
"
public,delete_list,p_list_id uuid,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.delete_list(p_list_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user   uuid := auth.uid();
  v_event  uuid;
  v_owner  uuid;
begin
  if v_user is null then
    raise exception 'not_authenticated';
  end if;

  select l.event_id, l.created_by
    into v_event, v_owner
  from public.lists l
  where l.id = p_list_id;

  if v_event is null then
    raise exception 'not_found';
  end if;

  -- Only the creator may delete (default)
  if v_owner <> v_user then
    -- Optional: allow event admins to delete too. Uncomment to enable.
    -- if not exists (
    --   select 1 from public.event_members em
    --   where em.event_id = v_event and em.user_id = v_user and em.role = 'admin'
    -- ) then
      raise exception 'not_authorized';
    -- end if;
  end if;

  delete from public.lists where id = p_list_id;
end;
$function$
"
public,ensure_event_owner_member,,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.ensure_event_owner_member()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.owner_id is not null then
    insert into public.event_members(event_id, user_id, role)
    values (new.id, new.owner_id, 'admin')
    on conflict (event_id, user_id)
    do update set role = excluded.role
    where event_members.role <> 'admin';
  end if;
  return new;
end;
$function$
"
public,event_claim_counts_for_user,p_event_ids uuid[],sql,true,s,"CREATE OR REPLACE FUNCTION public.event_claim_counts_for_user(p_event_ids uuid[])
 RETURNS TABLE(event_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  visible_lists as (
    select l.id, l.event_id
    from public.lists l, me
    where l.event_id = any(p_event_ids)
      and public.can_view_list(l.id, (select uid from me))
      -- hide counts for lists where I am a recipient
      and not exists (
        select 1 from public.list_recipients lr
        where lr.list_id = l.id
          and lr.user_id = (select uid from me)
      )
  ),

  items_by_event as (
    select i.id as item_id, vl.event_id
    from public.items i
    join visible_lists vl on vl.id = i.list_id
  ),

  claims_on_visible as (
    select ibe.event_id
    from public.claims c
    join items_by_event ibe on ibe.item_id = c.item_id
  )

  select event_id, count(*)::int as claim_count
  from claims_on_visible
  group by event_id;
$function$
"
public,event_id_for_item,i_id uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.event_id_for_item(i_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select l.event_id
  from public.items i
  join public.lists l on l.id = i.list_id
  where i.id = i_id
$function$
"
public,event_id_for_list,uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.event_id_for_list(uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT event_id FROM public.lists WHERE id = $1
$function$
"
public,event_is_accessible,"p_event_id uuid, p_user uuid",sql,true,s,"CREATE OR REPLACE FUNCTION public.event_is_accessible(p_event_id uuid, p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with ranked as (
    select e.id,
           row_number() over (partition by em.user_id order by e.created_at, e.id) rn
    from public.events e
    join public.event_members em on em.event_id = e.id
    where em.user_id = p_user
  )
  select case
    when public.is_pro(p_user, now()) then true
    else exists(select 1 from ranked r where r.id = p_event_id and r.rn <= 3)
  end;
$function$
"
public,events_for_current_user,,sql,true,s,"CREATE OR REPLACE FUNCTION public.events_for_current_user()
 RETURNS TABLE(id uuid, title text, event_date date, join_code text, created_at timestamp with time zone, member_count bigint, total_items bigint, claimed_count bigint, accessible boolean, rownum integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),
  my_events as (
    select e.*
    from events e
    join event_members em on em.event_id = e.id
    join me on me.uid = em.user_id
  ),
  counts as (
    select
      l.event_id,
      count(distinct l.id) as list_count,
      count(i.id)          as total_items
    from lists l
    left join items i on i.list_id = l.id
    group by l.event_id
  ),
  claims as (
    select l.event_id, count(distinct c.id) as claimed_count
    from lists l
    join items i on i.list_id = l.id
    left join claims c on c.item_id = i.id
    group by l.event_id
  ),
  ranked as (
    select
      e.id, e.title, e.event_date, e.join_code, e.created_at,
      (select count(*) from event_members em2 where em2.event_id = e.id) as member_count,
      coalesce(ct.total_items, 0) as total_items,
      coalesce(cl.claimed_count, 0) as claimed_count,
      row_number() over (order by e.created_at desc nulls last, e.id) as rownum
    from my_events e
    left join counts ct on ct.event_id = e.id
    left join claims cl on cl.event_id = e.id
  )
  select
    r.id, r.title, r.event_date, r.join_code, r.created_at,
    r.member_count, r.total_items, r.claimed_count,
    (r.rownum <= public.allowed_event_slots()) as accessible,
    r.rownum
  from ranked r
  order by r.created_at desc nulls last, r.id;
$function$
"
public,handle_new_user,,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    null
  )
  on conflict (id) do update set display_name = excluded.display_name;
  return new;
end;
$function$
"
public,is_event_admin,"e_id uuid, u_id uuid",sql,true,s,"CREATE OR REPLACE FUNCTION public.is_event_admin(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.event_members em where em.event_id=e_id and em.user_id=u_id and em.role='admin')
$function$
"
public,is_event_member,"e_id uuid, u_id uuid",sql,true,s,"CREATE OR REPLACE FUNCTION public.is_event_member(e_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(select 1 from public.event_members em
                where em.event_id = e_id and em.user_id = u_id)
$function$
"
public,is_list_recipient,"l_id uuid, u_id uuid",sql,true,s,"CREATE OR REPLACE FUNCTION public.is_list_recipient(l_id uuid, u_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists(
    select 1
    from public.list_recipients lr
    where lr.list_id = l_id and lr.user_id = u_id
  )
$function$
"
public,is_member_of_event,p_event uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.is_member_of_event(p_event uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.event_members em
    WHERE em.event_id = p_event
      AND em.user_id  = auth.uid()
  );
$function$
"
public,is_pro,p_user uuid,sql,false,s,"CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select public.is_pro(p_user, now());
$function$
"
public,is_pro,"p_user uuid, p_at timestamp with time zone",sql,false,s,"CREATE OR REPLACE FUNCTION public.is_pro(p_user uuid, p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(
    (select (plan = 'pro') or (pro_until is not null and pro_until >= p_at)
       from public.profiles where id = p_user),
    false
  );
$function$
"
public,is_pro_v2,"p_user uuid, p_at timestamp with time zone",plpgsql,true,s,"CREATE OR REPLACE FUNCTION public.is_pro_v2(p_user uuid, p_at timestamp with time zone DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  until_ts timestamptz;
begin
  if p_user is null then
    return false;
  end if;

  -- If the table hasn't been created yet, treat as Free (no error)
  if to_regclass('public.user_plans') is null then
    return false;
  end if;

  select pro_until into until_ts
  from public.user_plans
  where user_id = p_user;

  return coalesce(until_ts >= p_at, false);
end;
$function$
"
public,join_event,p_code text,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.join_event(p_code text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_event_id uuid;
  v_user_id  uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not authenticated';
  end if;

  -- Find event by code (case-insensitive, trimmed)
  select id
    into v_event_id
  from public.events
  where upper(join_code) = upper(trim(p_code))
  limit 1;

  if v_event_id is null then
    raise exception 'invalid_join_code';
  end if;

  insert into public.event_members(event_id, user_id, role)
  values (v_event_id, v_user_id, 'giver')
  on conflict (event_id, user_id) do nothing;

  return v_event_id;
end;
$function$
"
public,leave_event,p_event_id uuid,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.leave_event(p_event_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role public.member_role;  -- your enum type
  v_owner uuid;
  v_remaining integer;
  v_admins integer;
  v_new_admin uuid;
  v_deleted boolean := false;
  v_transferred boolean := false;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- must be a member
  select role into v_role
  from public.event_members
  where event_id = p_event_id and user_id = v_uid;
  if not found then
    raise exception 'not_member';
  end if;

  -- current owner
  select owner_id into v_owner from public.events where id = p_event_id;

  -- remove my claims (within this event)
  delete from public.claims c
  using public.items i, public.lists l
  where c.item_id = i.id
    and i.list_id = l.id
    and l.event_id = p_event_id
    and c.claimer_id = v_uid;

  -- remove me as recipient in lists of this event
  delete from public.list_recipients lr
  using public.lists l2
  where lr.list_id = l2.id
    and l2.event_id = p_event_id
    and lr.user_id = v_uid;

  -- remove my membership
  delete from public.event_members
  where event_id = p_event_id and user_id = v_uid;

  -- anyone left?
  select count(*) into v_remaining
  from public.event_members
  where event_id = p_event_id;

  if v_remaining = 0 then
    delete from public.events where id = p_event_id;
    v_deleted := true;
    return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', null);
  end if;

  -- ensure at least one admin remains (ONLY check role='admin')
  select count(*) into v_admins
  from public.event_members
  where event_id = p_event_id and role = 'admin';

  if v_admins = 0 then
    -- promote someone
    select public._pick_new_admin(p_event_id) into v_new_admin;
    if v_new_admin is not null then
      update public.event_members
      set role = 'admin'
      where event_id = p_event_id and user_id = v_new_admin;
      v_transferred := true;
    end if;
  end if;

  -- if the leaver was the owner, assign owner to an existing admin if any,
  -- otherwise to the newly promoted admin (v_new_admin)
  if v_owner = v_uid then
    -- try an existing admin first
    select user_id into v_new_admin
    from public.event_members
    where event_id = p_event_id and role = 'admin'
    limit 1;

    if v_new_admin is null then
      -- fallback: pick any member
      select public._pick_new_admin(p_event_id) into v_new_admin;
    end if;

    if v_new_admin is not null then
      update public.events set owner_id = v_new_admin where id = p_event_id;
      v_transferred := true;
    end if;
  end if;

  return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', v_new_admin);
end
$function$
"
public,list_claim_counts_for_user,p_list_ids uuid[],sql,true,s,"CREATE OR REPLACE FUNCTION public.list_claim_counts_for_user(p_list_ids uuid[])
 RETURNS TABLE(list_id uuid, claim_count integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  visible_lists as (
    select l.id, l.event_id
    from public.lists l, me
    where l.id = any(p_list_ids)
      and public.can_view_list(l.id, (select uid from me))
  ),

  items_by_list as (
    select i.id as item_id, i.list_id
    from public.items i
    join visible_lists vl on vl.id = i.list_id
  ),

  -- lists where I am NOT a recipient (I can see total claims)
  non_recipient_lists as (
    select vl.id as list_id
    from visible_lists vl, me
    where not exists (
      select 1 from public.list_recipients lr
      where lr.list_id = vl.id
        and lr.user_id = (select uid from me)
    )
  ),

  -- claims everyone (non-recipients) can see on visible lists
  claims_viewable as (
    select i.list_id
    from public.claims c
    join items_by_list i on i.item_id = c.item_id
    where exists (
      select 1 from non_recipient_lists n
      where n.list_id = i.list_id
    )
  ),

  -- always include MY own claims so my UI stays in sync
  my_claims as (
    select i.list_id
    from public.claims c
    join items_by_list i on i.item_id = c.item_id
    where c.claimer_id = (select uid from me)
  ),

  merged as (
    select list_id from claims_viewable
    union all
    select list_id from my_claims
  )

  select list_id, count(*)::int as claim_count
  from merged
  group by list_id;
$function$
"
public,list_claims_for_user,p_item_ids uuid[],sql,true,s,"CREATE OR REPLACE FUNCTION public.list_claims_for_user(p_item_ids uuid[])
 RETURNS TABLE(item_id uuid, claimer_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with me as (select auth.uid() as uid),

  -- Items I can view (honor your can_view_list logic)
  visible_items as (
    select i.id as item_id, i.list_id
    from public.items i, me
    where i.id = any(p_item_ids)
      and public.can_view_list(i.list_id, (select uid from me))
  ),

  -- For non-recipients: show all claims on visible items
  non_recipient_items as (
    select vi.item_id
    from visible_items vi, me
    where not exists (
      select 1
      from public.list_recipients lr
      where lr.list_id = vi.list_id
        and lr.user_id = (select uid from me)
    )
  ),

  claims_for_viewers as (
    select c.item_id, c.claimer_id
    from public.claims c
    join non_recipient_items n on n.item_id = c.item_id
  ),

  -- Always include my own claim so my button becomes ""Unclaim""
  my_claims as (
    select c.item_id, c.claimer_id
    from public.claims c, me
    where c.item_id = any(p_item_ids)
      and c.claimer_id = (select uid from me)
  )

  select * from claims_for_viewers
  union
  select * from my_claims;
$function$
"
public,list_id_for_item,i_id uuid,sql,true,s,"CREATE OR REPLACE FUNCTION public.list_id_for_item(i_id uuid)
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select list_id from public.items where id = i_id
$function$
"
public,remove_member,"p_event_id uuid, p_user_id uuid",plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.remove_member(p_event_id uuid, p_user_id uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_actor uuid := auth.uid();
  v_actor_role public.member_role;
  v_owner uuid;
  v_target_role public.member_role;
  v_remaining integer;
  v_admins integer;
  v_new_admin uuid;
  v_deleted boolean := false;
  v_transferred boolean := false;
  v_actor_is_owner boolean := false;
begin
  if v_actor is null then
    raise exception 'not_authenticated';
  end if;
  if p_user_id = v_actor then
    raise exception 'use_leave_event_for_self';
  end if;

  -- actor must be a member
  select role into v_actor_role
  from public.event_members
  where event_id = p_event_id and user_id = v_actor;
  if not found then
    raise exception 'not_member';
  end if;

  -- event owner
  select owner_id into v_owner from public.events where id = p_event_id;
  v_actor_is_owner := (v_owner = v_actor);

  -- require admin role OR owner of the event
  if v_actor_role <> 'admin' and not v_actor_is_owner then
    raise exception 'not_authorized';
  end if;

  -- target must be a member
  select role into v_target_role
  from public.event_members
  where event_id = p_event_id and user_id = p_user_id;
  if not found then
    raise exception 'target_not_member';
  end if;

  -- cleanup target's claims and recipient entries inside this event
  delete from public.claims c
  using public.items i, public.lists l
  where c.item_id = i.id
    and i.list_id = l.id
    and l.event_id = p_event_id
    and c.claimer_id = p_user_id;

  delete from public.list_recipients lr
  using public.lists l2
  where lr.list_id = l2.id
    and l2.event_id = p_event_id
    and lr.user_id = p_user_id;

  -- remove membership
  delete from public.event_members
  where event_id = p_event_id and user_id = p_user_id;

  -- anyone left?
  select count(*) into v_remaining
  from public.event_members
  where event_id = p_event_id;

  if v_remaining = 0 then
    delete from public.events where id = p_event_id;
    v_deleted := true;
    return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', null);
  end if;

  -- if target was admin, ensure at least one admin remains
  if v_target_role = 'admin' then
    select count(*) into v_admins
    from public.event_members
    where event_id = p_event_id and role = 'admin';

    if v_admins = 0 then
      select public._pick_new_admin(p_event_id) into v_new_admin;
      if v_new_admin is not null then
        update public.event_members
        set role = 'admin'
        where event_id = p_event_id and user_id = v_new_admin;
        v_transferred := true;
      end if;
    end if;
  end if;

  -- if target was owner, transfer ownership to an existing admin if any,
  -- otherwise to the newly promoted admin, otherwise to any member.
  if v_owner = p_user_id then
    -- prefer an existing admin
    select user_id into v_new_admin
    from public.event_members
    where event_id = p_event_id and role = 'admin'
    limit 1;

    if v_new_admin is null then
      -- fall back to anyone (maybe promoted above)
      select public._pick_new_admin(p_event_id) into v_new_admin;
    end if;

    if v_new_admin is not null then
      update public.events set owner_id = v_new_admin where id = p_event_id;
      v_transferred := true;
    end if;
  end if;

  return json_build_object('removed', true, 'deleted_event', v_deleted, 'transferred', v_transferred, 'new_admin', v_new_admin);
end
$function$
"
public,rollover_all_due_events,,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.rollover_all_due_events()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_count int := 0;
  rec record;
  v_new date;
begin
  for rec in
    select e.id, e.event_date, e.recurrence
    from public.events e
    where e.recurrence <> 'none'
      and e.event_date is not null
      and e.event_date <= current_date
      and (e.last_rolled_at is null or e.last_rolled_at < e.event_date)
  loop
    -- Remove ONLY items that had at least one claim
    delete from public.items i
    using public.lists l
    where i.list_id = l.id
      and l.event_id = rec.id
      and exists (select 1 from public.claims c where c.item_id = i.id);

    -- Clean up any orphan claims just in case
    delete from public.claims c
    where not exists (select 1 from public.items i where i.id = c.item_id);

    -- Compute the next occurrence strictly after today
    v_new := _next_occurrence(rec.event_date, rec.recurrence, 1);
    while v_new <= current_date loop
      v_new := _next_occurrence(v_new, rec.recurrence, 1);
    end loop;

    update public.events
       set event_date     = v_new,
           last_rolled_at = current_date
     where id = rec.id;

    v_count := v_count + 1;
  end loop;

  return v_count;
end
$function$
"
public,set_list_created_by,,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.set_list_created_by()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.created_by is null then
    new.created_by := auth.uid();
  end if;
  return new;
end;
$function$
"
public,set_onboarding_done,p_done boolean,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.set_onboarding_done(p_done boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  update public.profiles
  set onboarding_done = coalesce(p_done, true),
      onboarding_at   = case when coalesce(p_done, true) then now() else null end
  where id = auth.uid();
end
$function$
"
public,set_plan,"p_plan text, p_months integer, p_user uuid",plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.set_plan(p_plan text, p_months integer DEFAULT 0, p_user uuid DEFAULT auth.uid())
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_plan = 'pro' then
    update public.profiles
       set plan = 'pro',
           pro_until = case when p_months > 0 then now() + (p_months||' months')::interval else null end
     where id = p_user;
  else
    update public.profiles
       set plan = 'free',
           pro_until = null
     where id = p_user;
  end if;
end;
$function$
"
public,set_profile_name,p_name text,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.set_profile_name(p_name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.profiles (id, display_name)
  values (auth.uid(), p_name)
  on conflict (id) do update set display_name = excluded.display_name;
end;
$function$
"
public,tg_set_timestamp,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION public.tg_set_timestamp()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
"
public,unclaim_item,p_item_id uuid,plpgsql,true,v,"CREATE OR REPLACE FUNCTION public.unclaim_item(p_item_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  u uuid := auth.uid();
begin
  if u is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.claims
  where item_id = p_item_id
    and claimer_id = u;
end;
$function$
"
public,whoami,,sql,true,s,"CREATE OR REPLACE FUNCTION public.whoami()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'uid', auth.uid(),
    'role', current_setting('request.jwt.claim.role', true)
  );
$function$
"
realtime,apply_rls,"wal jsonb, max_record_bytes integer",plpgsql,false,v,"CREATE OR REPLACE FUNCTION realtime.apply_rls(wal jsonb, max_record_bytes integer DEFAULT (1024 * 1024))
 RETURNS SETOF realtime.wal_rls
 LANGUAGE plpgsql
AS $function$
declare
-- Regclass of the table e.g. public.notes
entity_ regclass = (quote_ident(wal ->> 'schema') || '.' || quote_ident(wal ->> 'table'))::regclass;

-- I, U, D, T: insert, update ...
action realtime.action = (
    case wal ->> 'action'
        when 'I' then 'INSERT'
        when 'U' then 'UPDATE'
        when 'D' then 'DELETE'
        else 'ERROR'
    end
);

-- Is row level security enabled for the table
is_rls_enabled bool = relrowsecurity from pg_class where oid = entity_;

subscriptions realtime.subscription[] = array_agg(subs)
    from
        realtime.subscription subs
    where
        subs.entity = entity_;

-- Subscription vars
roles regrole[] = array_agg(distinct us.claims_role::text)
    from
        unnest(subscriptions) us;

working_role regrole;
claimed_role regrole;
claims jsonb;

subscription_id uuid;
subscription_has_access bool;
visible_to_subscription_ids uuid[] = '{}';

-- structured info for wal's columns
columns realtime.wal_column[];
-- previous identity values for update/delete
old_columns realtime.wal_column[];

error_record_exceeds_max_size boolean = octet_length(wal::text) > max_record_bytes;

-- Primary jsonb output for record
output jsonb;

begin
perform set_config('role', null, true);

columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'columns') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

old_columns =
    array_agg(
        (
            x->>'name',
            x->>'type',
            x->>'typeoid',
            realtime.cast(
                (x->'value') #>> '{}',
                coalesce(
                    (x->>'typeoid')::regtype, -- null when wal2json version <= 2.4
                    (x->>'type')::regtype
                )
            ),
            (pks ->> 'name') is not null,
            true
        )::realtime.wal_column
    )
    from
        jsonb_array_elements(wal -> 'identity') x
        left join jsonb_array_elements(wal -> 'pk') pks
            on (x ->> 'name') = (pks ->> 'name');

for working_role in select * from unnest(roles) loop

    -- Update `is_selectable` for columns and old_columns
    columns =
        array_agg(
            (
                c.name,
                c.type_name,
                c.type_oid,
                c.value,
                c.is_pkey,
                pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
            )::realtime.wal_column
        )
        from
            unnest(columns) c;

    old_columns =
            array_agg(
                (
                    c.name,
                    c.type_name,
                    c.type_oid,
                    c.value,
                    c.is_pkey,
                    pg_catalog.has_column_privilege(working_role, entity_, c.name, 'SELECT')
                )::realtime.wal_column
            )
            from
                unnest(old_columns) c;

    if action <> 'DELETE' and count(1) = 0 from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            -- subscriptions is already filtered by entity
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 400: Bad Request, no primary key']
        )::realtime.wal_rls;

    -- The claims role does not have SELECT permission to the primary key of entity
    elsif action <> 'DELETE' and sum(c.is_selectable::int) <> count(1) from unnest(columns) c where c.is_pkey then
        return next (
            jsonb_build_object(
                'schema', wal ->> 'schema',
                'table', wal ->> 'table',
                'type', action
            ),
            is_rls_enabled,
            (select array_agg(s.subscription_id) from unnest(subscriptions) as s where claims_role = working_role),
            array['Error 401: Unauthorized']
        )::realtime.wal_rls;

    else
        output = jsonb_build_object(
            'schema', wal ->> 'schema',
            'table', wal ->> 'table',
            'type', action,
            'commit_timestamp', to_char(
                ((wal ->> 'timestamp')::timestamptz at time zone 'utc'),
                'YYYY-MM-DD""T""HH24:MI:SS.MS""Z""'
            ),
            'columns', (
                select
                    jsonb_agg(
                        jsonb_build_object(
                            'name', pa.attname,
                            'type', pt.typname
                        )
                        order by pa.attnum asc
                    )
                from
                    pg_attribute pa
                    join pg_type pt
                        on pa.atttypid = pt.oid
                where
                    attrelid = entity_
                    and attnum > 0
                    and pg_catalog.has_column_privilege(working_role, entity_, pa.attname, 'SELECT')
            )
        )
        -- Add ""record"" key for insert and update
        || case
            when action in ('INSERT', 'UPDATE') then
                jsonb_build_object(
                    'record',
                    (
                        select
                            jsonb_object_agg(
                                -- if unchanged toast, get column name and value from old record
                                coalesce((c).name, (oc).name),
                                case
                                    when (c).name is null then (oc).value
                                    else (c).value
                                end
                            )
                        from
                            unnest(columns) c
                            full outer join unnest(old_columns) oc
                                on (c).name = (oc).name
                        where
                            coalesce((c).is_selectable, (oc).is_selectable)
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                    )
                )
            else '{}'::jsonb
        end
        -- Add ""old_record"" key for update and delete
        || case
            when action = 'UPDATE' then
                jsonb_build_object(
                        'old_record',
                        (
                            select jsonb_object_agg((c).name, (c).value)
                            from unnest(old_columns) c
                            where
                                (c).is_selectable
                                and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                        )
                    )
            when action = 'DELETE' then
                jsonb_build_object(
                    'old_record',
                    (
                        select jsonb_object_agg((c).name, (c).value)
                        from unnest(old_columns) c
                        where
                            (c).is_selectable
                            and ( not error_record_exceeds_max_size or (octet_length((c).value::text) <= 64))
                            and ( not is_rls_enabled or (c).is_pkey ) -- if RLS enabled, we can't secure deletes so filter to pkey
                    )
                )
            else '{}'::jsonb
        end;

        -- Create the prepared statement
        if is_rls_enabled and action <> 'DELETE' then
            if (select 1 from pg_prepared_statements where name = 'walrus_rls_stmt' limit 1) > 0 then
                deallocate walrus_rls_stmt;
            end if;
            execute realtime.build_prepared_statement_sql('walrus_rls_stmt', entity_, columns);
        end if;

        visible_to_subscription_ids = '{}';

        for subscription_id, claims in (
                select
                    subs.subscription_id,
                    subs.claims
                from
                    unnest(subscriptions) subs
                where
                    subs.entity = entity_
                    and subs.claims_role = working_role
                    and (
                        realtime.is_visible_through_filters(columns, subs.filters)
                        or (
                          action = 'DELETE'
                          and realtime.is_visible_through_filters(old_columns, subs.filters)
                        )
                    )
        ) loop

            if not is_rls_enabled or action = 'DELETE' then
                visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
            else
                -- Check if RLS allows the role to see the record
                perform
                    -- Trim leading and trailing quotes from working_role because set_config
                    -- doesn't recognize the role as valid if they are included
                    set_config('role', trim(both '""' from working_role::text), true),
                    set_config('request.jwt.claims', claims::text, true);

                execute 'execute walrus_rls_stmt' into subscription_has_access;

                if subscription_has_access then
                    visible_to_subscription_ids = visible_to_subscription_ids || subscription_id;
                end if;
            end if;
        end loop;

        perform set_config('role', null, true);

        return next (
            output,
            is_rls_enabled,
            visible_to_subscription_ids,
            case
                when error_record_exceeds_max_size then array['Error 413: Payload Too Large']
                else '{}'
            end
        )::realtime.wal_rls;

    end if;
end loop;

perform set_config('role', null, true);
end;
$function$
"
realtime,broadcast_changes,"topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text",plpgsql,false,v,"CREATE OR REPLACE FUNCTION realtime.broadcast_changes(topic_name text, event_name text, operation text, table_name text, table_schema text, new record, old record, level text DEFAULT 'ROW'::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Declare a variable to hold the JSONB representation of the row
    row_data jsonb := '{}'::jsonb;
BEGIN
    IF level = 'STATEMENT' THEN
        RAISE EXCEPTION 'function can only be triggered for each row, not for each statement';
    END IF;
    -- Check the operation type and handle accordingly
    IF operation = 'INSERT' OR operation = 'UPDATE' OR operation = 'DELETE' THEN
        row_data := jsonb_build_object('old_record', OLD, 'record', NEW, 'operation', operation, 'table', table_name, 'schema', table_schema);
        PERFORM realtime.send (row_data, event_name, topic_name);
    ELSE
        RAISE EXCEPTION 'Unexpected operation type: %', operation;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to process the row: %', SQLERRM;
END;

$function$
"
realtime,build_prepared_statement_sql,"prepared_statement_name text, entity regclass, columns realtime.wal_column[]",sql,false,v,"CREATE OR REPLACE FUNCTION realtime.build_prepared_statement_sql(prepared_statement_name text, entity regclass, columns realtime.wal_column[])
 RETURNS text
 LANGUAGE sql
AS $function$
      /*
      Builds a sql string that, if executed, creates a prepared statement to
      tests retrive a row from *entity* by its primary key columns.
      Example
          select realtime.build_prepared_statement_sql('public.notes', '{""id""}'::text[], '{""bigint""}'::text[])
      */
          select
      'prepare ' || prepared_statement_name || ' as
          select
              exists(
                  select
                      1
                  from
                      ' || entity || '
                  where
                      ' || string_agg(quote_ident(pkc.name) || '=' || quote_nullable(pkc.value #>> '{}') , ' and ') || '
              )'
          from
              unnest(columns) pkc
          where
              pkc.is_pkey
          group by
              entity
      $function$
"
realtime,cast,"val text, type_ regtype",plpgsql,false,i,"CREATE OR REPLACE FUNCTION realtime.""cast""(val text, type_ regtype)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
    declare
      res jsonb;
    begin
      execute format('select to_jsonb(%L::'|| type_::text || ')', val)  into res;
      return res;
    end
    $function$
"
realtime,check_equality_op,"op realtime.equality_op, type_ regtype, val_1 text, val_2 text",plpgsql,false,i,"CREATE OR REPLACE FUNCTION realtime.check_equality_op(op realtime.equality_op, type_ regtype, val_1 text, val_2 text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
      /*
      Casts *val_1* and *val_2* as type *type_* and check the *op* condition for truthiness
      */
      declare
          op_symbol text = (
              case
                  when op = 'eq' then '='
                  when op = 'neq' then '!='
                  when op = 'lt' then '<'
                  when op = 'lte' then '<='
                  when op = 'gt' then '>'
                  when op = 'gte' then '>='
                  when op = 'in' then '= any'
                  else 'UNKNOWN OP'
              end
          );
          res boolean;
      begin
          execute format(
              'select %L::'|| type_::text || ' ' || op_symbol
              || ' ( %L::'
              || (
                  case
                      when op = 'in' then type_::text || '[]'
                      else type_::text end
              )
              || ')', val_1, val_2) into res;
          return res;
      end;
      $function$
"
realtime,is_visible_through_filters,"columns realtime.wal_column[], filters realtime.user_defined_filter[]",sql,false,i,"CREATE OR REPLACE FUNCTION realtime.is_visible_through_filters(columns realtime.wal_column[], filters realtime.user_defined_filter[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    /*
    Should the record be visible (true) or filtered out (false) after *filters* are applied
    */
        select
            -- Default to allowed when no filters present
            $2 is null -- no filters. this should not happen because subscriptions has a default
            or array_length($2, 1) is null -- array length of an empty array is null
            or bool_and(
                coalesce(
                    realtime.check_equality_op(
                        op:=f.op,
                        type_:=coalesce(
                            col.type_oid::regtype, -- null when wal2json version <= 2.4
                            col.type_name::regtype
                        ),
                        -- cast jsonb to text
                        val_1:=col.value #>> '{}',
                        val_2:=f.value
                    ),
                    false -- if null, filter does not match
                )
            )
        from
            unnest(filters) f
            join unnest(columns) col
                on f.column_name = col.name;
    $function$
"
realtime,list_changes,"publication name, slot_name name, max_changes integer, max_record_bytes integer",sql,false,v,"CREATE OR REPLACE FUNCTION realtime.list_changes(publication name, slot_name name, max_changes integer, max_record_bytes integer)
 RETURNS SETOF realtime.wal_rls
 LANGUAGE sql
 SET log_min_messages TO 'fatal'
AS $function$
      with pub as (
        select
          concat_ws(
            ',',
            case when bool_or(pubinsert) then 'insert' else null end,
            case when bool_or(pubupdate) then 'update' else null end,
            case when bool_or(pubdelete) then 'delete' else null end
          ) as w2j_actions,
          coalesce(
            string_agg(
              realtime.quote_wal2json(format('%I.%I', schemaname, tablename)::regclass),
              ','
            ) filter (where ppt.tablename is not null and ppt.tablename not like '% %'),
            ''
          ) w2j_add_tables
        from
          pg_publication pp
          left join pg_publication_tables ppt
            on pp.pubname = ppt.pubname
        where
          pp.pubname = publication
        group by
          pp.pubname
        limit 1
      ),
      w2j as (
        select
          x.*, pub.w2j_add_tables
        from
          pub,
          pg_logical_slot_get_changes(
            slot_name, null, max_changes,
            'include-pk', 'true',
            'include-transaction', 'false',
            'include-timestamp', 'true',
            'include-type-oids', 'true',
            'format-version', '2',
            'actions', pub.w2j_actions,
            'add-tables', pub.w2j_add_tables
          ) x
      )
      select
        xyz.wal,
        xyz.is_rls_enabled,
        xyz.subscription_ids,
        xyz.errors
      from
        w2j,
        realtime.apply_rls(
          wal := w2j.data::jsonb,
          max_record_bytes := max_record_bytes
        ) xyz(wal, is_rls_enabled, subscription_ids, errors)
      where
        w2j.w2j_add_tables <> ''
        and xyz.subscription_ids[1] is not null
    $function$
"
realtime,quote_wal2json,entity regclass,sql,false,i,"CREATE OR REPLACE FUNCTION realtime.quote_wal2json(entity regclass)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
      select
        (
          select string_agg('' || ch,'')
          from unnest(string_to_array(nsp.nspname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '""')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '""'
            )
        )
        || '.'
        || (
          select string_agg('' || ch,'')
          from unnest(string_to_array(pc.relname::text, null)) with ordinality x(ch, idx)
          where
            not (x.idx = 1 and x.ch = '""')
            and not (
              x.idx = array_length(string_to_array(nsp.nspname::text, null), 1)
              and x.ch = '""'
            )
          )
      from
        pg_class pc
        join pg_namespace nsp
          on pc.relnamespace = nsp.oid
      where
        pc.oid = entity
    $function$
"
realtime,send,"payload jsonb, event text, topic text, private boolean",plpgsql,false,v,"CREATE OR REPLACE FUNCTION realtime.send(payload jsonb, event text, topic text, private boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  BEGIN
    -- Set the topic configuration
    EXECUTE format('SET LOCAL realtime.topic TO %L', topic);

    -- Attempt to insert the message
    INSERT INTO realtime.messages (payload, event, topic, private, extension)
    VALUES (payload, event, topic, private, 'broadcast');
  EXCEPTION
    WHEN OTHERS THEN
      -- Capture and notify the error
      RAISE WARNING 'ErrorSendingBroadcastMessage: %', SQLERRM;
  END;
END;
$function$
"
realtime,subscription_check_filters,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION realtime.subscription_check_filters()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
    /*
    Validates that the user defined filters for a subscription:
    - refer to valid columns that the claimed role may access
    - values are coercable to the correct column type
    */
    declare
        col_names text[] = coalesce(
                array_agg(c.column_name order by c.ordinal_position),
                '{}'::text[]
            )
            from
                information_schema.columns c
            where
                format('%I.%I', c.table_schema, c.table_name)::regclass = new.entity
                and pg_catalog.has_column_privilege(
                    (new.claims ->> 'role'),
                    format('%I.%I', c.table_schema, c.table_name)::regclass,
                    c.column_name,
                    'SELECT'
                );
        filter realtime.user_defined_filter;
        col_type regtype;

        in_val jsonb;
    begin
        for filter in select * from unnest(new.filters) loop
            -- Filtered column is valid
            if not filter.column_name = any(col_names) then
                raise exception 'invalid column for filter %', filter.column_name;
            end if;

            -- Type is sanitized and safe for string interpolation
            col_type = (
                select atttypid::regtype
                from pg_catalog.pg_attribute
                where attrelid = new.entity
                      and attname = filter.column_name
            );
            if col_type is null then
                raise exception 'failed to lookup type for column %', filter.column_name;
            end if;

            -- Set maximum number of entries for in filter
            if filter.op = 'in'::realtime.equality_op then
                in_val = realtime.cast(filter.value, (col_type::text || '[]')::regtype);
                if coalesce(jsonb_array_length(in_val), 0) > 100 then
                    raise exception 'too many values for `in` filter. Maximum 100';
                end if;
            else
                -- raises an exception if value is not coercable to type
                perform realtime.cast(filter.value, col_type);
            end if;

        end loop;

        -- Apply consistent order to filters so the unique constraint on
        -- (subscription_id, entity, filters) can't be tricked by a different filter order
        new.filters = coalesce(
            array_agg(f order by f.column_name, f.op, f.value),
            '{}'
        ) from unnest(new.filters) f;

        return new;
    end;
    $function$
"
realtime,to_regrole,role_name text,sql,false,i,"CREATE OR REPLACE FUNCTION realtime.to_regrole(role_name text)
 RETURNS regrole
 LANGUAGE sql
 IMMUTABLE
AS $function$ select role_name::regrole $function$
"
realtime,topic,,sql,false,s,"CREATE OR REPLACE FUNCTION realtime.topic()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
select nullif(current_setting('realtime.topic', true), '')::text;
$function$
"
storage,add_prefixes,"_bucket_id text, _name text",plpgsql,true,v,"CREATE OR REPLACE FUNCTION storage.add_prefixes(_bucket_id text, _name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    prefixes text[];
BEGIN
    prefixes := ""storage"".""get_prefixes""(""_name"");

    IF array_length(prefixes, 1) > 0 THEN
        INSERT INTO storage.prefixes (name, bucket_id)
        SELECT UNNEST(prefixes) as name, ""_bucket_id"" ON CONFLICT DO NOTHING;
    END IF;
END;
$function$
"
storage,can_insert_object,"bucketid text, name text, owner uuid, metadata jsonb",plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.can_insert_object(bucketid text, name text, owner uuid, metadata jsonb)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
BEGIN
  INSERT INTO ""storage"".""objects"" (""bucket_id"", ""name"", ""owner"", ""metadata"") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$function$
"
storage,delete_prefix,"_bucket_id text, _name text",plpgsql,true,v,"CREATE OR REPLACE FUNCTION storage.delete_prefix(_bucket_id text, _name text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
    -- Check if we can delete the prefix
    IF EXISTS(
        SELECT FROM ""storage"".""prefixes""
        WHERE ""prefixes"".""bucket_id"" = ""_bucket_id""
          AND level = ""storage"".""get_level""(""_name"") + 1
          AND ""prefixes"".""name"" COLLATE ""C"" LIKE ""_name"" || '/%'
        LIMIT 1
    )
    OR EXISTS(
        SELECT FROM ""storage"".""objects""
        WHERE ""objects"".""bucket_id"" = ""_bucket_id""
          AND ""storage"".""get_level""(""objects"".""name"") = ""storage"".""get_level""(""_name"") + 1
          AND ""objects"".""name"" COLLATE ""C"" LIKE ""_name"" || '/%'
        LIMIT 1
    ) THEN
    -- There are sub-objects, skip deletion
    RETURN false;
    ELSE
        DELETE FROM ""storage"".""prefixes""
        WHERE ""prefixes"".""bucket_id"" = ""_bucket_id""
          AND level = ""storage"".""get_level""(""_name"")
          AND ""prefixes"".""name"" = ""_name"";
        RETURN true;
    END IF;
END;
$function$
"
storage,delete_prefix_hierarchy_trigger,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.delete_prefix_hierarchy_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    prefix text;
BEGIN
    prefix := ""storage"".""get_prefix""(OLD.""name"");

    IF coalesce(prefix, '') != '' THEN
        PERFORM ""storage"".""delete_prefix""(OLD.""bucket_id"", prefix);
    END IF;

    RETURN OLD;
END;
$function$
"
storage,enforce_bucket_name_length,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.enforce_bucket_name_length()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name ""%"" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$function$
"
storage,extension,name text,plpgsql,false,i,"CREATE OR REPLACE FUNCTION storage.extension(name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    SELECT _parts[array_length(_parts,1)] INTO _filename;
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$function$
"
storage,filename,name text,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.filename(name text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
_parts text[];
BEGIN
	select string_to_array(name, '/') into _parts;
	return _parts[array_length(_parts,1)];
END
$function$
"
storage,foldername,name text,plpgsql,false,i,"CREATE OR REPLACE FUNCTION storage.foldername(name text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
BEGIN
    -- Split on ""/"" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$function$
"
storage,get_level,name text,sql,false,i,"CREATE OR REPLACE FUNCTION storage.get_level(name text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
SELECT array_length(string_to_array(""name"", '/'), 1);
$function$
"
storage,get_prefix,name text,sql,false,i,"CREATE OR REPLACE FUNCTION storage.get_prefix(name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE STRICT
AS $function$
SELECT
    CASE WHEN strpos(""name"", '/') > 0 THEN
             regexp_replace(""name"", '[\/]{1}[^\/]+\/?$', '')
         ELSE
             ''
        END;
$function$
"
storage,get_prefixes,name text,plpgsql,false,i,"CREATE OR REPLACE FUNCTION storage.get_prefixes(name text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE STRICT
AS $function$
DECLARE
    parts text[];
    prefixes text[];
    prefix text;
BEGIN
    -- Split the name into parts by '/'
    parts := string_to_array(""name"", '/');
    prefixes := '{}';

    -- Construct the prefixes, stopping one level below the last part
    FOR i IN 1..array_length(parts, 1) - 1 LOOP
            prefix := array_to_string(parts[1:i], '/');
            prefixes := array_append(prefixes, prefix);
    END LOOP;

    RETURN prefixes;
END;
$function$
"
storage,get_size_by_bucket,,plpgsql,false,s,"CREATE OR REPLACE FUNCTION storage.get_size_by_bucket()
 RETURNS TABLE(size bigint, bucket_id text)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    return query
        select sum((metadata->>'size')::bigint) as size, obj.bucket_id
        from ""storage"".objects as obj
        group by obj.bucket_id;
END
$function$
"
storage,list_multipart_uploads_with_delimiter,"bucket_id text, prefix_param text, delimiter_param text, max_keys integer, next_key_token text, next_upload_token text",plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.list_multipart_uploads_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, next_key_token text DEFAULT ''::text, next_upload_token text DEFAULT ''::text)
 RETURNS TABLE(key text, id text, created_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE ""C"") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE ""C"" > $4
                            ELSE
                                key COLLATE ""C"" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE ""C"" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE ""C"" ASC, created_at ASC) as e order by key COLLATE ""C"" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$function$
"
storage,list_objects_with_delimiter,"bucket_id text, prefix_param text, delimiter_param text, max_keys integer, start_after text, next_token text",plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.list_objects_with_delimiter(bucket_id text, prefix_param text, delimiter_param text, max_keys integer DEFAULT 100, start_after text DEFAULT ''::text, next_token text DEFAULT ''::text)
 RETURNS TABLE(name text, id uuid, metadata jsonb, updated_at timestamp with time zone)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(name COLLATE ""C"") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                        substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1)))
                    ELSE
                        name
                END AS name, id, metadata, updated_at
            FROM
                storage.objects
            WHERE
                bucket_id = $5 AND
                name ILIKE $1 || ''%'' AND
                CASE
                    WHEN $6 != '''' THEN
                    name COLLATE ""C"" > $6
                ELSE true END
                AND CASE
                    WHEN $4 != '''' THEN
                        CASE
                            WHEN position($2 IN substring(name from length($1) + 1)) > 0 THEN
                                substring(name from 1 for length($1) + position($2 IN substring(name from length($1) + 1))) COLLATE ""C"" > $4
                            ELSE
                                name COLLATE ""C"" > $4
                            END
                    ELSE
                        true
                END
            ORDER BY
                name COLLATE ""C"" ASC) as e order by name COLLATE ""C"" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_token, bucket_id, start_after;
END;
$function$
"
storage,objects_insert_prefix_trigger,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.objects_insert_prefix_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM ""storage"".""add_prefixes""(NEW.""bucket_id"", NEW.""name"");
    NEW.level := ""storage"".""get_level""(NEW.""name"");

    RETURN NEW;
END;
$function$
"
storage,objects_update_prefix_trigger,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.objects_update_prefix_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
    old_prefixes TEXT[];
BEGIN
    -- Ensure this is an update operation and the name has changed
    IF TG_OP = 'UPDATE' AND (NEW.""name"" <> OLD.""name"" OR NEW.""bucket_id"" <> OLD.""bucket_id"") THEN
        -- Retrieve old prefixes
        old_prefixes := ""storage"".""get_prefixes""(OLD.""name"");

        -- Remove old prefixes that are only used by this object
        WITH all_prefixes as (
            SELECT unnest(old_prefixes) as prefix
        ),
        can_delete_prefixes as (
             SELECT prefix
             FROM all_prefixes
             WHERE NOT EXISTS (
                 SELECT 1 FROM ""storage"".""objects""
                 WHERE ""bucket_id"" = OLD.""bucket_id""
                   AND ""name"" <> OLD.""name""
                   AND ""name"" LIKE (prefix || '%')
             )
         )
        DELETE FROM ""storage"".""prefixes"" WHERE name IN (SELECT prefix FROM can_delete_prefixes);

        -- Add new prefixes
        PERFORM ""storage"".""add_prefixes""(NEW.""bucket_id"", NEW.""name"");
    END IF;
    -- Set the new level
    NEW.""level"" := ""storage"".""get_level""(NEW.""name"");

    RETURN NEW;
END;
$function$
"
storage,operation,,plpgsql,false,s,"CREATE OR REPLACE FUNCTION storage.operation()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$function$
"
storage,prefixes_insert_trigger,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.prefixes_insert_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    PERFORM ""storage"".""add_prefixes""(NEW.""bucket_id"", NEW.""name"");
    RETURN NEW;
END;
$function$
"
storage,search,"prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text",plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.search(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text)
 RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
 LANGUAGE plpgsql
AS $function$
declare
    can_bypass_rls BOOLEAN;
begin
    SELECT rolbypassrls
    INTO can_bypass_rls
    FROM pg_roles
    WHERE rolname = coalesce(nullif(current_setting('role', true), 'none'), current_user);

    IF can_bypass_rls THEN
        RETURN QUERY SELECT * FROM storage.search_v1_optimised(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    ELSE
        RETURN QUERY SELECT * FROM storage.search_legacy_v1(prefix, bucketname, limits, levels, offsets, search, sortcolumn, sortorder);
    END IF;
end;
$function$
"
storage,search_legacy_v1,"prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text",plpgsql,false,s,"CREATE OR REPLACE FUNCTION storage.search_legacy_v1(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text)
 RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select path_tokens[$1] as folder
           from storage.objects
             where objects.name ilike $2 || $3 || ''%''
               and bucket_id = $4
               and array_length(objects.path_tokens, 1) <> $1
           group by folder
           order by folder ' || v_sort_order || '
     )
     (select folder as ""name"",
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[$1] as ""name"",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where objects.name ilike $2 || $3 || ''%''
       and bucket_id = $4
       and array_length(objects.path_tokens, 1) = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$function$
"
storage,search_v1_optimised,"prefix text, bucketname text, limits integer, levels integer, offsets integer, search text, sortcolumn text, sortorder text",plpgsql,false,s,"CREATE OR REPLACE FUNCTION storage.search_v1_optimised(prefix text, bucketname text, limits integer DEFAULT 100, levels integer DEFAULT 1, offsets integer DEFAULT 0, search text DEFAULT ''::text, sortcolumn text DEFAULT 'name'::text, sortorder text DEFAULT 'asc'::text)
 RETURNS TABLE(name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, last_accessed_at timestamp with time zone, metadata jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
    v_order_by text;
    v_sort_order text;
begin
    case
        when sortcolumn = 'name' then
            v_order_by = 'name';
        when sortcolumn = 'updated_at' then
            v_order_by = 'updated_at';
        when sortcolumn = 'created_at' then
            v_order_by = 'created_at';
        when sortcolumn = 'last_accessed_at' then
            v_order_by = 'last_accessed_at';
        else
            v_order_by = 'name';
        end case;

    case
        when sortorder = 'asc' then
            v_sort_order = 'asc';
        when sortorder = 'desc' then
            v_sort_order = 'desc';
        else
            v_sort_order = 'asc';
        end case;

    v_order_by = v_order_by || ' ' || v_sort_order;

    return query execute
        'with folders as (
           select (string_to_array(name, ''/''))[level] as name
           from storage.prefixes
             where lower(prefixes.name) like lower($2 || $3) || ''%''
               and bucket_id = $4
               and level = $1
           order by name ' || v_sort_order || '
     )
     (select name,
            null as id,
            null as updated_at,
            null as created_at,
            null as last_accessed_at,
            null as metadata from folders)
     union all
     (select path_tokens[level] as ""name"",
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
     from storage.objects
     where lower(objects.name) like lower($2 || $3) || ''%''
       and bucket_id = $4
       and level = $1
     order by ' || v_order_by || ')
     limit $5
     offset $6' using levels, prefix, search, bucketname, limits, offsets;
end;
$function$
"
storage,search_v2,"prefix text, bucket_name text, limits integer, levels integer, start_after text",plpgsql,false,s,"CREATE OR REPLACE FUNCTION storage.search_v2(prefix text, bucket_name text, limits integer DEFAULT 100, levels integer DEFAULT 1, start_after text DEFAULT ''::text)
 RETURNS TABLE(key text, name text, id uuid, updated_at timestamp with time zone, created_at timestamp with time zone, metadata jsonb)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN query EXECUTE
        $sql$
        SELECT * FROM (
            (
                SELECT
                    split_part(name, '/', $4) AS key,
                    name || '/' AS name,
                    NULL::uuid AS id,
                    NULL::timestamptz AS updated_at,
                    NULL::timestamptz AS created_at,
                    NULL::jsonb AS metadata
                FROM storage.prefixes
                WHERE name COLLATE ""C"" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE ""C"" > $5
                ORDER BY prefixes.name COLLATE ""C"" LIMIT $3
            )
            UNION ALL
            (SELECT split_part(name, '/', $4) AS key,
                name,
                id,
                updated_at,
                created_at,
                metadata
            FROM storage.objects
            WHERE name COLLATE ""C"" LIKE $1 || '%'
                AND bucket_id = $2
                AND level = $4
                AND name COLLATE ""C"" > $5
            ORDER BY name COLLATE ""C"" LIMIT $3)
        ) obj
        ORDER BY name COLLATE ""C"" LIMIT $3;
        $sql$
        USING prefix, bucket_name, limits, levels, start_after;
END;
$function$
"
storage,update_updated_at_column,,plpgsql,false,v,"CREATE OR REPLACE FUNCTION storage.update_updated_at_column()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$function$
"
vault,_crypto_aead_det_decrypt,"message bytea, additional bytea, key_id bigint, context bytea, nonce bytea",c,false,i,"CREATE OR REPLACE FUNCTION vault._crypto_aead_det_decrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/supabase_vault', $function$pgsodium_crypto_aead_det_decrypt_by_id$function$
"
vault,_crypto_aead_det_encrypt,"message bytea, additional bytea, key_id bigint, context bytea, nonce bytea",c,false,i,"CREATE OR REPLACE FUNCTION vault._crypto_aead_det_encrypt(message bytea, additional bytea, key_id bigint, context bytea DEFAULT '\x7067736f6469756d'::bytea, nonce bytea DEFAULT NULL::bytea)
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/supabase_vault', $function$pgsodium_crypto_aead_det_encrypt_by_id$function$
"
vault,_crypto_aead_det_noncegen,,c,false,i,"CREATE OR REPLACE FUNCTION vault._crypto_aead_det_noncegen()
 RETURNS bytea
 LANGUAGE c
 IMMUTABLE
AS '$libdir/supabase_vault', $function$pgsodium_crypto_aead_det_noncegen$function$
"
vault,create_secret,"new_secret text, new_name text, new_description text, new_key_id uuid",plpgsql,true,v,"CREATE OR REPLACE FUNCTION vault.create_secret(new_secret text, new_name text DEFAULT NULL::text, new_description text DEFAULT ''::text, new_key_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  rec record;
BEGIN
  INSERT INTO vault.secrets (secret, name, description)
  VALUES (
    new_secret,
    new_name,
    new_description
  )
  RETURNING * INTO rec;
  UPDATE vault.secrets s
  SET secret = encode(vault._crypto_aead_det_encrypt(
    message := convert_to(rec.secret, 'utf8'),
    additional := convert_to(s.id::text, 'utf8'),
    key_id := 0,
    context := 'pgsodium'::bytea,
    nonce := rec.nonce
  ), 'base64')
  WHERE id = rec.id;
  RETURN rec.id;
END
$function$
"
vault,update_secret,"secret_id uuid, new_secret text, new_name text, new_description text, new_key_id uuid",plpgsql,true,v,"CREATE OR REPLACE FUNCTION vault.update_secret(secret_id uuid, new_secret text DEFAULT NULL::text, new_name text DEFAULT NULL::text, new_description text DEFAULT NULL::text, new_key_id uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  decrypted_secret text := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE id = secret_id);
BEGIN
  UPDATE vault.secrets s
  SET
    secret = CASE WHEN new_secret IS NULL THEN s.secret
                  ELSE encode(vault._crypto_aead_det_encrypt(
                    message := convert_to(new_secret, 'utf8'),
                    additional := convert_to(s.id::text, 'utf8'),
                    key_id := 0,
                    context := 'pgsodium'::bytea,
                    nonce := s.nonce
                  ), 'base64') END,
    name = coalesce(new_name, s.name),
    description = coalesce(new_description, s.description),
    updated_at = now()
  WHERE s.id = secret_id;
END
$function$
"