# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

pg_ducklake is a PostgreSQL extension that integrates DuckLake lakehouse format and DuckDB's columnar-vectorized analytics engine into PostgreSQL. It forked from pg_duckdb and adds support for DuckLake metadata management while maintaining all core pg_duckdb functionality.

**Critical Development Constraint**: This project tracks upstream pg_duckdb closely to enable easy merging. **All changes should be scoped to these directories only:**
- `include/pgduckdb/ducklake/` and `src/ducklake/` - DuckLake-specific implementation
- `sql/pg_duckdb--1.1.0--1.2.0.sql` - PostgreSQL-level object registration (functions, types, GUCs)
- `test/regression_ducklake/` - DuckLake-specific tests

**Do not modify files outside these paths** unless absolutely necessary. This makes merging upstream updates straightforward.

**Key Architecture Components:**
- **DuckDB Integration**: Embedded DuckDB database instance per PostgreSQL connection for analytical query processing
- **DuckLake Support**: Lakehouse format with metadata stored in PostgreSQL tables and data files (Parquet) in local filesystem or cloud storage (S3, GCS, Azure, R2)
- **DuckLake Extension**: `third_party/ducklake` submodule provides the core DuckLake functionality
- **Table Access Method**: `USING ducklake` for lakehouse format with columnar storage
- **Query Acceleration**: Automatically accelerates analytical queries on PostgreSQL tables using DuckDB's vectorized execution

## Build System

### Prerequisites
- PostgreSQL 14-18
- CMake, Ninja, pkg-config
- DuckDB dependencies (liblz4-dev, libcurl4-openssl-dev)
- Python 3.8+ for testing

### Build Commands

```bash
# Initialize submodules (required on first clone)
git submodule update --init --recursive

# Standard release build (dynamic linking)
make -j$(nproc)
sudo make install

# Static linking (for production)
DUCKDB_BUILD=ReleaseStatic make -j$(nproc)
sudo make install

# Debug build
DUCKDB_BUILD=Debug make -j$(nproc)
sudo make install

# Build for specific PostgreSQL version
PG_CONFIG=/path/to/pg_config make install
```

### Clean Commands
```bash
make clean              # Clean pg_ducklake build files
make clean-all          # Clean both pg_ducklake and DuckDB library
make clean-duckdb       # Clean only DuckDB library
make clean-regression   # Clean test artifacts
```

### Testing
```bash
# Run all tests
make check

# Run only regression tests
make installcheck

# Run only Python tests
make pycheck

# Run specific test
make installcheck TEST=basic

# Run tests with specific concurrency
PYTEST_CONCURRENCY=4 make pycheck
```

### Code Quality
```bash
# Format code (follows project style)
make format

# Check linting
make lintcheck
```

## Architecture

### Core Components

1. **DuckDBManager** (`src/pgduckdb_duckdb.cpp`, `include/pgduckdb/pgduckdb_duckdb.hpp`)
   - Singleton pattern managing embedded DuckDB instance per connection
   - Handles connection lifecycle, secrets management, and extension loading
   - Located in `pgduckdb::DuckDBManager`

2. **Hooks System** (`src/pgduckdb_hooks.cpp`)
   - PostgreSQL hooks interception (planner, executor, explain)
   - Routes queries to DuckDB execution when appropriate
   - Critical for query acceleration

3. **DuckLake Metadata Manager** (`src/ducklake/pgducklake_metadata_manager.cpp`)
   - Bridges PostgreSQL metadata tables with DuckDB's DuckLake extension
   - Manages Parquet file storage and metadata synchronization
   - Implements `duckdb::DuckLakeMetadataManager` interface

4. **Table Access Method** (`src/ducklake/pgducklake_table_am.cpp`)
   - Custom PostgreSQL table access method for DuckLake
   - Enables `CREATE TABLE ... USING ducklake` syntax

5. **Type Conversion** (`src/pgduckdb_types.cpp`)
   - Bidirectional type conversion between PostgreSQL and DuckDB
   - Handles complex nested types, arrays, and numerics

6. **Transaction Management** (`src/pgduckdb_xact.cpp`)
   - Coordinates PostgreSQL and DuckDB transactions
   - Prevents mixed writes (PostgreSQL + DuckDB in same transaction)
   - Manages command IDs for metadata consistency

### Directory Structure

```
src/
├── pgduckdb.cpp           # Extension initialization (_PG_init) [UPSTREAM]
├── pgduckdb_hooks.cpp     # Query planner/executor hooks [UPSTREAM]
├── pgduckdb_duckdb.cpp    # DuckDB instance management [UPSTREAM]
├── pgduckdb_ddl.cpp       # DDL statement handling [UPSTREAM]
├── pgduckdb_types.cpp     # Type conversion logic [UPSTREAM]
├── pgduckdb_xact.cpp      # Transaction coordination [UPSTREAM]
├── pgduckdb_guc.cpp       # GUC configuration variables [UPSTREAM]
├── pgduckdb_planner.cpp   # Query planning for DuckDB [UPSTREAM]
├── ducklake/              # 🟢 DuckLake-specific code [SAFE TO MODIFY]
│   ├── pgducklake_metadata_manager.cpp
│   ├── pgducklake_ddl.cpp
│   └── pgducklake_table_am.cpp
├── scan/                  # PostgreSQL scanning logic for DuckDB [UPSTREAM]
├── utility/               # Utility functions (COPY, signal handling) [UPSTREAM]
├── catalog/               # Catalog management [UPSTREAM]
└── pg/                    # PostgreSQL utility wrappers [UPSTREAM]

include/pgduckdb/
├── pgduckdb.h             # Main C header [UPSTREAM]
├── pgduckdb_*.hpp         # C++ headers for each component [UPSTREAM]
└── ducklake/              # 🟢 DuckLake-specific headers [SAFE TO MODIFY]

sql/
├── pg_duckdb--1.1.0--1.2.0.sql  # 🟢 Version upgrade script [SAFE TO MODIFY]
└── pg_duckdb--*.sql       # Other upgrade scripts [UPSTREAM]

test/
├── regression/            # PostgreSQL regression tests (pg_duckdb) [UPSTREAM]
├── regression_ducklake/   # 🟢 DuckLake-specific regression tests [SAFE TO MODIFY]
└── pycheck/               # Python-based integration tests [UPSTREAM]

third_party/
├── duckdb/                # Git submodule: DuckDB [EXTERNAL]
└── ducklake/              # 🟢 Git submodule: DuckLake extension [OUR ADDITION]
```

**Legend:**
- 🟢 **SAFE TO MODIFY** - DuckLake-specific changes, tracked separately from upstream
- **UPSTREAM** - From pg_duckdb, avoid modifications to enable easy merging
- **EXTERNAL** - Git submodules shared with upstream (DuckDB)
- **OUR ADDITION** - New submodules added for DuckLake support

### Current Upstream Modifications

The following upstream files have minimal modifications to support DuckLake:

1. **src/pgduckdb_duckdb.cpp** - Added DuckLake metadata manager includes
2. **src/pgduckdb_xact.cpp** - Added `ducklake_command_id_increment` tracking to allow DuckLake metadata writes to coexist with DuckDB writes
3. **src/pgduckdb_hooks.cpp** - Removed view-checking optimization (simplifies query routing)
4. **src/utility/signal_guard.cpp** - Simplified error handling in signal guard
5. **include/pgduckdb/pgduckdb_guc.hpp** & **src/pgduckdb_guc.cpp** - Added `ducklake.default_table_path` GUC variable

These changes are documented and minimal to enable straightforward merging. When merging upstream updates, preserve these DuckLake-specific modifications.

## Key Patterns and Conventions

### Error Handling
- **Before DuckDB execution**: Use `elog(ERROR, ...)` - never throw exceptions
- **Inside DuckDB execution**: Use exceptions - never use `elog(ERROR, ...)`
- Boundary is critical: exceptions in PostgreSQL code can cause crashes
- Use `PostgresFunctionGuard` when calling PostgreSQL functions from DuckDB context

### Memory Management
- **PostgreSQL code**: Use memory contexts (`palloc`, `palloc0`)
- **C++ code**: Use smart pointers (`duckdb::unique_ptr`), avoid `malloc`/`new`
- Prefer `unique_ptr` over `shared_ptr` unless absolutely necessary

### Coding Style
- **C files**: Tabs for indentation, spaces for alignment, 120 column limit
- **C++ files**: Follow DuckDB guidelines (see CONTRIBUTING.md)
- Use `const` whenever possible
- No namespace imports (e.g., `using std`)
- All functions in `src/` must be in `pgduckdb` namespace
- Use C++11 range-based for loops: `for (const auto& item : items)`

### PostgreSQL Integration
- Extension must be loaded via `shared_preload_libraries`
- Requires PostgreSQL restart to add/remove from preload libraries
- Uses GUC variables for configuration (prefix: `duckdb.*`)
- Background worker for MotherDucK cache invalidation

### Transaction Rules
- Cannot write to both PostgreSQL and DuckDB tables in same transaction
- Cannot mix DDL for PostgreSQL and DuckDB in same transaction
- DuckLake metadata table writes are exception to the above (coexist with DuckDB writes)
- Use `duckdb.unsafe_allow_mixed_transactions` to bypass (not recommended)

## Configuration (GUC Variables)

Key settings in `postgresql.conf`:

```conf
# Required
shared_preload_libraries = 'pg_duckdb'

# Query execution
duckdb.force_execution = off           # Force DuckDB for Postgres tables
duckdb.unsafe_allow_mixed_transactions = off

# Resources (per connection)
duckdb.max_memory = 4096               # MB
duckdb.threads = -1                    # -1 = CPU cores

# DuckLake
duckdb.default_table_path = '/path'    # Default DuckLake data location

# Security
duckdb.postgres_role = ''              # Role allowed to use DuckDB
duckdb.disabled_filesystems = ''       # Disable filesystems
```

## Upstream Merge Strategy

This repository is designed to track upstream pg_duckdb closely. When working on DuckLake features:

1. **Keep changes isolated**: All DuckLake code should live in the designated directories
2. **Minimize upstream modifications**: If you must touch upstream files:
   - Document the change thoroughly with comments like `// MODIFIED for DuckLake: reason`
   - Keep changes as minimal as possible
   - Consider if functionality can be achieved through extension hooks instead
3. **SQL upgrades**: Use `sql/pg_duckdb--1.1.0--1.2.0.sql` for registering new PostgreSQL objects
4. **Testing**: Put DuckLake tests in `test/regression_ducklake/` to keep them separate

When merging upstream updates:
```bash
git remote add upstream https://github.com/duckdb/pg_duckdb.git
git fetch upstream
git merge upstream/main
# Resolve conflicts focusing on keeping ducklake-specific changes
```

To check current diff from upstream:
```bash
git diff --stat duckdb/main HEAD  # What we have that upstream doesn't
git diff --stat HEAD duckdb/main  # What upstream has that we don't
```

## Testing Strategy

### Test Types
1. **Regression Tests** (`test/regression/`, `test/regression_ducklake/`)
   - PostgreSQL standard regression test framework
   - SQL-based tests in `sql/*.sql`, expected output in `expected/*.out`
   - Run with `make installcheck`

2. **Python Tests** (`test/pycheck/`)
   - pytest-based integration tests
   - Manages PostgreSQL lifecycle programmatically
   - Better for complex scenarios and setup/teardown
   - Run with `make pycheck`

### Test Organization
- `test/regression/sql/basic.sql` - Core functionality
- `test/regression_ducklake/sql/basic.sql` - DuckLake-specific
- Use `TEST` environment variable to run specific test
- Tests automatically set `AWS_REGION=us-east-1` for consistency

## Development Workflow

1. **Make changes** to source files
   - **Keep changes in ducklake-specific directories** (see constraint above)
   - If you must modify upstream files, document why and minimize the scope
2. **Run `make -j$(nproc)`** to build
3. **Run `make format`** before committing
4. **Run `make check`** (or subset) to verify
5. **Create regression test** in `test/regression_ducklake/` for new features/bugs
6. **Update `sql/pg_duckdb--1.1.0--1.2.0.sql`** if adding PostgreSQL functions/types/GUCs
7. **Update docs** if user-facing behavior changes

## Common Gotchas

1. **Upstream modifications**: Avoid changing files outside ducklake-specific directories to enable easy merging from pg_duckdb
2. **Submodule updates**: After `git pull`, run `git submodule update --init --recursive`
3. **Clean builds**: If DuckDB version changes, run `make clean-all`
4. **PostgreSQL restart**: Required after `make install` if extension already loaded
5. **Transaction isolation**: DuckDB doesn't see PostgreSQL uncommitted changes
6. **Type limitations**: Not all PostgreSQL types supported (see docs/types.md)
7. **Local filesystem**: DuckDB may not access local DuckLake data (use cloud storage)
8. **Debug builds**: Slower but more assertions, useful for development
9. **Static builds**: Use `DUCKDB_BUILD=ReleaseStatic` for production deployment

## Key Files to Understand

1. `src/pgduckdb.cpp` - Extension entry point, initialization order
2. `src/pgduckdb_hooks.cpp` - Query routing logic
3. `src/ducklake/pgducklake_metadata_manager.cpp` - DuckLake integration
4. `include/pgduckdb/pgduckdb_duckdb.hpp` - DuckDB instance management
5. `src/pgduckdb_xact.cpp` - Transaction coordination
6. `src/pgduckdb_types.cpp` - Type conversion logic

## DuckLake Tables

- **USING ducklake**: Stores data as Parquet files in configured location (local filesystem or cloud storage)
- DuckLake requires `ducklake.create_metadata()` call first
- DuckLake metadata stored in PostgreSQL `ducklake.*` tables
- Supports DuckDB query acceleration features for analytical queries
