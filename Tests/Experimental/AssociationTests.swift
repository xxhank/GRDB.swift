import XCTest
#if SQLITE_HAS_CODEC
    import GRDBCipher
#else
    import GRDB
#endif

struct HasOneAssociation {
    let parentTable: String
    let childTable: String
    let foreignKey: Set<String>
    
    init(parentTable: String, childTable: String, foreignKey: Set<String>) {
        self.parentTable = parentTable
        self.childTable = childTable
        self.foreignKey = foreignKey
    }
}

class AssociationTests: GRDBTestCase {
}
