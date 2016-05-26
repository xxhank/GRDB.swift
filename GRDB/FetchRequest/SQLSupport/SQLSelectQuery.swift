

// MARK: - _SQLSelectQuery

/// This type is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public struct _SQLSelectQuery {
    var selection: [_SQLSelectable]
    var distinct: Bool
    var source: _SQLSource?
    var whereExpression: _SQLExpression?
    var groupByExpressions: [_SQLExpression]
    var sortDescriptors: [_SQLSortDescriptorType]
    var reversed: Bool
    var havingExpression: _SQLExpression?
    var limit: _SQLLimit?
    
    init(
        select selection: [_SQLSelectable],
        distinct: Bool = false,
        from source: _SQLSource? = nil,
        filter whereExpression: _SQLExpression? = nil,
        groupBy groupByExpressions: [_SQLExpression] = [],
        orderBy sortDescriptors: [_SQLSortDescriptorType] = [],
        reversed: Bool = false,
        having havingExpression: _SQLExpression? = nil,
        limit: _SQLLimit? = nil)
    {
        self.selection = selection
        self.distinct = distinct
        self.source = source
        self.whereExpression = whereExpression
        self.groupByExpressions = groupByExpressions
        self.sortDescriptors = sortDescriptors
        self.reversed = reversed
        self.havingExpression = havingExpression
        self.limit = limit
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        // Prevent source ambiguity
        if let source = source {
            var sourcesByName: [String: [_SQLSource]] = [:]
            for source in source.referencedSources {
                guard let name = source.name else { continue }
                var sources = sourcesByName[name] ?? []
                guard sources.indexOf({ $0 === source }) == nil else {
                    continue
                }
                sources.append(source)
                sourcesByName[name] = sources
            }
            for (name, sources) in sourcesByName where sources.count > 1 {
                for (index, source) in sources.enumerate() {
                    source.name = "\(name)\(index)"
                }
            }
        }
        
        var sql = "SELECT"
        
        if distinct {
            sql += " DISTINCT"
        }
        
        assert(!selection.isEmpty)
        if case .Star(let starSource) = selection[0].sqlSelectableKind where starSource === source {
            sql += " *"
        } else {
            sql += try " " + selection.map { try $0.resultColumnSQL(db, &bindings) }.joinWithSeparator(", ")
        }
        
        if let source = source {
            sql += try " FROM " + source.sql(db, &bindings)
        }
        
        if let whereExpression = whereExpression {
            sql += try " WHERE " + whereExpression.sql(db, &bindings)
        }
        
        if !groupByExpressions.isEmpty {
            sql += try " GROUP BY " + groupByExpressions.map { try $0.sql(db, &bindings) }.joinWithSeparator(", ")
        }
        
        if let havingExpression = havingExpression {
            sql += try " HAVING " + havingExpression.sql(db, &bindings)
        }
        
        var sortDescriptors = self.sortDescriptors
        if reversed {
            if sortDescriptors.isEmpty {
                // https://www.sqlite.org/lang_createtable.html#rowid
                //
                // > The rowid value can be accessed using one of the special
                // > case-independent names "rowid", "oid", or "_rowid_" in
                // > place of a column name. If a table contains a user defined
                // > column named "rowid", "oid" or "_rowid_", then that name
                // > always refers the explicitly declared column and cannot be
                // > used to retrieve the integer rowid value.
                //
                // Here we assume that _rowid_ is not a custom column.
                // TODO: support for user-defined _rowid_ column.
                // TODO: support for WITHOUT ROWID tables.
                sortDescriptors = [SQLColumn("_rowid_").desc]
            } else {
                sortDescriptors = sortDescriptors.map { $0.reversedSortDescriptor }
            }
        }
        if !sortDescriptors.isEmpty {
            sql += try " ORDER BY " + sortDescriptors.map { try $0.orderingSQL(db, &bindings) }.joinWithSeparator(", ")
        }
        
        if let limit = limit {
            sql += " LIMIT " + limit.sql
        }
        
        return sql
    }
    
    /// Returns a query that counts the number of rows matched by self.
    var countQuery: _SQLSelectQuery {
        guard groupByExpressions.isEmpty && limit == nil else {
            // SELECT ... GROUP BY ...
            // SELECT ... LIMIT ...
            return trivialCountQuery
        }
        
        guard let table = source as? _SQLSourceTable else {
            // SELECT ... FROM (something which is not a table)
            return trivialCountQuery
        }
        
        assert(!selection.isEmpty)
        if selection.count == 1 {
            let selectable = self.selection[0]
            switch selectable.sqlSelectableKind {
            case .Star(source: let source):
                guard !distinct else {
                    return trivialCountQuery
                }
                
                guard source === table else {
                    return trivialCountQuery
                }
                
                // SELECT * FROM tableName ...
                // ->
                // SELECT COUNT(*) FROM tableName ...
                var countQuery = unorderedQuery
                countQuery.selection = [_SQLExpression.Count(selectable)]
                return countQuery
                
            case .Expression(let expression):
                // SELECT [DISTINCT] expr FROM tableName ...
                if distinct {
                    // SELECT DISTINCT expr FROM tableName ...
                    // ->
                    // SELECT COUNT(DISTINCT expr) FROM tableName ...
                    var countQuery = unorderedQuery
                    countQuery.distinct = false
                    countQuery.selection = [_SQLExpression.CountDistinct(expression)]
                    return countQuery
                } else {
                    // SELECT expr FROM tableName ...
                    // ->
                    // SELECT COUNT(*) FROM tableName ...
                    var countQuery = unorderedQuery
                    countQuery.selection = [_SQLExpression.Count(_SQLResultColumn.Star(table))]
                    return countQuery
                }
            }
        } else {
            // SELECT [DISTINCT] expr1, expr2, ... FROM tableName ...
            
            guard !distinct else {
                return trivialCountQuery
            }

            // SELECT expr1, expr2, ... FROM tableName ...
            // ->
            // SELECT COUNT(*) FROM tableName ...
            var countQuery = unorderedQuery
            countQuery.selection = [_SQLExpression.Count(_SQLResultColumn.Star(table))]
            return countQuery
        }
    }
    
    // SELECT COUNT(*) FROM (self)
    private var trivialCountQuery: _SQLSelectQuery {
        let source = _SQLSourceQuery(query: unorderedQuery, name: nil)
        return _SQLSelectQuery(
            select: [_SQLExpression.Count(_SQLResultColumn.Star(source))],
            from: source)
    }
    
    /// Remove ordering
    private var unorderedQuery: _SQLSelectQuery {
        var query = self
        query.reversed = false
        query.sortDescriptors = []
        return query
    }
    
    func adapter(statement: SelectStatement) throws -> RowAdapter? {
        guard let source = source else {
            return nil
        }
        // Our sources define variant based on selection index:
        //
        //      SELECT a.*, b.* FROM a JOIN b ...
        //                  ^ variant at selection index 1
        //
        // Now that we have a statement, we can turn those indexes into
        // column indexes:
        //
        //      SELECT a.id, a.name, b.id, b.title FROM a JOIN b ...
        //                           ^ variant at column index 2
        var columnIndex = 0
        var columnIndexForSelectionIndex: [Int: Int] = [:]
        for (selectionIndex, selectable) in selection.enumerate() {
            columnIndexForSelectionIndex[selectionIndex] = columnIndex
            switch selectable.sqlSelectableKind {
            case .Expression:
                columnIndex += 1
            case .Star(let source):
                columnIndex += try source.numberOfColumns(statement.database)
            }
        }
        
        return source.adapter(columnIndexForSelectionIndex, variantRowAdapters: [:])
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        return try selection.reduce(0) { (count, let selectable) in
            switch selectable.sqlSelectableKind {
            case .Expression:
                return count + 1
            case .Star(let source):
                return try count + source.numberOfColumns(db)
            }
        }
    }
}


// MARK: - _SQLSource

/// TODO
public protocol _SQLSource: class {
    var name: String? { get set }
    var leftSourceForJoins: _SQLSource { get }
    var referencedSources: [_SQLSource] { get }
    func numberOfColumns(db: Database) throws -> Int
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter?
    func copy() -> Self
}

extension _SQLSource {
    // Default implementation
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter? {
        // TODO: fix this not elegant code
        if variantRowAdapters.isEmpty {
            return nil
        } else {
            return RowAdapter(mainRowAdapter: nil, variantRowAdapters: variantRowAdapters)
        }
    }
}

final class _SQLSourceTable : _SQLSource {
    private let tableName: String
    var alias: String?
    
    init(tableName: String, alias: String?) {
        self.tableName = tableName
        self.alias = alias
    }
    
    var name : String? {
        get { return alias ?? tableName }
        set { alias = newValue }
    }
    
    var leftSourceForJoins: _SQLSource {
        return self
    }
    
    var referencedSources: [_SQLSource] {
        return [self]
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        return try db.numberOfColumns(tableName)
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        if let alias = alias {
            return tableName.quotedDatabaseIdentifier + " " + alias.quotedDatabaseIdentifier
        } else {
            return tableName.quotedDatabaseIdentifier
        }
    }
    
    func copy() -> _SQLSourceTable {
        return _SQLSourceTable(tableName: tableName, alias: alias)
    }
}

extension _SQLSourceTable : CustomStringConvertible {
    var description: String {
        if let alias = alias {
            return "\(tableName) AS \(alias)"
        } else {
            return tableName
        }
    }
}

final class _SQLSourceQuery: _SQLSource {
    private let query: _SQLSelectQuery
    var name: String?
    
    init(query: _SQLSelectQuery, name: String?) {
        self.query = query
        self.name = name
    }
    
    var leftSourceForJoins: _SQLSource {
        return self
    }
    
    var referencedSources: [_SQLSource] {
        if let source = query.source {
            return [self] + source.referencedSources
        }
        return [self]
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        return try query.numberOfColumns(db)
    }

    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        if let name = name {
            return try "(" + query.sql(db, &bindings) + ") AS " + name.quotedDatabaseIdentifier
        } else {
            return try "(" + query.sql(db, &bindings) + ")"
        }
    }
    
    func copy() -> _SQLSourceQuery {
        return _SQLSourceQuery(query: query, name: name)
    }
}

final class _SQLSourceJoin: _SQLSource {
    private let baseSource: _SQLSource
    private let leftSource: _SQLSource
    private let rightSource: _SQLSource
    private let foreignKey: [String: String] // [leftColumn: rightColumn]
    private let variantName: String
    private let variantSelectionIndex: Int
    
    init(baseSource: _SQLSource, leftSource: _SQLSource, rightSource: _SQLSource, foreignKey: [String: String], variantName: String, variantSelectionIndex: Int) {
        self.baseSource = baseSource
        self.leftSource = leftSource
        self.rightSource = rightSource
        self.foreignKey = foreignKey
        self.variantName = variantName
        self.variantSelectionIndex = variantSelectionIndex
    }
    
    var name: String? {
        get { return rightSource.name }
        set { rightSource.name = newValue }
    }
    
    var leftSourceForJoins: _SQLSource {
        return baseSource.leftSourceForJoins
    }
    
    var variantSource: _SQLSource {
        return leftSource
    }
    
    var referencedSources: [_SQLSource] {
        return baseSource.referencedSources + leftSource.referencedSources + rightSource.referencedSources
    }
    
    func numberOfColumns(db: Database) throws -> Int {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        var sql = try baseSource.sql(db, &bindings)
        let rightSourceSQL = try rightSource.sql(db, &bindings)
        sql += " LEFT JOIN " + rightSourceSQL + " ON "
        sql += foreignKey.map({ (leftColumn, rightColumn) -> String in
            "\(rightSource.name!.quotedDatabaseIdentifier).\(rightColumn.quotedDatabaseIdentifier) = \(leftSource.name!.quotedDatabaseIdentifier).\(leftColumn.quotedDatabaseIdentifier)"
        }).joinWithSeparator(" AND ")
        return sql
    }
    
    func copy() -> _SQLSourceJoin {
        fatalError("TODO: this code is never run and this method should not exist")
    }
    
    func adapter(columnIndexForSelectionIndex: [Int: Int], variantRowAdapters: [String: RowAdapter]) -> RowAdapter? {
        let columnIndex = columnIndexForSelectionIndex[variantSelectionIndex]!
        
//        if mergeVariants {
//            let adapter = baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [:], mergeVariants: variantSource === baseSource.variantSource) ?? RowAdapter(mainRowAdapter: nil, variantRowAdapters: [:])
//            return adapter.addingVariantAdapter(RowAdapter(fromColumnAtIndex: columnIndex), named: variantName)
//        } else {
//            let adapter = RowAdapter(mainRowAdapter: RowAdapter(fromColumnAtIndex: columnIndex), variantRowAdapters: variantRowAdapters)
//            return baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [variantName: adapter], mergeVariants: variantSource === baseSource.variantSource)
//        }
        let adapter = RowAdapter(mainRowAdapter: RowAdapter(fromColumnAtIndex: columnIndex), variantRowAdapters: variantRowAdapters)
        return baseSource.adapter(columnIndexForSelectionIndex, variantRowAdapters: [variantName: adapter])
    }
}

extension _SQLSourceJoin : CustomStringConvertible {
    var description: String {
        return "<base: \(baseSource) left:\(leftSource) right:\(rightSource)>"
    }
}


// MARK: - _SQLSortDescriptorType

/// This protocol is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public protocol _SQLSortDescriptorType {
    var reversedSortDescriptor: _SQLSortDescriptor { get }
    func orderingSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String
}

/// This type is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public enum _SQLSortDescriptor {
    case Asc(_SQLExpression)
    case Desc(_SQLExpression)
}

extension _SQLSortDescriptor : _SQLSortDescriptorType {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var reversedSortDescriptor: _SQLSortDescriptor {
        switch self {
        case .Asc(let expression):
            return .Desc(expression)
        case .Desc(let expression):
            return .Asc(expression)
        }
    }
    
    /// This method is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public func orderingSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        switch self {
        case .Asc(let expression):
            return try expression.sql(db, &bindings) + " ASC"
        case .Desc(let expression):
            return try expression.sql(db, &bindings) + " DESC"
        }
    }
}


// MARK: - _SQLLimit

struct _SQLLimit {
    let limit: Int
    let offset: Int?
    
    var sql: String {
        if let offset = offset {
            return "\(limit) OFFSET \(offset)"
        } else {
            return "\(limit)"
        }
    }
}


// MARK: - _SQLExpressionType

public protocol _SQLExpressionType {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    var sqlExpression: _SQLExpression { get }
}

// Conformance to _SQLExpressionType
extension DatabaseValueConvertible {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var sqlExpression: _SQLExpression {
        return .Value(self)
    }
}

/// This protocol is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public protocol _SQLDerivedExpressionType : _SQLExpressionType, _SQLSortDescriptorType, _SQLSelectable {
}

// Conformance to _SQLSortDescriptorType
extension _SQLDerivedExpressionType {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var reversedSortDescriptor: _SQLSortDescriptor {
        return .Desc(sqlExpression)
    }
    
    /// This method is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public func orderingSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        return try sqlExpression.sql(db, &bindings)
    }
}

// Conformance to _SQLSelectable
extension _SQLDerivedExpressionType {
    
    /// This method is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public func resultColumnSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        return try sqlExpression.sql(db, &bindings)
    }
    
    /// This method is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public func countedSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        return try sqlExpression.sql(db, &bindings)
    }
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var sqlSelectableKind: _SQLSelectableKind {
        return .Expression(sqlExpression)
    }
}

extension _SQLDerivedExpressionType {
    
    /// Returns a value that can be used as an argument to FetchRequest.order()
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var asc: _SQLSortDescriptor {
        return .Asc(sqlExpression)
    }
    
    /// Returns a value that can be used as an argument to FetchRequest.order()
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var desc: _SQLSortDescriptor {
        return .Desc(sqlExpression)
    }
    
    /// Returns a value that can be used as an argument to FetchRequest.select()
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public func aliased(alias: String) -> _SQLSelectable {
        return _SQLResultColumn.Expression(expression: sqlExpression, alias: alias)
    }
}


/// This type is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public indirect enum _SQLExpression {
    /// For example: `name || 'rrr' AS pirateName`
    case Literal(String)
    
    /// For example: `1` or `'foo'`
    case Value(DatabaseValueConvertible?)
    
    /// For example: `name`, `table.name`
    case Identifier(identifier: String, sourceName: String?)
    
    /// For example: `name = 'foo' COLLATE NOCASE`
    case Collate(_SQLExpression, String)
    
    /// For example: `NOT condition`
    case Not(_SQLExpression)
    
    /// For example: `name = 'foo'`
    case Equal(_SQLExpression, _SQLExpression)
    
    /// For example: `name <> 'foo'`
    case NotEqual(_SQLExpression, _SQLExpression)
    
    /// For example: `name IS NULL`
    case Is(_SQLExpression, _SQLExpression)
    
    /// For example: `name IS NOT NULL`
    case IsNot(_SQLExpression, _SQLExpression)
    
    /// For example: `-value`
    case PrefixOperator(String, _SQLExpression)
    
    /// For example: `age + 1`
    case InfixOperator(String, _SQLExpression, _SQLExpression)
    
    /// For example: `id IN (1,2,3)`
    case In([_SQLExpression], _SQLExpression)
    
    /// For example `id IN (SELECT ...)`
    case InSubQuery(_SQLSelectQuery, _SQLExpression)
    
    /// For example `EXISTS (SELECT ...)`
    case Exists(_SQLSelectQuery)
    
    /// For example: `age BETWEEN 1 AND 2`
    case Between(value: _SQLExpression, min: _SQLExpression, max: _SQLExpression)
    
    /// For example: `LOWER(name)`
    case Function(String, [_SQLExpression])
    
    /// For example: `COUNT(*)`
    case Count(_SQLSelectable)
    
    /// For example: `COUNT(DISTINCT name)`
    case CountDistinct(_SQLExpression)
    
    ///
    func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        // TODO: this method is slow to compile
        // https://medium.com/swift-programming/speeding-up-slow-swift-build-times-922feeba5780#.s77wmh4h0
        // 10746.4ms	/Users/groue/Documents/git/groue/GRDB.swift/GRDB/FetchRequest/SQLSelectQuery.swift:439:10	func sql(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String
        switch self {
        case .Literal(let sql):
            return sql
            
        case .Value(let value):
            guard let value = value else {
                return "NULL"
            }
            bindings.append(value)
            return "?"
            
        case .Identifier(let identifier, let sourceName):
            if let sourceName = sourceName {
                return sourceName.quotedDatabaseIdentifier + "." + identifier.quotedDatabaseIdentifier
            } else {
                return identifier.quotedDatabaseIdentifier
            }
            
        case .Collate(let expression, let collation):
            let sql = try expression.sql(db, &bindings)
            let chars = sql.characters
            if chars.last! == ")" {
                return String(chars.prefixUpTo(chars.endIndex.predecessor())) + " COLLATE " + collation + ")"
            } else {
                return sql + " COLLATE " + collation
            }
            
        case .Not(let condition):
            switch condition {
            case .Not(let expression):
                return try expression.sql(db, &bindings)
                
            case .In(let expressions, let expression):
                if expressions.isEmpty {
                    return "1"
                } else {
                    return try "(" + expression.sql(db, &bindings) + " NOT IN (" + expressions.map { try $0.sql(db, &bindings) }.joinWithSeparator(", ") + "))"
                }
                
            case .InSubQuery(let subQuery, let expression):
                return try "(" + expression.sql(db, &bindings) + " NOT IN (" + subQuery.sql(db, &bindings)  + "))"
                
            case .Exists(let subQuery):
                return try "(NOT EXISTS (" + subQuery.sql(db, &bindings)  + "))"
                
            case .Equal(let lhs, let rhs):
                return try _SQLExpression.NotEqual(lhs, rhs).sql(db, &bindings)
                
            case .NotEqual(let lhs, let rhs):
                return try _SQLExpression.Equal(lhs, rhs).sql(db, &bindings)
                
            case .Is(let lhs, let rhs):
                return try _SQLExpression.IsNot(lhs, rhs).sql(db, &bindings)
                
            case .IsNot(let lhs, let rhs):
                return try _SQLExpression.Is(lhs, rhs).sql(db, &bindings)
                
            default:
                return try "(NOT " + condition.sql(db, &bindings) + ")"
            }
            
        case .Equal(let lhs, let rhs):
            switch (lhs, rhs) {
            case (let lhs, .Value(let rhs)) where rhs == nil:
                // Swiftism!
                // Turn `filter(a == nil)` into `a IS NULL` since the intention is obviously to check for NULL. `a = NULL` would evaluate to NULL.
                return try "(" + lhs.sql(db, &bindings) + " IS NULL)"
            case (.Value(let lhs), let rhs) where lhs == nil:
                // Swiftism!
                return try "(" + rhs.sql(db, &bindings) + " IS NULL)"
            default:
                return try "(" + lhs.sql(db, &bindings) + " = " + rhs.sql(db, &bindings) + ")"
            }
            
        case .NotEqual(let lhs, let rhs):
            switch (lhs, rhs) {
            case (let lhs, .Value(let rhs)) where rhs == nil:
                // Swiftism!
                // Turn `filter(a != nil)` into `a IS NOT NULL` since the intention is obviously to check for NULL. `a <> NULL` would evaluate to NULL.
                return try "(" + lhs.sql(db, &bindings) + " IS NOT NULL)"
            case (.Value(let lhs), let rhs) where lhs == nil:
                // Swiftism!
                return try "(" + rhs.sql(db, &bindings) + " IS NOT NULL)"
            default:
                return try "(" + lhs.sql(db, &bindings) + " <> " + rhs.sql(db, &bindings) + ")"
            }
            
        case .Is(let lhs, let rhs):
            switch (lhs, rhs) {
            case (let lhs, .Value(let rhs)) where rhs == nil:
                return try "(" + lhs.sql(db, &bindings) + " IS NULL)"
            case (.Value(let lhs), let rhs) where lhs == nil:
                return try "(" + rhs.sql(db, &bindings) + " IS NULL)"
            default:
                return try "(" + lhs.sql(db, &bindings) + " IS " + rhs.sql(db, &bindings) + ")"
            }
            
        case .IsNot(let lhs, let rhs):
            switch (lhs, rhs) {
            case (let lhs, .Value(let rhs)) where rhs == nil:
                return try "(" + lhs.sql(db, &bindings) + " IS NOT NULL)"
            case (.Value(let lhs), let rhs) where lhs == nil:
                return try "(" + rhs.sql(db, &bindings) + " IS NOT NULL)"
            default:
                return try "(" + lhs.sql(db, &bindings) + " IS NOT " + rhs.sql(db, &bindings) + ")"
            }
            
        case .PrefixOperator(let SQLOperator, let value):
            return try SQLOperator + value.sql(db, &bindings)
            
        case .InfixOperator(let SQLOperator, let lhs, let rhs):
            return try "(" + lhs.sql(db, &bindings) + " \(SQLOperator) " + rhs.sql(db, &bindings) + ")"
            
        case .In(let expressions, let expression):
            guard !expressions.isEmpty else {
                return "0"
            }
            return try "(" + expression.sql(db, &bindings) + " IN (" + expressions.map { try $0.sql(db, &bindings) }.joinWithSeparator(", ")  + "))"
        
        case .InSubQuery(let subQuery, let expression):
            return try "(" + expression.sql(db, &bindings) + " IN (" + subQuery.sql(db, &bindings)  + "))"
            
        case .Exists(let subQuery):
            return try "(EXISTS (" + subQuery.sql(db, &bindings)  + "))"
            
        case .Between(value: let value, min: let min, max: let max):
            return try "(" + value.sql(db, &bindings) + " BETWEEN " + min.sql(db, &bindings) + " AND " + max.sql(db, &bindings) + ")"
            
        case .Function(let functionName, let functionArguments):
            return try functionName + "(" + functionArguments.map { try $0.sql(db, &bindings) }.joinWithSeparator(", ")  + ")"
            
        case .Count(let counted):
            return try "COUNT(" + counted.countedSQL(db, &bindings) + ")"
            
        case .CountDistinct(let expression):
            return try "COUNT(DISTINCT " + expression.sql(db, &bindings) + ")"
        }
    }
}

extension _SQLExpression : _SQLDerivedExpressionType {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var sqlExpression: _SQLExpression {
        return self
    }
}


// MARK: - _SQLSelectable

/// This protocol is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public protocol _SQLSelectable {
    func resultColumnSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String
    func countedSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String
    var sqlSelectableKind: _SQLSelectableKind { get }
}

/// This type is an implementation detail of the query interface.
/// Do not use it directly.
///
/// See https://github.com/groue/GRDB.swift/#the-query-interface
public enum _SQLSelectableKind {
    case Star(_SQLSource)
    case Expression(_SQLExpression)
}

enum _SQLResultColumn {
    case Star(_SQLSource)
    case Expression(expression: _SQLExpression, alias: String)
}

extension _SQLResultColumn : _SQLSelectable {
    
    func resultColumnSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        switch self {
        case .Star(let source):
            if let sourceName = source.name {
                return sourceName.quotedDatabaseIdentifier + ".*"
            } else {
                return "*"
            }
        case .Expression(expression: let expression, alias: let alias):
            return try expression.sql(db, &bindings) + " AS " + alias.quotedDatabaseIdentifier
        }
    }
    
    func countedSQL(db: Database, inout _ bindings: [DatabaseValueConvertible?]) throws -> String {
        switch self {
        case .Star:
            return "*"
        case .Expression(expression: let expression, alias: _):
            return try expression.sql(db, &bindings)
        }
    }
    
    var sqlSelectableKind: _SQLSelectableKind {
        switch self {
        case .Star(let source):
            return .Star(source)
        case .Expression(expression: let expression, alias: _):
            return .Expression(expression)
        }
    }
}


// MARK: _SQLLiteral

struct _SQLLiteral {
    let sql: String
    init(_ sql: String) {
        self.sql = sql
    }
}

extension _SQLLiteral : _SQLDerivedExpressionType {
    var sqlExpression: _SQLExpression {
        return .Literal(sql)
    }
}


// MARK: - SQLColumn

/// A column in the database
///
/// See https://github.com/groue/GRDB.swift#the-query-interface
public struct SQLColumn {
    let sourceName: String?
    
    /// The name of the column
    public let name: String
    
    /// Initializes a column given its name.
    public init(_ name: String) {
        self.name = name
        self.sourceName = nil
    }
    
    init(_ name: String, sourceName: String?) {
        self.name = name
        self.sourceName = sourceName
    }
}

extension SQLColumn : _SQLDerivedExpressionType {
    
    /// This property is an implementation detail of the query interface.
    /// Do not use it directly.
    ///
    /// See https://github.com/groue/GRDB.swift/#the-query-interface
    public var sqlExpression: _SQLExpression {
        return .Identifier(identifier: name, sourceName: sourceName)
    }
}

