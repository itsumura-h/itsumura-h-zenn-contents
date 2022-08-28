import 
  std/asyncdispatch,
  std/db_postgres,
  std/options,
  std/json,
  allographer/query_builder,
  ./setting

proc index*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  for i in 1..10:
    echo plugin.rdb.getRow(sql"SELECT * FROM num_table WHERE id = ?", i)
  return "index"

proc show*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "show"
