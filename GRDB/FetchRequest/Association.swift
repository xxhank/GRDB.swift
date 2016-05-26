/// TODO
public protocol Association {
//    /// TODO
//    @warn_unused_result
//    func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource)
    /// TODO
    @warn_unused_result
    func fork() -> Self
    /// TODO
    @warn_unused_result
    func aliased(alias: String) -> Association
    
    /// TODO
    @warn_unused_result
    func numberOfColumns(db: Database) throws -> Int
    
    /// TODO
    var referencedSources: [_SQLSource] { get }
    
    var rightSource: _SQLSource { get }
    
    /// TODO
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String
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
        return ChainedAssociation(baseAssociation: self, rightAssociations: associations.map { $0.fork() })
    }
}

struct ChainedAssociation {
    let baseAssociation: Association
    let rightAssociations: [Association]
}

extension ChainedAssociation : Association {
//    func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
//        var (query, baseTarget) = baseAssociation.includedQuery(query, leftSource: leftSource)
//        for association in rightAssociations {
//            (query, _) = association.includedQuery(query, leftSource: baseTarget)
//        }
//        return (query, baseTarget)
//    }
    
    /// TODO
    func fork() -> ChainedAssociation {
        return ChainedAssociation(baseAssociation: baseAssociation.fork(), rightAssociations: rightAssociations.map { $0.fork() })
    }
    
    /// TODO
    func aliased(alias: String) -> Association {
        return ChainedAssociation(baseAssociation: baseAssociation.aliased(alias), rightAssociations: rightAssociations)
    }
    
    /// TODO
    @warn_unused_result
    func numberOfColumns(db: Database) throws -> Int {
        return try rightAssociations.reduce(baseAssociation.numberOfColumns(db)) { try $0 + $1.numberOfColumns(db) }
    }
    
    /// TODO
    var referencedSources: [_SQLSource] {
        return rightAssociations.reduce(baseAssociation.referencedSources) { $0 + $1.referencedSources }
    }
    
    /// TODO
    var rightSource: _SQLSource {
        return baseAssociation.rightSource
    }
    
    /// TODO
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String {
        var sql = try baseAssociation.sql(db, &bindings, leftSourceName: leftSourceName)
        sql += try rightAssociations.map {
            try $0.sql(db, &bindings, leftSourceName: baseAssociation.rightSource.name!)
        }.joinWithSeparator(" ")
        return sql
    }
}

/// TODO
public struct OneToOneAssociation {
    /// TODO
    public let name: String
    /// TODO
    public let foreignKey: [String: String] // [leftColumn: rightColumn]
    /// TODO
    public let rightSource: _SQLSource
    
    /// TODO
    public init(name: String, tableName: String, foreignKey: [String: String]) {
        self.init(name: name, rightSource: _SQLSourceTable(tableName: tableName, alias: ((name == tableName) ? nil : name)), foreignKey: foreignKey)
    }
    
    init(name: String, rightSource: _SQLSource, foreignKey: [String: String]) {
        self.name = name
        self.rightSource = rightSource
        self.foreignKey = foreignKey
    }
}

extension OneToOneAssociation : Association {
//    /// TODO
//    public func includedQuery(query: _SQLSelectQuery, leftSource: _SQLSource) -> (_SQLSelectQuery, _SQLSource) {
//        var query = query
//        query.source = _SQLSourceJoin(
//            baseSource: query.source!,
//            leftSource: leftSource,
//            rightSource: rightSource,
//            foreignKey: foreignKey,
//            variantName: name,
//            variantSelectionIndex: query.selection.count)
//        query.selection.append(_SQLResultColumn.Star(rightSource))
//        return (query, rightSource)
//    }
    
    /// TODO
    public func fork() -> OneToOneAssociation {
        return OneToOneAssociation(name: name, rightSource: rightSource.copy(), foreignKey: foreignKey)
    }
    
    /// TODO
    @warn_unused_result
    public func aliased(alias: String) -> Association {
        let rightSource = self.rightSource.copy()
        rightSource.name = name
        return OneToOneAssociation(name: name, rightSource: rightSource, foreignKey: foreignKey)
    }
    
    /// TODO
    @warn_unused_result
    public func numberOfColumns(db: Database) throws -> Int {
        return try rightSource.numberOfColumns(db)
    }
    
    /// TODO
    public var referencedSources: [_SQLSource] {
        return rightSource.referencedSources
    }
    
    /// TODO
    public func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?], leftSourceName: String) throws -> String {
        var sql = try "LEFT JOIN " + rightSource.sql(db, &bindings) + " ON "
        sql += foreignKey.map({ (leftColumn, rightColumn) -> String in
            "\(rightSource.name!.quotedDatabaseIdentifier).\(rightColumn.quotedDatabaseIdentifier) = \(leftSourceName.quotedDatabaseIdentifier).\(leftColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
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
        var source = query.source!
        for association in associations {
            source = source.include(association)
        }
        query.source = source
        return QueryInterfaceRequest(query: query)
//        var query = self.query
//        let leftSource = query.source!.leftSourceForJoins
//        for association in associations {
//            (query, _) = association.includedQuery(query, leftSource: leftSource)
//        }
//        return QueryInterfaceRequest(query: query)
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
