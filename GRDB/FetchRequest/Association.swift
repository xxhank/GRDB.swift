/// TODO
public protocol Association {
    /// TODO
    func joinedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource)
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
    func joinedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var (query, baseTarget) = baseAssociation.joinedQuery(query, leftSource: leftSource)
        for association in joinedAssociations {
            (query, _) = association.joinedQuery(query, leftSource: baseTarget)
        }
        return (query, baseTarget)
    }
    
    /// TODO
    func fork() -> CompoundAssociation {
        return CompoundAssociation(baseAssociation: baseAssociation.fork(), joinedAssociations: joinedAssociations.map { $0.fork() })
    }
}

extension QueryInterfaceRequest {
    /// TODO: doc
    public func join(associations: Association...) -> QueryInterfaceRequest<T> {
        return join(associations)
    }
    
    /// TODO: doc
    /// TODO: test that request.join([assoc1, assoc2]) <=> request.join([assoc1]).join([assoc2]) 
    public func join(associations: [Association]) -> QueryInterfaceRequest<T> {
        var query = self.query
        let leftSource = query.source!.leftSourceForJoins
        for association in associations {
            (query, _) = association.joinedQuery(query, leftSource: leftSource)
        }
        return QueryInterfaceRequest(query: query)
    }
}