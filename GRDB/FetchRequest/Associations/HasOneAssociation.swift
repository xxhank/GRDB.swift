/// TODO
public struct HasOneAssociation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [ownerColumn: ownedColumn]
    let ownedSource: _SQLSourceTable
    
    /// TODO
    public init(name: String, tableName: String, foreignKey: [String: String]) {
        self.init(name: name, ownedSource: _SQLSourceTable(tableName: tableName, alias: nil), foreignKey: foreignKey)
    }
    
    init(name: String, ownedSource: _SQLSourceTable, foreignKey: [String: String]) {
        self.name = name
        self.ownedSource = ownedSource
        self.foreignKey = foreignKey
    }
}

extension HasOneAssociation : Association {
    /// TODO
    public func joinedQuery(query: _SQLSelectQuery, joinOrigin: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var query = query
        query.source = _SQLSourceJoinHasOne(
            baseSource: query.source!,
            ownedSource: ownedSource,
            ownerSource: joinOrigin,
            foreignKey: foreignKey,
            variantName: name,
            variantSelectionIndex: query.selection.count)
        query.selection.append(_SQLResultColumn.Star(ownedSource))
        return (query, ownedSource)
    }
    
    /// TODO
    public func fork() -> HasOneAssociation {
        return HasOneAssociation(name: name, ownedSource: ownedSource.copy(), foreignKey: foreignKey)
    }
}

final class _SQLSourceJoinHasOne: _SQLSource {
    private let baseSource: _SQLSource
    private let ownedSource: _SQLSource
    private let ownerSource: _SQLSource
    private let foreignKey: [String: String] // [ownerColumn: ownedColumn]
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
        return [baseSource, ownerSource, ownedSource]
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        var sql = try baseSource.sql(db, &bindings)
        let ownedSourceSQL = try ownedSource.sql(db, &bindings)
        sql += " LEFT JOIN " + ownedSourceSQL + " ON "
        sql += foreignKey.map({ (ownerColumn, ownedColumn) -> String in
            "\(ownedSource.name!.quotedDatabaseIdentifier).\(ownedColumn.quotedDatabaseIdentifier) = \(ownerSource.name!.quotedDatabaseIdentifier).\(ownerColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
    }
    
    func copy() -> _SQLSourceJoinHasOne {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter? {
        let columnIndex = columnIndexForSelectionIndex[variantSelectionIndex]!
        let adapter = RowAdapter(mainRowAdapter: RowAdapter(fromColumnAtIndex: columnIndex), variantRowAdapters: variantRowAdapters)
        return baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [variantName: adapter])
    }
}
