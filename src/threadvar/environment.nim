import
  std/asyncdispatch,
  std/json,
  std/osproc,
  std/random,
  allographer/connection,
  allographer/schema_builder,
  allographer/query_builder,
  ./fw/lib


proc initDb*():Rdb =
  return dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 20, 30, true, false)

type Plugin* = ref object
  rdb*:Rdb

proc new*(_:type Plugin):Plugin =
  return Plugin(
    rdb: initDb()
  )

type Controller* = ref object
  action*: proc(plugin:Plugin):Future[void] {.async, gcsafe.}

randomize()

let rdb = initDb()
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
