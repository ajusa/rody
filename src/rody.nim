import std/[strutils, xmltree, cookies, strtabs, times, options], mummy, webby
export mummy, webby

type Halt = ref object of ValueError

var request* {.threadvar.}: Request
var headers* {.threadvar.}: HttpHeaders
var status* {.threadvar.}: int
var body* {.threadvar.}: string

var path* {.threadvar.}: string
var undo {.threadvar.}: seq[string]

proc halt*() = raise Halt()

proc push*(pattern: string): bool =
  if path.startsWith(pattern):
    path.removePrefix(pattern)
    undo.add(pattern)
    return true

proc pop*() =
  path = undo.pop() & path

template at*(pattern: string, body: untyped) =
  if push(pattern):
    body
    pop()

proc isInt(s: string): bool =
  try:
    discard s.parseInt()
    true
  except Defect: false

template at*(t: typedesc[int], body: untyped) =
  var numStr = ""
  var i = 1
  while i < path.len and path[i].isDigit():
    numStr.add(path[i])
    inc i
  if numStr.isInt and push("/" & numStr):
    var it {.inject.} = numStr.parseInt()
    body
    pop()

template at*(t: typedesc[string], body: untyped) =
  var str = ""
  var i = 1
  while i < path.len and path[i] != '/':
    str.add(path[i])
    inc i
  if str.len > 0 and push("/" & str):
    var it {.inject.} = str
    body
    pop()

template match(meth: string, body: untyped) =
  if request.httpMethod == meth and path == "":
    body
    halt()

template get*(body: untyped) = match("GET"): body
template post*(body: untyped) = match("POST", body)
template delete*(body: untyped) = match("DELETE", body)
template put*(body: untyped) = match("PUT", body)

template route*(body: untyped): untyped =
  proc(request: Request) {.gcsafe.} =
    try:
      rody.request = request
      path = request.path
      body
      status = 404
      request.respond(status, headers, rody.body)
    except Halt:
      request.respond(status, headers, rody.body)

proc resp*(body: string) =
  status = 200
  rody.body = body

proc redirect*(path: string) =
  status = 302
  headers["Location"] = path

proc cookies*(request: Request, key: string, default = ""): string =
  request.headers["Cookie"].parseCookies.getOrDefault(key, default)

proc setCookie*(key, value: string, path = "", maxAge = initDuration(days = 30)) =
  headers.add(("Set-Cookie", setCookie(key, value, path = "/" & path, noName = true,
    secure = true, httpOnly = true, sameSite = Strict, maxAge = some(maxAge.inSeconds.int))))

proc params*(): seq[(string, string)] =
  if request.body.len > 0: result &= request.body.parseSearch.toBase
  result &= request.queryParams.toBase

template `@`*(key: string): string = params()[key]

proc safe*[T](s: T): string = xmltree.escape($s)
