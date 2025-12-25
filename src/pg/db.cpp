#include "pgduckdb/pg/db.hpp"

extern "C" {
#include "postgres.h"
#include "miscadmin.h"
#include "commands/dbcommands.h"
}

namespace pgduckdb::pg {
const char *
GetDatabaseName() {
	return get_database_name(MyDatabaseId);
}
const char *
GetDatabaseName(Oid dbid) {
	return get_database_name(dbid);
}
} // namespace pgduckdb::pg
