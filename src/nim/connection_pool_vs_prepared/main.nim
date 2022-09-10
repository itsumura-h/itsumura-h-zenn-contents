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
  let n = 500
  # プリペアドステートメント
  block:
    let start = cpuTime()
    var resp = newJArray()
    let conn = rdb.conn
    let prepare = conn.prepare(PostgreSQL, "select * from num_table where id = $1 LIMIT 1", "12345").await
    var futures = newSeq[Future[(seq[Row], DbRows)]](n)
    for i in 1..n:
      futures[i-1] = prepare.query(PostgreSQL, @[$i])
    
    let resArr = all(futures).await
    for res in resArr:
      let rows = res[0]
      for row in rows:
        let dbInfo = res[1]
        resp.add(%*{dbInfo[0][0].name: row[0], dbInfo[0][1].name: row[1]})
    # echo resp
    echo cpuTime() - start

  # コネクションプール
  block:
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
