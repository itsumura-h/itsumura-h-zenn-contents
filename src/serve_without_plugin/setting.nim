import
  std/asyncdispatch,
  std/db_postgres


proc initDb*():DbConn =
  open("db", "user", "pass", "database")


# ============================================================
type Plugin* = ref object

proc new*(_:type Plugin):Plugin =
  return Plugin()

# ============================================================
type Controller* = ref object
  action*: proc():Future[string] {.async, gcsafe.}

proc new*(_:type Controller, action: proc():Future[string] {.async, gcsafe.}):Controller =
  return Controller(action:action)
