import 
  std/asyncdispatch,
  std/json,
  std/options,
  std/random,
  std/times,
  allographer/connection,
  allographer/schema_builder,
  allographer/query_builder,
  allographer/async/async_db

randomize()

let rdb = dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 96, 30, false, false)

proc init() =
  rdb.create(
    table("num_threads", [
        Column.integer("id"),
        Column.integer("randomnumber")
    ])
  )

  seeder rdb, "num_threads":
    var data = newSeq[JsonNode]()
    for i in 1..10000:
      let randomNum = rand(10000)
      data.add(%*{"id": i, "randomnumber": randomNum})
    rdb.table("num_threads").insert(data).waitFor


proc main(){.async.} =
  init()
  let n = 10000
  let start = cpuTime()
  var resp = newJArray()
  var futures = newSeq[Future[Option[JsonNode]]](n)
  for i in 1..n:
    futures[i-1] = rdb.table("num_table").find(i)
  let resArr = all(futures).await
  for rowOpt in resArr:
    resp.add(rowOpt.get)
  # echo resp
  echo cpuTime() - start


main().waitFor
