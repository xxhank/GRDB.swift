import XCTest
#if SQLITE_HAS_CODEC
    import GRDBCipher
#else
    import GRDB
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
            let request = parentTable.join(association)
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
                
                let variant = row.variant(named: association.name)!
                XCTAssertEqual(Array(variant.columnNames), ["id", "parentID", "name"])
                
                XCTAssertEqual(variant.databaseValue(atIndex: 0), 100.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 1), 1.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 2), "child1".databaseValue)
                
                XCTAssertEqual(variant.value(named: "id") as Int, 100)
                XCTAssertEqual(variant.value(named: "parentID") as Int, 1)
                XCTAssertEqual(variant.value(named: "name") as String, "child1")
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
                
                let variant = row.variant(named: association.name)!
                XCTAssertEqual(Array(variant.columnNames), ["id", "parentID", "name"])
                
                XCTAssertEqual(variant.databaseValue(atIndex: 0), DatabaseValue.Null)
                XCTAssertEqual(variant.databaseValue(atIndex: 1), DatabaseValue.Null)
                XCTAssertEqual(variant.databaseValue(atIndex: 2), DatabaseValue.Null)
            }
        }
    }
    
    func testRecursiveAssociation() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE persons (id INTEGER PRIMARY KEY, name TEXT, friendID INTEGER REFERENCES persons(id))")
                try db.execute("INSERT INTO persons (id, name, friendID) VALUES (1, 'Arthur', NULL)")
                try db.execute("INSERT INTO persons (id, name, friendID) VALUES (2, 'Barbara', 1)")
            }
            let parentTable = QueryInterfaceRequest<Void>(tableName: "persons")
            let association = HasOneAssociation(name: "friend", childTable: "persons", foreignKey: ["id": "friendID"])
            let request = parentTable.join(association)
            XCTAssertEqual(sql(dbQueue, request), "SELECT \"persons0\".*, \"persons1\".* FROM \"persons\" \"persons0\" LEFT JOIN \"persons\" \"persons1\" ON \"persons1\".\"friendID\" = \"persons0\".\"id\"")
            
            let rows = dbQueue.inDatabase { db in
                Row.fetchAll(db, request)
            }
            XCTAssertEqual(rows.count, 2)
            
            do {
                let row = rows[0]
                XCTAssertEqual(Array(row.columnNames), ["id", "name", "friendID", "id", "name", "friendID"])
                
                XCTAssertEqual(row.databaseValue(atIndex: 0), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 1), "Arthur".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 2), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 3), 2.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 4), "Barbara".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 5), 1.databaseValue)
                
                XCTAssertEqual(row.value(named: "id") as Int, 1)
                XCTAssertEqual(row.value(named: "name") as String, "Arthur")
                XCTAssertTrue(row.value(named: "friendID") == nil)
                
                let variant = row.variant(named: association.name)!
                XCTAssertEqual(Array(variant.columnNames), ["id", "name", "friendID"])
                
                XCTAssertEqual(variant.databaseValue(atIndex: 0), 2.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 1), "Barbara".databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 2), 1.databaseValue)
                
                XCTAssertEqual(variant.value(named: "id") as Int, 2)
                XCTAssertEqual(variant.value(named: "name") as String, "Barbara")
                XCTAssertEqual(variant.value(named: "friendID") as Int, 1)
            }
            
            do {
                let row = rows[1]
                XCTAssertEqual(Array(row.columnNames), ["id", "name", "friendID", "id", "name", "friendID"])
                
                XCTAssertEqual(row.databaseValue(atIndex: 0), 2.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 1), "Barbara".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 2), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 3), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 4), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 5), DatabaseValue.Null)
                
                XCTAssertEqual(row.value(named: "id") as Int, 2)
                XCTAssertEqual(row.value(named: "name") as String, "Barbara")
                XCTAssertEqual(row.value(named: "friendID") as Int, 1)
                
                let variant = row.variant(named: association.name)!
                XCTAssertEqual(Array(variant.columnNames), ["id", "name", "friendID"])
                
                XCTAssertEqual(variant.databaseValue(atIndex: 0), DatabaseValue.Null)
                XCTAssertEqual(variant.databaseValue(atIndex: 1), DatabaseValue.Null)
                XCTAssertEqual(variant.databaseValue(atIndex: 2), DatabaseValue.Null)
            }
        }
    }
    
    func testNestedRecursiveAssociation() {
        assertNoError {
            let dbQueue = try makeDatabaseQueue()
            try dbQueue.inDatabase { db in
                try db.execute("CREATE TABLE persons (id INTEGER PRIMARY KEY, name TEXT, friendID INTEGER REFERENCES persons(id))")
                try db.execute("INSERT INTO persons (id, name, friendID) VALUES (1, 'Arthur', NULL)")
                try db.execute("INSERT INTO persons (id, name, friendID) VALUES (2, 'Barbara', 1)")
                try db.execute("INSERT INTO persons (id, name, friendID) VALUES (3, 'Craig', 2)")
            }
            let parentTable = QueryInterfaceRequest<Void>(tableName: "persons")
            let association = HasOneAssociation(name: "friend", childTable: "persons", foreignKey: ["id": "friendID"])
            let request = parentTable.join(association.join(association))
            XCTAssertEqual(sql(dbQueue, request), "SELECT \"persons0\".*, \"persons1\".*, \"persons2\".* FROM \"persons\" \"persons0\" LEFT JOIN \"persons\" \"persons1\" ON \"persons1\".\"friendID\" = \"persons0\".\"id\" LEFT JOIN \"persons\" \"persons2\" ON \"persons2\".\"friendID\" = \"persons1\".\"id\"")
            
            let rows = dbQueue.inDatabase { db in
                Row.fetchAll(db, request)
            }
            XCTAssertEqual(rows.count, 3)
            
            do {
                let row = rows[0]
                XCTAssertEqual(Array(row.columnNames), ["id", "name", "friendID", "id", "name", "friendID", "id", "name", "friendID"])
                
                XCTAssertEqual(row.databaseValue(atIndex: 0), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 1), "Arthur".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 2), DatabaseValue.Null)
                XCTAssertEqual(row.databaseValue(atIndex: 3), 2.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 4), "Barbara".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 5), 1.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 6), 3.databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 7), "Craig".databaseValue)
                XCTAssertEqual(row.databaseValue(atIndex: 8), 2.databaseValue)
                
                XCTAssertEqual(row.value(named: "id") as Int, 1)
                XCTAssertEqual(row.value(named: "name") as String, "Arthur")
                XCTAssertTrue(row.value(named: "friendID") == nil)
                
                let variant = row.variant(named: association.name)!
                XCTAssertEqual(Array(variant.columnNames), ["id", "name", "friendID", "id", "name", "friendID"])
                
                XCTAssertEqual(variant.databaseValue(atIndex: 0), 2.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 1), "Barbara".databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 2), 1.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 3), 3.databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 4), "Craig".databaseValue)
                XCTAssertEqual(variant.databaseValue(atIndex: 5), 2.databaseValue)
                
                XCTAssertEqual(variant.value(named: "id") as Int, 2)
                XCTAssertEqual(variant.value(named: "name") as String, "Barbara")
                XCTAssertEqual(variant.value(named: "friendID") as Int, 1)
                
                let subvariant = variant.variant(named: association.name)!
                XCTAssertEqual(Array(subvariant.columnNames), ["id", "name", "friendID"])
                
                XCTAssertEqual(subvariant.databaseValue(atIndex: 0), 3.databaseValue)
                XCTAssertEqual(subvariant.databaseValue(atIndex: 1), "Craig".databaseValue)
                XCTAssertEqual(subvariant.databaseValue(atIndex: 2), 2.databaseValue)
                
                XCTAssertEqual(subvariant.value(named: "id") as Int, 3)
                XCTAssertEqual(subvariant.value(named: "name") as String, "Craig")
                XCTAssertEqual(subvariant.value(named: "friendID") as Int, 2)
            }
        }
    }
}
