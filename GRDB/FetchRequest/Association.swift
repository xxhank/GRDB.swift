/// TODO
public protocol Association {
    /// TODO
    @warn_unused_result
    func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource)
    /// TODO
    @warn_unused_result
    func fork() -> Self
    /// TODO
    @warn_unused_result
    func aliased(alias: String) -> Association
}

extension Association {
    /// TODO
    /// extension Method
    @warn_unused_result
    public func include(associations: Association...) -> Association {
        return include(associations)
    }
    
    /// TODO
    @warn_unused_result
    public func include(associations: [Association]) -> Association {
        return CompoundAssociation(baseAssociation: self, includedAssociations: associations.map { $0.fork() })
    }
}

struct CompoundAssociation {
    let baseAssociation: Association
    let includedAssociations: [Association]
}

extension CompoundAssociation : Association {
    func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
        var (query, baseTarget) = baseAssociation.includedQuery(query, leftSource: leftSource)
        for association in includedAssociations {
            (query, _) = association.includedQuery(query, leftSource: baseTarget)
        }
        return (query, baseTarget)
    }
    
    /// TODO
    func fork() -> CompoundAssociation {
        return CompoundAssociation(baseAssociation: baseAssociation.fork(), includedAssociations: includedAssociations.map { $0.fork() })
    }
    
    func aliased(alias: String) -> Association {
        return CompoundAssociation(baseAssociation: baseAssociation.aliased(alias), includedAssociations: includedAssociations)
    }
}

/// TODO
public struct OneToOneAssociation {
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

extension OneToOneAssociation : Association {
    /// TODO
    public func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
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
    public func fork() -> OneToOneAssociation {
        return OneToOneAssociation(name: name, rightSource: rightSource.copy(), foreignKey: foreignKey)
    }
    
    /// TODO
    @warn_unused_result
    public func aliased(alias: String) -> Association {
        let rightSource = self.rightSource.copy()
        rightSource.alias = alias
        return OneToOneAssociation(name: name, rightSource: rightSource, foreignKey: foreignKey)
    }
}

extension QueryInterfaceRequest {
    /// TODO: doc
    @warn_unused_result
    public func include(associations: Association...) -> QueryInterfaceRequest<T> {
        return include(associations)
    }
    
    /// TODO: doc
    /// TODO: test that request.include([assoc1, assoc2]) <=> request.include([assoc1]).include([assoc2])
    @warn_unused_result
    public func include(associations: [Association]) -> QueryInterfaceRequest<T> {
        var query = self.query
        let leftSource = query.source!.leftSourceForJoins
        for association in associations {
            (query, _) = association.includedQuery(query, leftSource: leftSource)
        }
        return QueryInterfaceRequest(query: query)
    }
}

extension TableMapping {
    /// TODO: doc
    @warn_unused_result
    public static func include(associations: Association...) -> QueryInterfaceRequest<Self> {
        return all().include(associations)
    }
    
    /// TODO: doc
    @warn_unused_result
    public static func include(associations: [Association]) -> QueryInterfaceRequest<Self> {
        return all().include(associations)
    }
}