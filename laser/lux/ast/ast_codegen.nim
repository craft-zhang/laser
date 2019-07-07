# Laser
# Copyright (c) 2018 Mamy André-Ratsimbazafy
# Distributed under the Apache v2 License (license terms are at http://www.apache.org/licenses/LICENSE-2.0).
# This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  macros, tables,
  # Internal
  ./ast_definition,
  ../platforms

proc codegen*(
    ast: LuxNode,
    arch: SimdArch,
    T: NimNode,
    params: seq[NimNode],
    visited: var Table[Id, NimNode],
    stmts: var NimNode): NimNode =
  ## Recursively walk the AST
  ## Append the corresponding Nim AST for generic instructions
  ## and returns a LValTensor, MutTensor or expression
  case ast.kind:
    of InTensor:
      return params[ast.symId]
    of IntImm:
      return newCall(SimdMap(arch, T, simdBroadcast), newLit(ast.intVal))
    of FloatImm:
      return newCall(SimdMap(arch, T, simdBroadcast), newLit(ast.floatVal))
    of MutTensor, LValTensor:
      let sym = newIdentNode(ast.symLVal)
      if ast.id in visited:
        return sym
      elif ast.prev_version.isNil:
        visited[ast.id] = sym
        return sym
      else:
        visited[ast.id] = sym
        var blck = newStmtList()
        let expression = codegen(ast.prev_version, arch, T, params, visited, blck)
        stmts.add blck
        if not(expression.kind == nnkIdent and eqIdent(sym, expression)):
          stmts.add newAssignment(
            newIdentNode(ast.symLVal),
            expression
          )
        return newIdentNode(ast.symLVal)
    of Assign:
      if ast.id in visited:
        return visited[ast.id]

      var varAssign = false

      if ast.lhs.id notin visited and
            ast.lhs.kind == LValTensor and
            ast.lhs.prev_version.isNil and
            ast.rhs.id notin visited:
          varAssign = true

      var rhsStmt = newStmtList()
      let rhs = codegen(ast.rhs, arch, T, params, visited, rhsStmt)
      stmts.add rhsStmt

      var lhsStmt = newStmtList()
      let lhs = codegen(ast.lhs, arch, T, params, visited, lhsStmt)
      stmts.add lhsStmt

      lhs.expectKind(nnkIdent)
      if varAssign:
        stmts.add newVarStmt(lhs, rhs)
      else:
        stmts.add newAssignment(lhs, rhs)
      # visited[ast] = lhs # Already done
      return lhs

    of Add, Mul:
      if ast.id in visited:
        return visited[ast.id]

      var callStmt = nnkCall.newTree()
      var lhsStmt = newStmtList()
      var rhsStmt = newStmtList()

      let lhs = codegen(ast.lhs, arch, T, params, visited, lhsStmt)
      let rhs = codegen(ast.rhs, arch, T, params, visited, rhsStmt)

      stmts.add lhsStmt
      stmts.add rhsStmt

      case ast.kind
      of Add: callStmt.add SimdMap(arch, T, simdAdd)
      of Mul: callStmt.add SimdMap(arch, T, simdMul)
      else: raise newException(ValueError, "Unreachable code")

      callStmt.add lhs
      callStmt.add rhs

      let memloc = genSym(nskLet, "memloc_")
      stmts.add newLetStmt(memloc, callStmt)
      visited[ast.id] = memloc
      return memloc

proc bodyGen*(
      arch: SimdArch,
      io_ast: varargs[LuxNode],
      ids: seq[NimNode],
      ids_baseType: seq[NimNode],
      resultType: NimNode,
    ): NimNode =
  # Does topological ordering and dead-code elimination
  result = newStmtList()
  var visitedNodes = initTable[Id, NimNode]()

  for i, inOutVar in io_ast:
    if inOutVar.kind != InTensor:
      if inOutVar.kind in {MutTensor, LValTensor}:
        let sym = codegen(inOutVar, arch, ids_baseType[i], ids, visitedNodes, result)
        sym.expectKind nnkIdent
        if resultType.kind == nnkTupleTy:
          result.add newAssignment(
            nnkDotExpr.newTree(
              newIdentNode"result",
              ids[i]
            ),
            sym
          )
        else:
          result.add newAssignment(
            newIdentNode"result",
            sym
          )
      else:
        let expression = codegen(inOutVar, arch, ids_baseType[i], ids, visitedNodes, result)
        if resultType.kind == nnkTupleTy:
          result.add newAssignment(
            nnkDotExpr.newTree(
              newIdentNode"result",
              ids[i]
            ),
            expression
          )
        else:
          result.add newAssignment(
            newIdentNode"result",
            expression
          )
  # TODO: support var Tensor.
