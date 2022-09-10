import 
  std/asyncdispatch,
  std/db_postgres,
  std/options,
  std/json,
  allographer/query_builder,
  ./setting

proc index*():Future[string] {.async, gcsafe.} =
  for i in 1..10:
    echo i
  return "index"

proc show*():Future[string] {.async, gcsafe.} =
  return "show"
