public struct HasOneAssociation {
    let name: String
    let childTable: String
    let foreignKey: [String: String] // [primaryKeyColumn: foreignKeyColumn]
    
    public init(name: String, childTable: String, foreignKey: [String: String]) {
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
            if query.selection.count == 1 {
                switch query.selection[0].sqlSelectableKind {
                case .Star(nil):
                    query.selection = [_SQLResultColumn.Star(query.source!.tableName!)]
                default:
                    break
                }
            }
            query.selection.append(_SQLResultColumn.Star(association.name))
            query.source = .JoinHasOne(baseSource: query.source!, association: association)
        }
        return QueryInterfaceRequest(query: query)
    }
}
