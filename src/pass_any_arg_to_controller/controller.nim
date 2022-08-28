import 
  std/asyncdispatch,
  std/options,
  std/json,
  allographer/query_builder,
  ./setting

proc index*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  for i in 1..10:
    echo plugin.rdb.table("num_table").find(i).await.get()
  return "index"

proc show*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "show"
