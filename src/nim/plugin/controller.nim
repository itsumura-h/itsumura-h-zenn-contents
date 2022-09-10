import
  std/asyncdispatch,
  std/json,
  std/options,
  std/strformat,
  allographer/query_builder,
  ./environment

proc controller1*(param: (Plugin, int)):Future[void] {.async, gcsafe.} =
  let (plugin, nThread) = param
  for i in 1..10:
    let res = plugin.rdb.table("hello").find(i).await.get
    echo &"スレッド{nThread} {i}回目 {res}"


proc controller2*(param: (Plugin, int)):Future[void] {.async, gcsafe.} =
  let (plugin, nThread) = param
  let countNum = 500
  var futures = newSeq[Future[void]](countNum)
  for i in 1..countNum:
    futures[i-1] = (proc():Future[void] {.async.} =
      let res = plugin.rdb.table("hello").find(i).await.get
      echo &"スレッド{nThread} {i}回目 {res}"
    )()
  all(futures).await
