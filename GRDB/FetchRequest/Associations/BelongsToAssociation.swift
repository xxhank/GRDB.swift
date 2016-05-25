/// TODO
public struct BelongsToAssociation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [leftColumn: rightColumn]
    let rightSource: _SQLSourceTable
    
    /// TODO
    public init(name: String, tableName: String, foreignKey: [String: String]) {
        self.init(name: name, rightSource: _SQLSourceTable(tableName: tableName, alias: ((name == tableName) ? nil : name)), foreignKey: foreignKey)
    }
    
    init(name: String, rightSource: _SQLSourceTable, foreignKey: [String: String]) {
        self.name = name
        self.rightSource = rightSource
        self.foreignKey = foreignKey
    }
}

extension BelongsToAssociation : Association {
    /// TODO
    public func joinedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var query = query
        query.source = _SQLSourceJoin(
            baseSource: query.source!,
            leftSource: leftSource,
            rightSource: rightSource,
            foreignKey: foreignKey,
            variantName: name,
            variantSelectionIndex: query.selection.count)
        query.selection.append(_SQLResultColumn.Star(rightSource))
        return (query, rightSource)
    }
    
    /// TODO
    public func fork() -> BelongsToAssociation {
        return BelongsToAssociation(name: name, rightSource: rightSource.copy(), foreignKey: foreignKey)
    }
}
