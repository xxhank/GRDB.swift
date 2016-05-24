/// TODO
public protocol Association {
    /// TODO
    func joinedQuery(query: _SQLSelectQuery, joinOrigin: _SQLSource) -> (_SQLSelectQuery, _SQLSource)
    /// TODO
    func fork() -> Self
}

extension Association {
    /// TODO
    /// extension Method
    public func join(associations: Association...) -> Association {
        return join(associations)
    }
    
    /// TODO
    func join(associations: [Association]) -> Association {
        return CompoundAssociation(baseAssociation: self, joinedAssociations: associations.map { $0.fork() })
    }
}

struct CompoundAssociation {
    let baseAssociation: Association
    let joinedAssociations: [Association]
}

extension CompoundAssociation : Association {
    func joinedQuery(query: _SQLSelectQuery, joinOrigin: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var (query, baseTarget) = baseAssociation.joinedQuery(query, joinOrigin: joinOrigin)
        for association in joinedAssociations {
            (query, _) = association.joinedQuery(query, joinOrigin: baseTarget)
        }
        return (query, baseTarget)
    }
    
    /// TODO
    func fork() -> CompoundAssociation {
        return CompoundAssociation(baseAssociation: baseAssociation.fork(), joinedAssociations: joinedAssociations.map { $0.fork() })
    }
}

/// TODO
public struct HasOneAssociation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [primaryKeyColumn: foreignKeyColumn]
    let joinTarget: _SQLSourceTable
    
    /// TODO
    public init(name: String, childTable: String, foreignKey: [String: String]) {
        self.init(name: name, joinTarget: _SQLSourceTable(tableName: childTable, alias: nil), foreignKey: foreignKey)
    }
    
    init(name: String, joinTarget: _SQLSourceTable, foreignKey: [String: String]) {
        self.name = name
        self.joinTarget = joinTarget
        self.foreignKey = foreignKey
    }
}

extension HasOneAssociation : Association {
    /// TODO
    public func joinedQuery(query: _SQLSelectQuery, joinOrigin: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var query = query
        query.source = _SQLSourceJoinHasOne(baseSource: query.source!, joinOrigin: joinOrigin, association: self, variantSelectionIndex: query.selection.count)
        query.selection.append(_SQLResultColumn.Star(joinTarget))
        return (query, joinTarget)
    }
    
    /// TODO
    public func fork() -> HasOneAssociation {
        return HasOneAssociation(name: name, joinTarget: joinTarget.copy(), foreignKey: foreignKey)
    }
}

final class _SQLSourceJoinHasOne: _SQLSource {
    private let baseSource: _SQLSource
    private let joinOrigin: _SQLSource
    private let association: HasOneAssociation
    private let variantSelectionIndex: Int
    
    init(baseSource: _SQLSource, joinOrigin: _SQLSource, association: HasOneAssociation, variantSelectionIndex: Int) {
        self.baseSource = baseSource
        self.joinOrigin = joinOrigin
        self.association = association
        self.variantSelectionIndex = variantSelectionIndex
    }
    
    var name: String? {
        get { return baseSource.name }
        set { baseSource.name = newValue }
    }
    
    var referencedSources: [_SQLSource] {
        return [baseSource, joinOrigin, association.joinTarget]
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        return try baseSource.numberOfColumns(db) + association.joinTarget.numberOfColumns(db)
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        var sql = try baseSource.sql(db, &bindings)
        let joinTargetSQL = try association.joinTarget.sql(db, &bindings)
        sql += " LEFT JOIN " + joinTargetSQL + " ON "
        sql += association.foreignKey.map({ (primaryColumn, foreignColumn) -> String in
            "\(association.joinTarget.name!.quotedDatabaseIdentifier).\(foreignColumn.quotedDatabaseIdentifier) = \(joinOrigin.name!.quotedDatabaseIdentifier).\(primaryColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
    }
    
    func copy() -> _SQLSourceJoinHasOne {
        // TODO: should we fork association?
        // TODO: what should we do with variantSelectionIndex?
        return _SQLSourceJoinHasOne(baseSource: baseSource, joinOrigin: joinOrigin, association: association, variantSelectionIndex: variantSelectionIndex)
    }
    
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter? {
        let columnIndex = columnIndexForSelectionIndex[variantSelectionIndex]!
        let adapter = RowAdapter(mainRowAdapter: RowAdapter(fromColumnAtIndex: columnIndex), variantRowAdapters: variantRowAdapters)
        return baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [association.name: adapter])
    }
}

extension QueryInterfaceRequest {
    /// TODO
    public func join(associations: Association...) -> QueryInterfaceRequest<T> {
        return join(associations)
    }
    
    /// TODO
    public func join(associations: [Association]) -> QueryInterfaceRequest<T> {
        var query = self.query
        let source = query.source!
        for association in associations {
            (query, _) = association.joinedQuery(query, joinOrigin: source)
        }
        return QueryInterfaceRequest(query: query)
    }
}
