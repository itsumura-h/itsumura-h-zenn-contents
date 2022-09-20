import 
  std/asyncdispatch,
  std/options,
  std/json,
  std/strutils,
  std/sequtils,
  allographer/query_builder,
  ./setting

proc index*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  let nThreads = 500
  var futures = newSeq[Future[Option[JsonNode]]](nThreads)
  for i in 1..nThreads:
    futures[i-1] = plugin.rdb.table("num_table").find(i)
  let res = all(futures).await
  let response = res.map(
    proc(x:Option[JsonNode]):JsonNode =
      x.get()
  )
  return $(%response)

proc show*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "show"
