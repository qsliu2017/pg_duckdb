#pragma once

#include "pgduckdb/pg/declarations.hpp"

namespace pgduckdb::pg {
extern const char *GetDatabaseName();
extern const char *GetDatabaseName(Oid db_oid);
} // namespace pgduckdb::pg
