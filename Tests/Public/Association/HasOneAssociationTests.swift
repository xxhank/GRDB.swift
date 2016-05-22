import XCTest
#if SQLITE_HAS_CODEC
    @testable import GRDBCipher // @testable so that we have access to SQLiteConnectionWillClose
#else
    @testable import GRDB       // @testable so that we have access to SQLiteConnectionWillClose
#endif

class HasOneAssociationTests: GRDBTestCase {

    func testAssociation() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE parents (id INTEGER PRIMARY KEY, name TEXT)")
                try db.execute("CREATE TABLE children (id INTEGER PRIMARY KEY, parentID REFERENCES parents(id), name TEXT)")
                try db.execute("INSERT INTO parents (id, name) VALUES (1, 'parent1')")
                try db.execute("INSERT INTO parents (id, name) VALUES (2, 'parent2')")
                try db.execute("INSERT INTO children (id, parentID, name) VALUES (100, 1, 'child1')")
            }
            let parentTable = QueryInterfaceRequest<Void>(tableName: "parents")
            let association = HasOneAssociation(name: "child", childTable: "children", foreignKey: ["id": "parentID"])
            let request = parentTable.include(association)
            print(sql(dbQueue, request))
            XCTAssertEqual(sql(dbQueue, request), "SELECT \"parents\".*, \"children\".* FROM \"parents\" LEFT JOIN \"children\" ON \"children\".\"parentID\" = \"parents\".\"id\"")
            
            let rows = dbQueue.inDatabase { db in
                Row.fetchAll(db, request)
            }
            XCTAssertEqual(rows.count, 2)
            
            do {
                let row = rows[0]
                XCTAssertEqual(Array(row.columnNames), ["id", "name", "id", "parentID", "name"])
                
                XCTAssertEqual(row.databaseValue(atIndex: 0), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 1), "parent1".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 2), 100.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 3), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 4), "child1".databaseValue)
                
                XCTAssertEqual(row.value(named: "id") as Int, 1)
                XCTAssertEqual(row.value(named: "name") as String, "parent1")
                
                let subrow = row.subrow(named: association.name)!
                XCTAssertEqual(Array(subrow.columnNames), ["id", "parentID", "name"])
                
                XCTAssertEqual(subrow.databaseValue(atIndex: 0), 100.databaseValue)
                XCTAssertEqual(subrow.databaseValue(atIndex: 1), 1.databaseValue)
                XCTAssertEqual(subrow.databaseValue(atIndex: 2), "child1".databaseValue)
                
                XCTAssertEqual(subrow.value(named: "id") as Int, 100)
                XCTAssertEqual(subrow.value(named: "parentID") as Int, 1)
                XCTAssertEqual(subrow.value(named: "name") as String, "child1")
            }
            
            do {
                let row = rows[1]
                XCTAssertEqual(Array(row.columnNames), ["id", "name", "id", "parentID", "name"])
                
                XCTAssertEqual(row.databaseValue(atIndex: 0), 2.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 1), "parent2".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 2), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 3), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 4), DatabaseValue.Null)
                
                XCTAssertEqual(row.value(named: "id") as Int, 2)
                XCTAssertEqual(row.value(named: "name") as String, "parent2")
                
                let subrow = row.subrow(named: association.name)!
                XCTAssertEqual(Array(subrow.columnNames), ["id", "parentID", "name"])
                
                XCTAssertEqual(subrow.databaseValue(atIndex: 0), DatabaseValue.Null)
                XCTAssertEqual(subrow.databaseValue(atIndex: 1), DatabaseValue.Null)
                XCTAssertEqual(subrow.databaseValue(atIndex: 2), DatabaseValue.Null)
            }
        }
    }
}
