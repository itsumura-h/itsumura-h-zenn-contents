import
  std/asyncdispatch,
  std/random,
  std/json,
  allographer/connection,
  allographer/schema_builder,
  allographer/query_builder

proc initDb*():Rdb =
  return dbOpen(PostgreSQL, "database", "benchmarkdbuser", "benchmarkdbpass", "tfb-database-pg", 5432, 20, 30, false, false)
  # return dbOpen(PostgreSQL, "db_name", "user", "pass", "db_host", 5432, 20, 30, true, false)

type Plugin* = ref object
  rdb*: Rdb

randomize()

var rdb = initDb()
rdb.create(
  table("num_table", [
    Column.integer("id"),
    Column.integer("randomnumber")
  ])
)

seeder rdb, "num_table":
  var data = newSeq[JsonNode]()
  for i in 1..10000:
    let randomNum = rand(10000)
    data.add(%*{"id": i, "randomnumber": randomNum})
  rdb.table("num_table").insert(data).waitFor
