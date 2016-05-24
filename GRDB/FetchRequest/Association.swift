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
