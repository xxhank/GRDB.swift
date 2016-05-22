public struct HasOneAssociation {
    public let name: String
    public let foreignKey: [String: String] // [primaryKeyColumn: foreignKeyColumn]
    let joinedTable: _SQLSourceTable
    
    public init(name: String, childTable: String, foreignKey: [String: String]) {
        self.name = name
        self.joinedTable = _SQLSourceTable(tableName: childTable, alias: nil)
        self.foreignKey = foreignKey
    }
}

extension QueryInterfaceRequest {
    func include(associations: HasOneAssociation...) -> QueryInterfaceRequest<T> {
        return include(associations)
    }
    
    public func include(associations: [HasOneAssociation]) -> QueryInterfaceRequest<T> {
        var query = self.query
        for association in associations {
            query.addSuffixSubrow(named: association.name)
            query.selection.append(_SQLResultColumn.Star(association.joinedTable))
            query.source = _SQLSourceJoinHasOne(baseSource: query.source!, association: association)
        }
        return QueryInterfaceRequest(query: query)
    }
}
