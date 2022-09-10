import 
  std/asyncdispatch,
  std/json,
  std/options,
  allographer/connection,
  allographer/schema_builder,
  allographer/query_builder

let rdb = dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 96, 30, false, false)

proc init() {.async.}=
  let rawSql = readFile("./query.sql")
  rdb.raw(rawSql).exec().await

proc main(){.async.} =
  # init().await
  let res = newJObject()
  let nums = rdb.table("payment_informations").count().await
  let amari = nums mod 100
  let loopCount = if amari > 0: (nums div 100)+1 else: nums div 100
  for i in 1..loopCount:
    let n = if i == 1: 1 else: ((i-1) * 100)+1
    let rows = rdb.table("payment_informations").offset(n).limit(100).get().await
    
    for row in rows:
      if not res.hasKey($row["account_number"].getStr()):
        res[$row["account_number"].getStr()] = %[row]
      else:
        res[$row["account_number"].getStr()].add(row)

  writeFile("./result.json", res.pretty())
  for key, row in res:
    if row.len() > 1 and key.len > 0 and key != "1108585":
      echo "=============================="
      echo "account_number… ", key
      for order in row:
        echo ""
        echo "order_id… ", order["orders_id"].getInt
        echo "updated_at… ", order["updated_at"].getStr


main().waitFor
