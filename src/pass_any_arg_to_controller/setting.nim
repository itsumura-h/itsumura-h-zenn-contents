import
  std/asyncdispatch,
  allographer/connection,
  allographer/query_builder


proc initDb*():Rdb =
  return dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 20, 30, true, false)

# ============================================================
type Plugin* = ref object
  rdb*:Rdb

proc new*(_:type Plugin):Plugin =
  return Plugin(
    rdb: initDb()
  )

# ============================================================
type Controller* = ref object
  action*: proc(plugin:Plugin):Future[string] {.async, gcsafe.}

proc new*(_:type Controller, action: proc(plugin:Plugin):Future[string] {.async, gcsafe.}):Controller =
  return Controller(action:action)
