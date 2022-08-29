import 
  std/asyncdispatch,
  std/options,
  std/json,
  allographer/query_builder,
  ./setting

proc index*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  var futures = newSeq[Future[Option[JsonNode]]](10)
  for i in 1..10:
    futures[i-1] = plugin.rdb.table("num_table").find(i)
  let res = all(futures).await
  var resp:seq[JsonNode]
  for row in res:
    resp.add(row.get())
  return $resp

proc show*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "show"
