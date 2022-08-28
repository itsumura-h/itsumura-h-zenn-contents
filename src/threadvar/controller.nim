import
  std/asyncdispatch,
  std/json,
  std/locks,
  std/options,
  std/strformat,
  allographer/query_builder,
  ./fw/lib,
  ./environment

proc controller1*(plugin:Plugin, nThread:int):Future[void] {.async, gcsafe.} =
  for i in 1..10:
    echo "=== 2"
    echo rdb.isNil
    let res = rdb.table("num_table").find(i).await.get
    echo &"スレッド{nThread} {i}回目 {res}"


proc controller2*(plugin:Plugin, nThread:int):Future[void] {.async, gcsafe.} =
  let countNum = 500
  var futures = newSeq[Future[void]](countNum)
  for i in 1..countNum:
    futures[i-1] = (proc():Future[void] {.async.} =
      let res = rdb.table("num_table").find(i).await.get
      echo &"スレッド{nThread} {i}回目 {res}"
    )()
  all(futures).await
