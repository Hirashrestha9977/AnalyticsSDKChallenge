import XCTest
@testable import AnalyticsKit

final class PropertyValueTests: XCTestCase {
    func test_literals_mapToMatchingCases() {
        let properties: [String: PropertyValue] = ["s": "text", "i": 42, "d": 1.5, "b": true]

        XCTAssertEqual(properties["s"], .string("text"))
        XCTAssertEqual(properties["i"], .int(42))
        XCTAssertEqual(properties["d"], .double(1.5))
        XCTAssertEqual(properties["b"], .bool(true))
    }

    func test_encoding_producesPlainJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let properties: [String: PropertyValue] = ["b": true, "d": 1.5, "i": 42, "s": "text"]

        let json = String(decoding: try encoder.encode(properties), as: UTF8.self)

        XCTAssertEqual(json, #"{"b":true,"d":1.5,"i":42,"s":"text"}"#)
    }

    func test_codable_roundTripsEveryCase() throws {
        let properties: [String: PropertyValue] = ["s": "true", "i": 0, "d": -0.25, "b": false, "digits": "123"]

        let data = try JSONEncoder().encode(properties)

        XCTAssertEqual(try JSONDecoder().decode([String: PropertyValue].self, from: data), properties)
    }

    func test_decoding_unsupportedValue_throws() {
        let data = Data(#"{"nested":{"a":1}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode([String: PropertyValue].self, from: data))
    }
}
