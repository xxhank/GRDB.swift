/// TODO
public struct BelongsToAssociation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [ownedColumn: ownerColumn]
    let ownerSource: _SQLSourceTable
    
    /// TODO
    public init(name: String, tableName: String, foreignKey: [String: String]) {
        self.init(name: name, ownerSource: _SQLSourceTable(tableName: tableName, alias: nil), foreignKey: foreignKey)
    }
    
    init(name: String, ownerSource: _SQLSourceTable, foreignKey: [String: String]) {
        self.name = name
        self.ownerSource = ownerSource
        self.foreignKey = foreignKey
    }
}

extension BelongsToAssociation : Association {
    /// TODO
    public func joinedQuery(query: _SQLSelectQuery, joinOrigin: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var query = query
        query.source = _SQLSourceJoinBelongsTo(
            baseSource: query.source!,
            ownedSource: joinOrigin,
            ownerSource: ownerSource,
            foreignKey: foreignKey,
            variantName: name,
            variantSelectionIndex: query.selection.count)
        query.selection.append(_SQLResultColumn.Star(ownerSource))
        return (query, ownerSource)
    }
    
    /// TODO
    public func fork() -> BelongsToAssociation {
        return BelongsToAssociation(name: name, ownerSource: ownerSource.copy(), foreignKey: foreignKey)
    }
}

final class _SQLSourceJoinBelongsTo: _SQLSource {
    private let baseSource: _SQLSource
    private let ownedSource: _SQLSource
    private let ownerSource: _SQLSource
    private let foreignKey: [String: String] // [ownedColumn: ownerColumn]
    private let variantName: String
    private let variantSelectionIndex: Int
    
    init(baseSource: _SQLSource, ownedSource: _SQLSource, ownerSource: _SQLSource, foreignKey: [String: String], variantName: String, variantSelectionIndex: Int) {
        self.baseSource = baseSource
        self.ownedSource = ownedSource
        self.ownerSource = ownerSource
        self.foreignKey = foreignKey
        self.variantName = variantName
        self.variantSelectionIndex = variantSelectionIndex
    }
    
    var name: String? {
        get { return baseSource.name }
        set { baseSource.name = newValue }
    }
    
    var referencedSources: [_SQLSource] {
        return [baseSource, ownedSource, ownerSource]
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        var sql = try baseSource.sql(db, &bindings)
        let ownerSourceSQL = try ownerSource.sql(db, &bindings)
        sql += " LEFT JOIN " + ownerSourceSQL + " ON "
        sql += foreignKey.map({ (ownedColumn, ownerColumn) -> String in
            "\(ownerSource.name!.quotedDatabaseIdentifier).\(ownerColumn.quotedDatabaseIdentifier) = \(ownedSource.name!.quotedDatabaseIdentifier).\(ownedColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
    }
    
    func copy() -> _SQLSourceJoinBelongsTo {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter? {
        let columnIndex = columnIndexForSelectionIndex[variantSelectionIndex]!
        let adapter = RowAdapter(mainRowAdapter: RowAdapter(fromColumnAtIndex: columnIndex), variantRowAdapters: variantRowAdapters)
        return baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [variantName: adapter])
    }
}
