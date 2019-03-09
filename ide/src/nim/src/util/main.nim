# Hello Nim!
import jester, typetraits, sequtils, tables, db_sqlite, types, parseutils, strutils, json
import jsonify
import init
import process
import branchingCondition
# include process

var db: DbConn
var decTable: CountTable[int]

proc init*(dirPath: string): Core =
    db = findFiles(dirPath)
    decTable = getDecendants(db)
    return makeCore(db, decTable)

proc loadNodes*(start: string): seq[Node] =

    var nId, pId, childId: int

    let query = "select nodeId, parentId, branchingVariable, isLeftChild, value, isSolution from Node where parentId = ? order by nodeId asc"

    for row1 in db.fastRows(sql(query), start):
        discard parseInt(row1[0], nId)

        discard parseInt(row1[1], pId)

        var childCount : int
        discard db.getValue(sql"select count(nodeId) from Node where parentId = ?", row1[0]).parseInt(childCount)

        let vName = db.getValue(sql"select branchingVariable from Node where nodeId = ?", pId)
        let value = db.getValue(sql"select value from Node where nodeId = ?", pId)
        
        let l = getLabel(getInitialVariables(), vName, row1[3], value)
        let pL = getLabel(getInitialVariables(), vName, row1[3], value, true)

        var decCount = 0
        if (decTable.hasKey(nId)):
            decCount = decTable[nId]

        result.add(Node(parentId: pId, id: nId, label:l, prettyLabel: pL, isLeftChild: parsebool(row1[3]), childCount: childCount, decCount: decCount))


proc getExpandedSetChild*(nodeId, path: string): Set =

    # echo prettyLookup[nodeId]

    result = Set(prettyLookup[nodeId][path.split(".")[0]])

    for name in path.split(".")[1..^1]:
        for kid in result.children:
            if kid.name == name:
                result = kid
                break;

    if result.name != path.split(".")[^1]:
        return nil


proc getChildSets(paths, nodeId: string): seq[Set] =
    if paths != "":
        for path in paths.split(":"):
            result.add(getExpandedSetChild(nodeId, path))


proc getJsonVarList*(domainsAtNode: seq[Variable], nodeId: string): JsonNode =
    result = %*[]

    for v in domainsAtNode:
        if (v != nil):
            if (v of Set):
                result.add(setToJson(Set(v), nodeId, true))
            else:
                result.add(%v)

proc loadSetChild*(nodeId, path: string): JsonNode =
    let s = getExpandedSetChild(nodeId, path)
    let update = setToJson(s, nodeId, true)
    return %*{"structure": %setToTreeView(s), "update": update, "path": path}


proc prettifyDomains(db: DbConn, nodeId, paths: string, wantExpressions: bool = false): PrettyDomainResponse =
    new result
    var domainsAtNode: seq[Variable]
    var domainsAtPrev: seq[Variable]
    var changedExpressions: seq[Expression]
    var changedList: seq[string]
    var id: int
    discard parseInt(nodeId, id)

    domainsAtNode.deepCopy(getPrettyDomainsOfNode(db, nodeId, wantExpressions))

    for kid in getChildSets(paths, nodeId):
        if kid != nil:
            domainsAtNode.add(kid)

    if (id != rootNodeId):
        let oldId = $(id - 1)
        domainsAtPrev = getPrettyDomainsOfNode(db, oldId, wantExpressions)

        for kid in getChildSets(paths, oldId):
            if kid != nil:
                domainsAtPrev.add(kid)

        (changedList, changedExpressions) = getPrettyChanges(domainsAtNode, domainsAtPrev)

    return PrettyDomainResponse(vars: getJsonVarList(domainsAtNode, nodeId), changed: changedList, changedExpressions: expressionsToJson(changedExpressions))

proc getSkeleton*(): TreeViewNode =
    return domainsToJson(getPrettyDomainsOfNode(db, "0", true))

proc loadPrettyDomains*(nodeId: string,  paths: string, wantExpressions: bool = false): PrettyDomainResponse =
    prettifyDomains(db, nodeId, paths, wantExpressions)

proc loadSimpleDomains*(nodeId: string, wantExpressions: bool = false): SimpleDomainResponse =

    var list: seq[string]
    var id: int
    var domainsAtPrev: seq[Variable]
    discard parseInt(nodeId, id)

    let domainsAtNode = getSimpleDomainsOfNode(db, nodeId, wantExpressions)

    if (id != rootNodeId):
        domainsAtPrev = getSimpleDomainsOfNode(db, $(id - 1), wantExpressions)

        for i in 0..<domainsAtNode.len():
            if (domainsAtNode[i].rng != domainsAtPrev[i].rng):
                list.add(domainsAtNode[i].name)

    return SimpleDomainResponse(changedNames: list, vars: domainsAtNode)


proc getLongestBranchingVarName*(): JsonNode =
    return % db.getRow(sql"select max(length(branchingVariable)) from Node")[0]

proc getSet*(nodeId: string): Set =
    for d in getPrettyDomainsOfNode(db, nodeId):
        if d of Set:
            return Set(d)
    return nil