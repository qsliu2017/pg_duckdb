CREATE SCHEMA ducklake;

GRANT USAGE ON SCHEMA ducklake TO PUBLIC;

CREATE FUNCTION ducklake._am_handler(internal)
    RETURNS table_am_handler
    SET search_path = pg_catalog, pg_temp
    AS 'MODULE_PATHNAME', 'ducklake_am_handler'
    LANGUAGE C;

CREATE ACCESS METHOD ducklake
    TYPE TABLE
    HANDLER ducklake._am_handler;

CREATE FUNCTION ducklake._create_table_trigger() RETURNS event_trigger
    SET search_path = pg_catalog, pg_temp
    AS 'MODULE_PATHNAME', 'ducklake_create_table_trigger' LANGUAGE C;

CREATE EVENT TRIGGER ducklake_create_table_trigger ON ddl_command_end
    WHEN tag IN ('CREATE TABLE')
    EXECUTE FUNCTION ducklake._create_table_trigger();

CREATE FUNCTION ducklake._drop_trigger() RETURNS event_trigger
    SET search_path = pg_catalog, pg_temp
    AS 'MODULE_PATHNAME', 'ducklake_drop_trigger' LANGUAGE C;

CREATE EVENT TRIGGER ducklake_drop_trigger ON sql_drop
    EXECUTE FUNCTION ducklake._drop_trigger();
