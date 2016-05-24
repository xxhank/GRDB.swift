import Foundation

#if !SQLITE_HAS_CODEC
    #if os(OSX)
        import SQLiteMacOSX
    #elseif os(iOS)
        #if (arch(i386) || arch(x86_64))
            import SQLiteiPhoneSimulator
        #else
            import SQLiteiPhoneOS
        #endif
    #endif
#endif

/// A database row.
public final class Row {
    
    // MARK: - Building rows
    
    /// Builds an empty row.
    public convenience init() {
        self.init(impl: EmptyRowImpl())
    }
    
    /// Builds a row from a dictionary of values.
    public convenience init(_ dictionary: [String: DatabaseValueConvertible?]) {
        self.init(impl: DictionaryRowImpl(dictionary: dictionary))
    }
    
    /// Returns a copy of the row.
    ///
    /// Fetched rows are reused during the iteration of a query, for performance
    /// reasons: make sure to make a copy of it whenever you want to keep a
    /// specific one: `row.copy()`.
    @warn_unused_result
    public func copy() -> Row {
        return impl.copy(self)
    }
    
    
    // MARK: - Not Public
    
    let impl: RowImpl
    
    /// Unless we are producing a row array, we use a single row when iterating a
    /// statement:
    ///
    ///     for row in Row.fetch(db, "SELECT ...") { ... }
    ///     for person in Person.fetch(db, "SELECT ...") { ... }
    ///
    /// This row keeps an unmanaged reference to the statement, and a handle to
    /// the sqlite statement, so that we avoid many retain/release invocations.
    ///
    /// The statementRef is released in deinit.
    let statementRef: Unmanaged<SelectStatement>?
    let sqliteStatement: SQLiteStatement
    
    deinit {
        statementRef?.release()
    }
    
    /// Builds a row from the an SQLite statement.
    ///
    /// The row is implemented on top of StatementRowImpl, which grants *direct*
    /// access to the SQLite statement. Iteration of the statement does modify
    /// the row.
    init(statement: SelectStatement) {
        let statementRef = Unmanaged.passRetained(statement) // released in deinit
        self.statementRef = statementRef
        self.sqliteStatement = statement.sqliteStatement
        self.impl = StatementRowImpl(sqliteStatement: statement.sqliteStatement, statementRef: statementRef)
    }
    
    /// Builds a row from the *current state* of the SQLite statement.
    ///
    /// The row is implemented on top of StatementCopyRowImpl, which *copies*
    /// the values from the SQLite statement so that further iteration of the
    /// statement does not modify the row.
    convenience init(copiedFromSQLiteStatement sqliteStatement: SQLiteStatement, statementRef: Unmanaged<SelectStatement>) {
        self.init(impl: StatementCopyRowImpl(sqliteStatement: sqliteStatement, columnNames: statementRef.takeUnretainedValue().columnNames))
    }
    
    /// Builds a row from the *current state* of the SQLite statement.
    ///
    /// The row is implemented on top of StatementCopyRowImpl, which *copies*
    /// the values from the SQLite statement so that further iteration of the
    /// statement does not modify the row.
    convenience init(copiedFromSQLiteStatement sqliteStatement: SQLiteStatement, columnNames: [String]) {
        self.init(impl: StatementCopyRowImpl(sqliteStatement: sqliteStatement, columnNames: columnNames))
    }
    
    init(impl: RowImpl) {
        self.impl = impl
        self.statementRef = nil
        self.sqliteStatement = nil
    }
}

extension Row {

    // MARK: - Columns
    
    /// The names of columns in the row.
    ///
    /// Columns appear in the same order as they occur as the `.0` member
    /// of column-value pairs in `self`.
    public var columnNames: LazyMapCollection<Row, String> {
        return lazy.map { $0.0 }
    }
    
    /// Returns true if and only if the row has that column.
    ///
    /// This method is case-insensitive.
    public func hasColumn(columnName: String) -> Bool {
        return impl.indexOfColumn(named: columnName) != nil
    }
}

extension Row {
    
    // MARK: - Extracting Values
    
    /// Returns Int64, Double, String, NSData or nil, depending on the value
    /// stored at the given index.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    @warn_unused_result
    public func value(atIndex index: Int) -> DatabaseValueConvertible? {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given index, converted to the requested type.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    ///
    /// If the SQLite value is NULL, the result is nil. Otherwise the SQLite
    /// value is converted to the requested type `Value`. Should this conversion
    /// fail, a fatal error is raised.
    @warn_unused_result
    public func value<Value: DatabaseValueConvertible>(atIndex index: Int) -> Value? {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given index, converted to the requested type.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    ///
    /// If the SQLite value is NULL, the result is nil. Otherwise the SQLite
    /// value is converted to the requested type `Value`. Should this conversion
    /// fail, a fatal error is raised.
    ///
    /// This method exists as an optimization opportunity for types that adopt
    /// StatementColumnConvertible. It *may* trigger SQLite built-in conversions
    /// (see https://www.sqlite.org/datatype3.html).
    @warn_unused_result
    public func value<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(atIndex index: Int) -> Value? {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return fastValue(atUncheckedIndex: index)
    }
    
    /// Returns the value at given index, converted to the requested type.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    ///
    /// This method crashes if the fetched SQLite value is NULL, or if the
    /// SQLite value can not be converted to `Value`.
    @warn_unused_result
    public func value<Value: DatabaseValueConvertible>(atIndex index: Int) -> Value {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given index, converted to the requested type.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    ///
    /// This method crashes if the fetched SQLite value is NULL, or if the
    /// SQLite value can not be converted to `Value`.
    ///
    /// This method exists as an optimization opportunity for types that adopt
    /// StatementColumnConvertible. It *may* trigger SQLite built-in conversions
    /// (see https://www.sqlite.org/datatype3.html).
    @warn_unused_result
    public func value<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(atIndex index: Int) -> Value {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return fastValue(atUncheckedIndex: index)
    }
    
    /// Returns Int64, Double, String, NSData or nil, depending on the value
    /// stored at the given column.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// The result is nil if the row does not contain the column.
    @warn_unused_result
    public func value(named columnName: String) -> DatabaseValueConvertible? {
        // IMPLEMENTATION NOTE
        // This method has a single know use case: checking if the value is nil,
        // as in:
        //
        //     if row.value(named: "foo") != nil { ... }
        //
        // Without this method, the code above would not compile.
        guard let index = impl.indexOfColumn(named: columnName) else {
            return nil
        }
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given column, converted to the requested type.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// If the column is missing or if the SQLite value is NULL, the result is
    /// nil. Otherwise the SQLite value is converted to the requested type
    /// `Value`. Should this conversion fail, a fatal error is raised.
    @warn_unused_result
    public func value<Value: DatabaseValueConvertible>(named columnName: String) -> Value? {
        guard let index = impl.indexOfColumn(named: columnName) else {
            return nil
        }
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given column, converted to the requested type.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// If the column is missing or if the SQLite value is NULL, the result is
    /// nil. Otherwise the SQLite value is converted to the requested type
    /// `Value`. Should this conversion fail, a fatal error is raised.
    ///
    /// This method exists as an optimization opportunity for types that adopt
    /// StatementColumnConvertible. It *may* trigger SQLite built-in conversions
    /// (see https://www.sqlite.org/datatype3.html).
    @warn_unused_result
    public func value<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(named columnName: String) -> Value? {
        guard let index = impl.indexOfColumn(named: columnName) else {
            return nil
        }
        return fastValue(atUncheckedIndex: index)
    }
    
    /// Returns the value at given column, converted to the requested type.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// If the row does not contain the column, a fatal error is raised.
    ///
    /// This method crashes if the fetched SQLite value is NULL, or if the
    /// SQLite value can not be converted to `Value`.
    @warn_unused_result
    public func value<Value: DatabaseValueConvertible>(named columnName: String) -> Value {
        guard let index = impl.indexOfColumn(named: columnName) else {
            fatalError("no such column: \(columnName)")
        }
        return impl.databaseValue(atIndex: index).value()
    }
    
    /// Returns the value at given column, converted to the requested type.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// If the row does not contain the column, a fatal error is raised.
    ///
    /// This method crashes if the fetched SQLite value is NULL, or if the
    /// SQLite value can not be converted to `Value`.
    ///
    /// This method exists as an optimization opportunity for types that adopt
    /// StatementColumnConvertible. It *may* trigger SQLite built-in conversions
    /// (see https://www.sqlite.org/datatype3.html).
    @warn_unused_result
    public func value<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(named columnName: String) -> Value {
        guard let index = impl.indexOfColumn(named: columnName) else {
            fatalError("no such column: \(columnName)")
        }
        return fastValue(atUncheckedIndex: index)
    }
    
    /// Returns the optional `NSData` at given index.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    ///
    /// If the SQLite value is NULL, the result is nil. If the SQLite value can
    /// not be converted to NSData, a fatal error is raised.
    ///
    /// The returned data does not owns its bytes: it must not be used longer
    /// than the row's lifetime.
    @warn_unused_result
    public func dataNoCopy(atIndex index: Int) -> NSData? {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return impl.dataNoCopy(atIndex: index)
    }
    
    /// Returns the optional `NSData` at given column.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// If the column is missing or if the SQLite value is NULL, the result is
    /// nil. If the SQLite value can not be converted to NSData, a fatal error
    /// is raised.
    ///
    /// The returned data does not owns its bytes: it must not be used longer
    /// than the row's lifetime.
    @warn_unused_result
    public func dataNoCopy(named columnName: String) -> NSData? {
        guard let index = impl.indexOfColumn(named: columnName) else {
            return nil
        }
        return impl.dataNoCopy(atIndex: index)
    }
}

extension Row {
    
    // MARK: - Extracting DatabaseValue
    
    /// The database values in the row.
    ///
    /// Values appear in the same order as they occur as the `.1` member
    /// of column-value pairs in `self`.
    public var databaseValues: LazyMapCollection<Row, DatabaseValue> {
        return lazy.map { $0.1 }
    }
    
    /// Returns the `DatabaseValue` at given index.
    ///
    /// Indexes span from 0 for the leftmost column to (row.count - 1) for the
    /// righmost column.
    @warn_unused_result
    public func databaseValue(atIndex index: Int) -> DatabaseValue {
        GRDBPrecondition(index >= 0 && index < count, "row index out of range")
        return impl.databaseValue(atIndex: index)
    }
    
    /// Returns the `DatabaseValue` at given column.
    ///
    /// Column name lookup is case-insensitive, and when several columns have
    /// the same name, the leftmost column is considered.
    ///
    /// The result is nil if the row does not contain the column.
    @warn_unused_result
    public func databaseValue(named columnName: String) -> DatabaseValue? {
        guard let index = impl.indexOfColumn(named: columnName) else {
            return nil
        }
        return impl.databaseValue(atIndex: index)
    }
}

extension Row {
    
    // MARK: - Helpers
    
    @warn_unused_result
    private func fastValue<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(atUncheckedIndex index: Int) -> Value? {
        let sqliteStatement = self.sqliteStatement
        guard sqliteStatement != nil else {
            return impl.databaseValue(atIndex: index).value()
        }
        guard sqlite3_column_type(sqliteStatement, Int32(index)) != SQLITE_NULL else {
            return nil
        }
        return Value.init(sqliteStatement: sqliteStatement, index: Int32(index))
    }
    
    @warn_unused_result
    private func fastValue<Value: protocol<DatabaseValueConvertible, StatementColumnConvertible>>(atUncheckedIndex index: Int) -> Value {
        let sqliteStatement = self.sqliteStatement
        guard sqliteStatement != nil else {
            return impl.databaseValue(atIndex: index).value()
        }
        guard sqlite3_column_type(sqliteStatement, Int32(index)) != SQLITE_NULL else {
            fatalError("could not convert NULL to \(Value.self).")
        }
        return Value.init(sqliteStatement: sqliteStatement, index: Int32(index))
    }
}

extension Row {
    
    // MARK: - Variants
    
    public func variant(named name: String) -> Row? {
        return impl.variant(named: name)
    }
}

extension Row {
    
    // MARK: - Fetching From SelectStatement
    
    /// Returns a sequence of rows fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT ...")
    ///     for row in Row.fetch(statement) {
    ///         let id: Int64 = row.value(atIndex: 0)
    ///         let name: String = row.value(atIndex: 1)
    ///     }
    ///
    /// Fetched rows are reused during the sequence iteration: don't wrap a row
    /// sequence in an array with `Array(rows)` or `rows.filter { ... }` since
    /// you would not get the distinct rows you expect. Use `Row.fetchAll(...)`
    /// instead.
    ///
    /// For the same reason, make sure you make a copy whenever you extract a
    /// row for later use: `row.copy()`.
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let rows = Row.fetch(statement)
    ///     for row in rows { ... } // 3 steps
    ///     db.execute("DELETE ...")
    ///     for row in rows { ... } // 2 steps
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements of the sequence are undefined.
    ///
    /// - parameters:
    ///     - db: A Database.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence of rows.
    @warn_unused_result
    public static func fetch(statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Row> {
        // Metal rows can be reused. And reusing them yields better performance.
        let row = try! Row(statement: statement).adaptedRow(adapter: adapter, statement: statement)
        return statement.fetchSequence(arguments: arguments) {
            return row
        }
    }
    
    /// Returns an array of rows fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT ...")
    ///     let rows = Row.fetchAll(statement)
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of rows.
    @warn_unused_result
    public static func fetchAll(statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Row] {
        let sqliteStatement = statement.sqliteStatement
        let columnNames = statement.columnNames
        let sequence: DatabaseSequence<Row>
        if let adapter = adapter {
            let adapterBinding = try! adapter.binding(with: statement)
            sequence = statement.fetchSequence(arguments: arguments) {
                Row(baseRow: Row(copiedFromSQLiteStatement: sqliteStatement, columnNames: columnNames), adapterBinding: adapterBinding)
            }
        } else {
            sequence = statement.fetchSequence(arguments: arguments) {
                Row(copiedFromSQLiteStatement: sqliteStatement, columnNames: columnNames)
            }
        }
        return Array(sequence)
    }
    
    /// Returns a single row fetched from a prepared statement.
    ///
    ///     let statement = db.selectStatement("SELECT ...")
    ///     let row = Row.fetchOne(statement)
    ///
    /// - parameters:
    ///     - statement: The statement to run.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional row.
    @warn_unused_result
    public static func fetchOne(statement: SelectStatement, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> Row? {
        let sqliteStatement = statement.sqliteStatement
        let columnNames = statement.columnNames
        let sequence = statement.fetchSequence(arguments: arguments) {
            Row(copiedFromSQLiteStatement: sqliteStatement, columnNames: columnNames)
        }
        guard let row = sequence.generate().next() else {
            return nil
        }
        return try! row.adaptedRow(adapter: adapter, statement: statement)
    }
}

extension Row {
    
    // MARK: - Fetching From SQL
    
    /// Returns a sequence of rows fetched from an SQL query.
    ///
    ///     for row in Row.fetch(db, "SELECT id, name FROM persons") {
    ///         let id: Int64 = row.value(atIndex: 0)
    ///         let name: String = row.value(atIndex: 1)
    ///     }
    ///
    /// Fetched rows are reused during the sequence iteration: don't wrap a row
    /// sequence in an array with `Array(rows)` or `rows.filter { ... }` since
    /// you would not get the distinct rows you expect. Use `Row.fetchAll(...)`
    /// instead.
    ///
    /// For the same reason, make sure you make a copy whenever you extract a
    /// row for later use: `row.copy()`.
    ///
    /// The returned sequence can be consumed several times, but it may yield
    /// different results, should database changes have occurred between two
    /// generations:
    ///
    ///     let rows = Row.fetch(db, "SELECT...")
    ///     for row in rows { ... } // 3 steps
    ///     db.execute("DELETE ...")
    ///     for row in rows { ... } // 2 steps
    ///
    /// If the database is modified while the sequence is iterating, the
    /// remaining elements of the sequence are undefined.
    ///
    /// - parameters:
    ///     - db: A Database.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: A sequence of rows.
    @warn_unused_result
    public static func fetch(db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> DatabaseSequence<Row> {
        return fetch(try! db.selectStatement(sql), arguments: arguments, adapter: adapter)
    }
    
    /// Returns an array of rows fetched from an SQL query.
    ///
    ///     let rows = Row.fetchAll(db, "SELECT ...")
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An array of rows.
    @warn_unused_result
    public static func fetchAll(db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> [Row] {
        return fetchAll(try! db.selectStatement(sql), arguments: arguments, adapter: adapter)
    }
    
    /// Returns a single row fetched from an SQL query.
    ///
    ///     let row = Row.fetchOne(db, "SELECT ...")
    ///
    /// - parameters:
    ///     - db: A database connection.
    ///     - sql: An SQL query.
    ///     - arguments: Optional statement arguments.
    ///     - adapter: Optional RowAdapter
    /// - returns: An optional row.
    @warn_unused_result
    public static func fetchOne(db: Database, _ sql: String, arguments: StatementArguments? = nil, adapter: RowAdapter? = nil) -> Row? {
        return fetchOne(try! db.selectStatement(sql), arguments: arguments, adapter: adapter)
    }
}

extension Row : CollectionType {
    
    // MARK: - Row as a Collection of (ColumnName, DatabaseValue) Pairs
    
    /// The number of columns in the row.
    public var count: Int {
        let sqliteStatement = self.sqliteStatement
        guard sqliteStatement != nil else {
            return impl.count
        }
        return Int(sqlite3_column_count(sqliteStatement))
    }
    
    /// Returns a *generator* over (ColumnName, DatabaseValue) pairs, from left
    /// to right.
    public func generate() -> IndexingGenerator<Row> {
        return IndexingGenerator(self)
    }
    
    /// The index of the first (ColumnName, DatabaseValue) pair.
    public var startIndex: RowIndex {
        return Index(0)
    }
    
    /// The "past-the-end" index, successor of the index of the last
    /// (ColumnName, DatabaseValue) pair.
    public var endIndex: RowIndex {
        return Index(impl.count)
    }
    
    /// Returns the (ColumnName, DatabaseValue) pair at given index.
    public subscript(index: RowIndex) -> (String, DatabaseValue) {
        return (
            impl.columnName(atIndex: index.index),
            impl.databaseValue(atIndex: index.index))
    }
}

extension Row : Equatable { }

/// Returns true if and only if both rows have the same columns and values, in
/// the same order. Columns are compared in a case-sensitive way.
public func ==(lhs: Row, rhs: Row) -> Bool {
    if lhs === rhs {
        return true
    }
    
    guard lhs.count == rhs.count else {
        return false
    }
    
    var lgen = lhs.generate()
    var rgen = rhs.generate()
    
    while let (lcol, lval) = lgen.next(), let (rcol, rval) = rgen.next() {
        guard lcol == rcol else {
            return false
        }
        guard lval == rval else {
            return false
        }
    }
    
    let lvariantNames = lhs.impl.variantNames
    let rvariantNames = rhs.impl.variantNames
    guard lvariantNames == rvariantNames else {
        return false
    }
    
    for name in lvariantNames {
        let lvariant = lhs.variant(named: name)
        let rvariant = rhs.variant(named: name)
        guard lvariant == rvariant else {
            return false
        }
    }
    
    return true
}

/// Row adopts CustomStringConvertible.
extension Row: CustomStringConvertible {
    /// A textual representation of `self`.
    public var description: String {
        return "<Row"
            + map { (column, dbv) in
                " \(column):\(dbv)"
                }.joinWithSeparator("")
            + ">"
    }
}


// MARK: - RowIndex

/// Indexes to (columnName, databaseValue) pairs in a database row.
public struct RowIndex: ForwardIndexType, BidirectionalIndexType, RandomAccessIndexType {
    let index: Int
    init(_ index: Int) { self.index = index }
    
    /// The index of the next (ColumnName, DatabaseValue) pair in a row.
    public func successor() -> RowIndex { return RowIndex(index + 1) }

    /// The index of the previous (ColumnName, DatabaseValue) pair in a row.
    public func predecessor() -> RowIndex { return RowIndex(index - 1) }

    /// The number of columns between two (ColumnName, DatabaseValue) pairs in
    /// a row.
    public func distanceTo(other: RowIndex) -> Int { return other.index - index }
    
    /// Return `self` offset by `n` steps.
    public func advancedBy(n: Int) -> RowIndex { return RowIndex(index + n) }
}

/// Equatable implementation for RowIndex
public func ==(lhs: RowIndex, rhs: RowIndex) -> Bool {
    return lhs.index == rhs.index
}


// MARK: - RowImpl

// The protocol for Row underlying implementation
protocol RowImpl {
    var count: Int { get }
    func databaseValue(atIndex index: Int) -> DatabaseValue
    func dataNoCopy(atIndex index:Int) -> NSData?
    func columnName(atIndex index: Int) -> String
    
    // This method MUST be case-insensitive, and returns the index of the
    // leftmost column that matches *name*.
    func indexOfColumn(named name: String) -> Int?
    
    func variant(named name: String) -> Row?
    
    var variantNames: Set<String> { get }
    
    // row.impl is guaranteed to be self.
    func copy(row: Row) -> Row
}


/// See Row.init(dictionary:)
private struct DictionaryRowImpl : RowImpl {
    let dictionary: [String: DatabaseValueConvertible?]
    
    init (dictionary: [String: DatabaseValueConvertible?]) {
        self.dictionary = dictionary
    }
    
    var count: Int {
        return dictionary.count
    }
    
    func dataNoCopy(atIndex index:Int) -> NSData? {
        return databaseValue(atIndex: index).value()
    }
    
    func databaseValue(atIndex index: Int) -> DatabaseValue {
        return dictionary[dictionary.startIndex.advancedBy(index)].1?.databaseValue ?? .Null
    }
    
    func columnName(atIndex index: Int) -> String {
        return dictionary[dictionary.startIndex.advancedBy(index)].0
    }
    
    // This method MUST be case-insensitive, and returns the index of the
    // leftmost column that matches *name*.
    func indexOfColumn(named name: String) -> Int? {
        let lowercaseName = name.lowercaseString
        guard let index = dictionary.indexOf({ (column, value) in column.lowercaseString == lowercaseName }) else {
            return nil
        }
        return dictionary.startIndex.distanceTo(index)
    }
    
    func variant(named name: String) -> Row? {
        return nil
    }
    
    var variantNames: Set<String> {
        return []
    }
    
    func copy(row: Row) -> Row {
        return row
    }
}


/// See Row.init(copiedFromStatementRef:sqliteStatement:)
private struct StatementCopyRowImpl : RowImpl {
    let databaseValues: ContiguousArray<DatabaseValue>
    let columnNames: [String]
    
    init(sqliteStatement: SQLiteStatement, columnNames: [String]) {
        assert(sqliteStatement != nil)
        let sqliteStatement = sqliteStatement
        self.databaseValues = ContiguousArray((0..<sqlite3_column_count(sqliteStatement)).lazy.map { DatabaseValue(sqliteStatement: sqliteStatement, index: $0) })
        self.columnNames = columnNames
    }
    
    var count: Int {
        return columnNames.count
    }
    
    func dataNoCopy(atIndex index:Int) -> NSData? {
        return databaseValue(atIndex: index).value()
    }
    
    func databaseValue(atIndex index: Int) -> DatabaseValue {
        return databaseValues[index]
    }
    
    func columnName(atIndex index: Int) -> String {
        return columnNames[index]
    }
    
    // This method MUST be case-insensitive, and returns the index of the
    // leftmost column that matches *name*.
    func indexOfColumn(named name: String) -> Int? {
        let lowercaseName = name.lowercaseString
        return columnNames.indexOf { $0.lowercaseString == lowercaseName }
    }
    
    func variant(named name: String) -> Row? {
        return nil
    }
    
    var variantNames: Set<String> {
        return []
    }
    
    func copy(row: Row) -> Row {
        return row
    }
}


/// See Row.init(statement:)
private struct StatementRowImpl : RowImpl {
    let statementRef: Unmanaged<SelectStatement>
    let sqliteStatement: SQLiteStatement
    let lowercaseColumnIndexes: [String: Int]
    
    init(sqliteStatement: SQLiteStatement, statementRef: Unmanaged<SelectStatement>) {
        assert(sqliteStatement != nil)
        self.statementRef = statementRef
        self.sqliteStatement = sqliteStatement
        // Optimize row.value(named: "...")
        let lowercaseColumnNames = (0..<sqlite3_column_count(sqliteStatement)).map { String.fromCString(sqlite3_column_name(sqliteStatement, Int32($0)))!.lowercaseString }
        self.lowercaseColumnIndexes = Dictionary(keyValueSequence: lowercaseColumnNames.enumerate().map { ($1, $0) }.reverse())
    }
    
    var count: Int {
        return Int(sqlite3_column_count(sqliteStatement))
    }
    
    func dataNoCopy(atIndex index:Int) -> NSData? {
        guard sqlite3_column_type(sqliteStatement, Int32(index)) != SQLITE_NULL else {
            return nil
        }
        let bytes = sqlite3_column_blob(sqliteStatement, Int32(index))
        let length = sqlite3_column_bytes(sqliteStatement, Int32(index))
        return NSData(bytesNoCopy: UnsafeMutablePointer(bytes), length: Int(length), freeWhenDone: false)
    }
    
    func databaseValue(atIndex index: Int) -> DatabaseValue {
        return DatabaseValue(sqliteStatement: sqliteStatement, index: Int32(index))
    }
    
    func columnName(atIndex index: Int) -> String {
        return statementRef.takeUnretainedValue().columnNames[index]
    }
    
    // This method MUST be case-insensitive, and returns the index of the
    // leftmost column that matches *name*.
    func indexOfColumn(named name: String) -> Int? {
        if let index = lowercaseColumnIndexes[name] {
            return index
        }
        return lowercaseColumnIndexes[name.lowercaseString]
    }
    
    func variant(named name: String) -> Row? {
        return nil
    }
    
    var variantNames: Set<String> {
        return []
    }
    
    func copy(row: Row) -> Row {
        return Row(copiedFromSQLiteStatement: sqliteStatement, statementRef: statementRef)
    }
}


/// See Row.init()
private struct EmptyRowImpl : RowImpl {
    var count: Int { return 0 }
    
    func databaseValue(atIndex index: Int) -> DatabaseValue {
        fatalError("row index out of range")
    }
    
    func dataNoCopy(atIndex index:Int) -> NSData? {
        fatalError("row index out of range")
    }
    
    func columnName(atIndex index: Int) -> String {
        fatalError("row index out of range")
    }
    
    func indexOfColumn(named name: String) -> Int? {
        return nil
    }
    
    func variant(named name: String) -> Row? {
        return nil
    }
    
    var variantNames: Set<String> {
        return []
    }
    
    func copy(row: Row) -> Row {
        return row
    }
}
