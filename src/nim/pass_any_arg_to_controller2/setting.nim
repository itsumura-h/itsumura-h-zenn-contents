import
  std/asyncdispatch,
  std/db_postgres


proc initDb*():DbConn =
  open("db", "user", "pass", "database")


# ============================================================
type Plugin* = ref object
  rdb*:DbConn

proc new*(_:type Plugin):Plugin =
  return Plugin(
    rdb: initDb()
  )

# ============================================================
type Controller* = ref object
  action*: proc(plugin:Plugin):Future[string] {.async, gcsafe.}

proc new*(_:type Controller, action: proc(plugin:Plugin):Future[string] {.async, gcsafe.}):Controller =
  return Controller(action:action)
