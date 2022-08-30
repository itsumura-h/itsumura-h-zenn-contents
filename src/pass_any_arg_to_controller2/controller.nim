import 
  std/asyncdispatch,
  std/db_postgres,
  std/options,
  std/strutils,
  std/json,
  ./setting

proc index*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  let nThreads = 500
  let res = newJArray()
  for i in 1..nThreads:
    let data = plugin.rdb.getRow(sql"SELECT * FROM num_table WHERE id = ?", i)
    res.add(%*{"id": data[0].parseInt, "randomnumber": data[1].parseInt})
  return $res

proc show*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "show"
