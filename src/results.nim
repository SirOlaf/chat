
type
  Result*[V, E] = object
    case hasErr: bool
    of false:
      val: V
    of true:
      err: E

proc `$`*[V, E](x: Result[V, E]): string =
  if x.hasErr:
    "Err(" & x.err.repr & ")"
  else:
    "Ok(" & x.val.repr & ")"

proc ok*[V, E](val: V): Result[V, E] {.inline.} =
  when V isnot void:
    Result[V, E](
      hasErr : false,
      val : val,
    )
  else:
    Result[V, E](
      hasErr : false,
    )

proc err*[V, E](err: E): Result[V, E] {.inline.} =
  Result[V, E](
    hasErr : true,
    err : err,
  )


template ifErr*(resExpr: Result, withName: untyped, errBody: untyped): untyped =
  let res = resExpr
  if res.hasErr:
    let withName {.inject.} = res.err
    errBody

template ifErr*(resExpr: Result, withName: untyped, errBody: untyped, okBody: untyped): untyped =
  let res = resExpr
  if res.hasErr:
    let withName {.inject.} = res.err
    errBody
  else:
    okBody

template ifErr*(resExpr: Result, withErrName: untyped, withOkName: untyped, errBody: untyped, okBody: untyped): untyped =
  let res = resExpr
  if res.hasErr:
    let withErrName {.inject.} = res.err
    errBody
  else:
    let withOkName {.inject.} = res.val
    okBody

template ifOk*(resExpr: Result, withName: untyped, okBody: untyped): untyped =
  let res = resExpr
  if not res.hasErr:
    let withName {.inject.} = res.val
    okBody

template ifOk*(resExpr: Result, withName: untyped, okBody: untyped, errBody: untyped): untyped =
  let res = resExpr
  if not res.hasErr:
    let withName {.inject.} = res.val
    okBody
  else:
    errBody

template ifOk*(resExpr: Result, withOkName: untyped, withErrName: untyped, okBody: untyped, errBody: untyped): untyped =
  let res = resExpr
  if not res.hasErr:
    let withOkName {.inject.} = res.val
    okBody
  else:
    let withErrName {.inject.} = res.err
    errBody
