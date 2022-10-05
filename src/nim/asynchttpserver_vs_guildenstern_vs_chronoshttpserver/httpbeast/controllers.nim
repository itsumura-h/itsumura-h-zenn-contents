import
  std/asyncdispatch,
  std/options,
  std/json,
  std/sequtils,
  allographer/connection,
  allographer/query_builder,
  ./lib/httpbeast,
  ./setting


proc plaintext*(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.} =
  return "plaintext"

proc sleep*(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.} =
  sleepAsync(10000).await
  return "sleep"

proc json*(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.} =
  return $(%*{"message": "Hello, World!"})

proc queries*(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.} =
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
