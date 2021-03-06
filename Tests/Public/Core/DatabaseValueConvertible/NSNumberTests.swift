import XCTest
#if USING_SQLCIPHER
    import GRDBCipher
#elseif USING_CUSTOMSQLITE
    import GRDBCustomSQLite
#else
    import GRDB
#endif

class NSNumberTests: GRDBTestCase {
    
    func testNSNumberDatabaseValueToSwiftType() {
        // case "c":
        let number_char = NSNumber(char: Int8.min + 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_char), Int64(Int8.min + 1))
        // case "C":
        let number_unsignedChar = NSNumber(unsignedChar: UInt8.max - 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_unsignedChar), Int64(UInt8.max - 1))
        // case "s":
        let number_short = NSNumber(short: Int16.min + 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_short), Int64(Int16.min + 1))
        // case "S":
        let number_unsignedShort = NSNumber(unsignedShort: UInt16.max - 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_unsignedShort), Int64(UInt16.max - 1))
        // case "i":
        let number_int = NSNumber(int: Int32.min + 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_int), Int64(Int32.min + 1))
        // case "I":
        let number_unsignedInt = NSNumber(unsignedInt: UInt32.max - 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_unsignedInt), Int64(UInt32.max - 1))
        // case "l":
        let number_long = NSNumber(long: Int.min + 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_long), Int64(Int.min + 1))
        // case "L":
        // TODO: Fails with fatalError:
        //let number_unsignedLong = NSNumber(unsignedLong: UInt.max - 1).databaseValue
        //XCTAssertEqual(Int64.fromDatabaseValue(number_unsignedLong), Int64(UInt.max - 1))
        // case "q":
        let number_longLong = NSNumber(longLong: Int64.min + 1).databaseValue
        XCTAssertEqual(Int64.fromDatabaseValue(number_longLong), Int64(Int64.min + 1))
        // case "Q":
        // TODO: Fails with fatalError:
        //let number_unsignedLongLong = NSNumber(unsignedLongLong: UInt64.max - 1).databaseValue
        //XCTAssertEqual(Int64.fromDatabaseValue(number_unsignedLongLong), Int64(UInt64.max - 1))
        // case "f":
        let number_float = NSNumber(float: Float(3.14159)).databaseValue
        XCTAssertEqual(Float.fromDatabaseValue(number_float), Float(3.14159))
        // case "d":
        let number_double = NSNumber(double: Double(10000000.01)).databaseValue
        XCTAssertEqual(Double.fromDatabaseValue(number_double), Double(10000000.01))
        // case "B":
        let number_bool_true = NSNumber(bool: true).databaseValue
        XCTAssertEqual(Bool.fromDatabaseValue(number_bool_true), true)
        let number_bool_false = NSNumber(bool: false).databaseValue
        XCTAssertEqual(Bool.fromDatabaseValue(number_bool_false), false)
    }
    
    func testNSNumberDatabaseValueRoundTrip() {
        
        func roundTrip(value: NSNumber) -> Bool
        {
            let databaseValue = value.databaseValue
            guard let back = NSNumber.fromDatabaseValue(databaseValue) else
            {
                XCTFail("Failed to convert from DatabaseValue to NSNumber")
                return false
            }
            return back.isEqualToNumber(value)
        }
        
        XCTAssertTrue(roundTrip(NSNumber(int: Int32.min + 1)))
        XCTAssertTrue(roundTrip(NSNumber(double: Double(10000000.01))))
    }
    
    func testNSNumberFromDatabaseValueFailure() {
        let databaseValue_Null = DatabaseValue.Null
        let databaseValue_String = "foo".databaseValue
        let databaseValue_Blob = "bar".dataUsingEncoding(NSUTF8StringEncoding)!.databaseValue
        XCTAssertNil(NSNumber.fromDatabaseValue(databaseValue_Null))
        XCTAssertNil(NSNumber.fromDatabaseValue(databaseValue_String))
        XCTAssertNil(NSNumber.fromDatabaseValue(databaseValue_Blob))
    }
    
}
