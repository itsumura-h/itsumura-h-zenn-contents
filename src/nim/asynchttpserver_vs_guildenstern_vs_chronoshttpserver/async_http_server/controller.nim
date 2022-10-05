import 
  std/asyncdispatch,
  std/options,
  std/json,
  std/strutils,
  std/sequtils,
  allographer/query_builder,
  ./fw/lib_view,
  ./setting,
  ./views/index_view

proc plaintext*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "plaintext"

proc indexPage*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  var resp  = $(indexView("asynchttpserver").await)
  return resp

proc sleep*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  sleepAsync(10000).await
  return "sleep"

proc json*(plugin:Plugin):Future[string] {.async, gcsafe.} =
  return $(%*{"message": "Hello, World!"})

proc queries*(plugin:Plugin):Future[string] {.async, gcsafe.} =
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
