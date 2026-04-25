import Foundation

/// A type-erased wrapper for arbitrary JSON values.
///
/// Used when metadata fields contain values of unknown type. Decoding priority:
/// nil check → Bool → Int → Double → String → Array → Dictionary → null fallback.
enum AnyCodableValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case dictionary([String: AnyCodableValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
            return
        }
        if let boolValue = try? container.decode(Bool.self) {
            self = .bool(boolValue)
            return
        }
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }
        if let doubleValue = try? container.decode(Double.self) {
            self = .double(doubleValue)
            return
        }
        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }
        if let arrayValue = try? container.decode([AnyCodableValue].self) {
            self = .array(arrayValue)
            return
        }
        if let dictValue = try? container.decode([String: AnyCodableValue].self) {
            self = .dictionary(dictValue)
            return
        }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    // MARK: - Computed Accessors

    var stringValue: String? {
        if case .string(let str) = self { return str }
        return nil
    }

    var intValue: Int? {
        if case .int(let num) = self { return num }
        return nil
    }

    var doubleValue: Double? {
        if case .double(let num) = self { return num }
        if case .int(let num) = self { return Double(num) }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let flag) = self { return flag }
        return nil
    }

    var displayString: String {
        switch self {
        case .string(let str): return str
        case .int(let num): return String(num)
        case .double(let num): return String(num)
        case .bool(let flag): return String(flag)
        case .array(let arr): return "[\(arr.count) items]"
        case .dictionary(let dict): return "{\(dict.count) keys}"
        case .null: return "null"
        }
    }
}
