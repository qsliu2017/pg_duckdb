-- Test ducklake.default_table_path GUC
-- This GUC allows specifying a default absolute path for DuckLake tables

-- First, verify the GUC exists and check its default value
SELECT name, setting, context
FROM pg_settings
WHERE name = 'ducklake.default_table_path';

-- Create DuckLake metadata with default path
SELECT ducklake.create_metadata();

-- Create a table without setting the GUC explicitly (uses default: DataDir/pg_ducklake/)
CREATE TABLE t1 (a int, b int) USING ducklake;
INSERT INTO t1 VALUES (1, 101), (2, 202);

-- Check the table path - should be relative to default path
SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 't1';

-- Check data file exists and is relative
SELECT COUNT(*) as data_file_count,
       BOOL_AND(path_is_relative) as all_files_relative
FROM ducklake.ducklake_data_file
WHERE table_id = (SELECT table_id FROM ducklake.ducklake_table WHERE table_name = 't1');

-- Verify the path is relative when using default catalog path
SELECT path_is_relative = true as is_relative_default
FROM ducklake.ducklake_table
WHERE table_name = 't1';

DROP TABLE t1;

-- Now set a custom default_table_path to an absolute path
SET ducklake.default_table_path = '/tmp/ducklake_custom_tables/';

-- Create another table with the custom GUC set
CREATE TABLE t2 (a int, b int) USING ducklake;
INSERT INTO t2 VALUES (3, 303), (4, 404);

-- Check the table path - should be absolute and start with the GUC path
SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 't2';

-- Check data file exists and is relative (table path provides the full location)
SELECT COUNT(*) as data_file_count,
       BOOL_AND(path_is_relative) as all_files_relative
FROM ducklake.ducklake_data_file
WHERE table_id = (SELECT table_id FROM ducklake.ducklake_table WHERE table_name = 't2');

-- Verify the path is absolute and uses the GUC path
SELECT
    path_is_relative = false as is_absolute,
    starts_with(path, '/tmp/ducklake_custom_tables/') as uses_guc_path
FROM ducklake.ducklake_table
WHERE table_name = 't2';

-- Verify data can be queried
SELECT * FROM t2 ORDER BY a;

DROP TABLE t2;

-- Test with a different custom path (no trailing slash)
SET ducklake.default_table_path = '/tmp/ducklake_alt';

CREATE TABLE t3 (id int, name text) USING ducklake;
INSERT INTO t3 VALUES (1, 'alice'), (2, 'bob');

-- Verify path uses the custom path
SELECT
    path_is_relative = false as is_absolute,
    starts_with(path, '/tmp/ducklake_alt') as uses_guc_path
FROM ducklake.ducklake_table
WHERE table_name = 't3';

SELECT * FROM t3 ORDER BY id;
DROP TABLE t3;

-- Test changing GUC mid-session - each table should use the GUC value at creation time
SET ducklake.default_table_path = '/tmp/batch1/';
CREATE TABLE batch1_table (x int) USING ducklake;
INSERT INTO batch1_table VALUES (100);

SET ducklake.default_table_path = '/tmp/batch2/';
CREATE TABLE batch2_table (x int) USING ducklake;
INSERT INTO batch2_table VALUES (200);

-- Verify each table has its own path
SELECT
    table_name,
    path,
    path_is_relative,
    starts_with(path, '/tmp/batch1/') as is_batch1,
    starts_with(path, '/tmp/batch2/') as is_batch2
FROM ducklake.ducklake_table
WHERE table_name IN ('batch1_table', 'batch2_table')
ORDER BY table_name;

-- Verify data files exist and are relative for each table
SELECT
    t.table_name,
    COUNT(*) as data_file_count,
    BOOL_AND(f.path_is_relative) as all_files_relative
FROM ducklake.ducklake_data_file f
JOIN ducklake.ducklake_table t ON f.table_id = t.table_id
WHERE t.table_name IN ('batch1_table', 'batch2_table')
GROUP BY t.table_name
ORDER BY t.table_name;

DROP TABLE batch1_table;
DROP TABLE batch2_table;

-- Enable mixed transactions for testing
SET duckdb.unsafe_allow_mixed_transactions = true;

-- Transaction corner cases
-- Test 1: SET GUC -> BEGIN -> CREATE TABLE -> INSERT -> COMMIT
-- The GUC is set before transaction, table should use the GUC path
SET ducklake.default_table_path = '/tmp/txn1_path/';
BEGIN;
CREATE TABLE txn1_table (x int) USING ducklake;
-- Note: Not inserting data here because /tmp/txn1_path/ may not exist
COMMIT;

SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 'txn1_table';

DROP TABLE txn1_table;

-- Test 2: GUC empty -> BEGIN -> CREATE TABLE -> COMMIT -> SET GUC -> SELECT
-- The table is created with empty GUC, so it should use relative path
SET ducklake.default_table_path = '';
BEGIN;
CREATE TABLE txn2_table (x int) USING ducklake;
INSERT INTO txn2_table VALUES (100);
COMMIT;

-- Now check path is relative
SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 'txn2_table';

-- Now set GUC and create another table
SET ducklake.default_table_path = '/tmp/txn2_path/';
BEGIN;
CREATE TABLE txn2_after_table (x int) USING ducklake;
-- Note: Not inserting data here because /tmp/txn2_path/ may not exist
COMMIT;

-- Check second table uses the new GUC path
SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 'txn2_after_table';

-- Verify data can be read from the table with data
SELECT * FROM txn2_table;

DROP TABLE txn2_table;
DROP TABLE txn2_after_table;

-- Test 3: Change GUC during transaction
-- Table path is determined at transaction commit time
SET ducklake.default_table_path = '';
BEGIN;
CREATE TABLE txn3_table (x int) USING ducklake;
-- Note: Not inserting data here
-- Change GUC before commit - this WILL affect the table path
SET ducklake.default_table_path = '/tmp/txn3_path/';
COMMIT;

-- Verify table uses the GUC value at COMMIT time (not CREATE time)
SELECT table_name, path, path_is_relative
FROM ducklake.ducklake_table
WHERE table_name = 'txn3_table';

DROP TABLE txn3_table;

-- Clean up
SELECT ducklake.drop_metadata(true);
