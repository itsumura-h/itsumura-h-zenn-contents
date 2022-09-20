import
  std/asyncdispatch,
  allographer/connection,
  allographer/query_builder,
  ./lib/httpbeast


# ============================================================
proc initDb*():Rdb =
  when compileOption("threads"):
    return dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 23, 30, false, false)
  else:
    return dbOpen(PostgreSQL, "database", "user", "pass", "db", 5432, 96, 30, false, false)

# ============================================================
type Plugin* = ref object
  rdb*:Rdb

proc new*(_:type Plugin):Plugin =
  return Plugin(
    rdb: initDb()
  )

# ============================================================
type Controller* = ref object
  action*: proc(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.}

proc new*(_:type Controller, action: proc(req: Request, plugin:Plugin):Future[string] {.async, gcsafe.}):Controller =
  return Controller(action:action)

type Route* = ref object
  path*:string
  httpMethod*:HttpMethod

type Routes* = seq[(Route, Controller)]
