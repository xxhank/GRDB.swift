/// TODO
public protocol Association {
    /// TODO
    func joinedQuery(query: _SQLSelectQuery, _ source: _SQLSource) -> (_SQLSelectQuery, _SQLSource)
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
    func joinedQuery(query: _SQLSelectQuery, _ source: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var (query, joinedSource) = baseAssociation.joinedQuery(query, source)
        for association in joinedAssociations {
            (query, _) = association.joinedQuery(query, joinedSource)
        }
        return (query, joinedSource)
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
    let joinedTable: _SQLSourceTable
    
    /// TODO
    public init(name: String, childTable: String, foreignKey: [String: String]) {
        self.init(name: name, joinedTable: _SQLSourceTable(tableName: childTable, alias: nil), foreignKey: foreignKey)
    }
    
    init(name: String, joinedTable: _SQLSourceTable, foreignKey: [String: String]) {
        self.name = name
        self.joinedTable = joinedTable
        self.foreignKey = foreignKey
    }
}

extension HasOneAssociation : Association {
    /// TODO
    public func joinedQuery(query: _SQLSelectQuery, _ source: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var query = query
        query.addSuffixSubrow(named: name)
        query.selection.append(_SQLResultColumn.Star(joinedTable))
        query.source = _SQLSourceJoinHasOne(baseSource: query.source!, joinSource: source, association: self)
        return (query, joinedTable)
    }
    
    /// TODO
    public func fork() -> HasOneAssociation {
        return HasOneAssociation(name: name, joinedTable: joinedTable.copy(), foreignKey: foreignKey)
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
            (query, _) = association.joinedQuery(query, source)
        }
        return QueryInterfaceRequest(query: query)
    }
}
