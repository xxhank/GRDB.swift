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
            }
            let parentTable = QueryInterfaceRequest<Void>(tableName: "parents")
            let association = HasOneAssociation(name: "child", childTable: "children", foreignKey: ["id": "parentID"])
            let request = parentTable.include(association)
            print(sql(dbQueue, request))
            XCTAssertEqual(sql(dbQueue, request), "SELECT \"parents\".*, \"child\".* FROM \"parents\" LEFT JOIN \"children\" \"child\" ON \"child\".\"parentID\" = \"parents\".\"id\"")
        }
    }
}
