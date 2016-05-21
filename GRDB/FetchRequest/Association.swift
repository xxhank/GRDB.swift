public struct HasOneAssociation {
    let name: String
    let childTable: String
    let foreignKey: Set<String>
    
    init(name: String, childTable: String, foreignKey: Set<String>) {
        self.name = name
        self.childTable = childTable
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
            query.selection.append(_SQLResultColumn.Star(association.name))
            query.source = .JoinHasOne(baseSource: query.source!, association: association)
        }
        return QueryInterfaceRequest(query: query)
    }
}
