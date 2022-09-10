import asyncdispatch, json, options, sequtils
import allographer/query_builder
import ../../../config/database
# framework
import basolato/controller
import basolato/core/base
# view
import ../views/pages/welcome_view


proc index*(context:Context, params:Params):Future[Response] {.async.} =
  let nThreads = 500
  var futures = newSeq[Future[Option[JsonNode]]](nThreads)
  for i in 1..nThreads:
    futures[i-1] = rdb.table("num_table").find(i)
  let res = all(futures).await
  let response = res.map(
    proc(x:Option[JsonNode]):JsonNode =
      x.get()
  )
  return render($(%response))

proc show*(context:Context, params:Params):Future[Response] {.async.} =
  return render("show")


proc indexApi*(context:Context, params:Params):Future[Response] {.async.} =
  return render(%*{"message": "Basolato " & BasolatoVersion})
