import Foundation

// MARK: - Shared Date Formatters

/// Shared date formatters used across all model decoders.
/// Stored as top-level constants to avoid repeated allocations.
let iso8601Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

let iso8601WithMillisFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

let simpleDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

// MARK: - Free Decoding Helpers

/// Decodes a Date value resilently from a keyed container.
///
/// Tries each strategy in order:
/// 1. Native `Date` (JSONDecoder date strategy)
/// 2. ISO 8601 string with timezone (`yyyy-MM-dd'T'HH:mm:ssZ`)
/// 3. ISO 8601 string with milliseconds (`yyyy-MM-dd'T'HH:mm:ss.SSSZ`)
/// 4. Simple date string (`yyyy-MM-dd`)
/// 5. Unix timestamp as `Double`
///
/// Returns `nil` if the key is missing or no strategy succeeds.
func decodeDateResiliently<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> Date? {
    // Try native Date first (handles JSONDecoder's configured strategy)
    if let date = try? container.decode(Date.self, forKey: key) {
        return date
    }

    // Try string-based formats
    if let rawString = try? container.decode(String.self, forKey: key) {
        if let date = iso8601Formatter.date(from: rawString) {
            return date
        }
        if let date = iso8601WithMillisFormatter.date(from: rawString) {
            return date
        }
        if let date = simpleDateFormatter.date(from: rawString) {
            return date
        }
    }

    // Try Unix timestamp
    if let timestamp = try? container.decode(Double.self, forKey: key) {
        return Date(timeIntervalSince1970: timestamp)
    }

    return nil
}

/// Decodes a `Bool` value resiliently, accepting both `Bool` and `String` ("true"/"false").
///
/// Returns `nil` if the key is missing.
func decodeFlexibleBool<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> Bool? {
    if let boolValue = try? container.decode(Bool.self, forKey: key) {
        return boolValue
    }
    if let stringValue = try? container.decode(String.self, forKey: key) {
        switch stringValue.lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }
    return nil
}

/// Decodes an `Int` value resiliently, accepting both `Int` and `String` representations.
///
/// Returns `nil` if the key is missing or the string cannot be converted.
func decodeFlexibleInt<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> Int? {
    if let intValue = try? container.decode(Int.self, forKey: key) {
        return intValue
    }
    if let stringValue = try? container.decode(String.self, forKey: key) {
        return Int(stringValue)
    }
    return nil
}

/// Decodes a `String` value resiliently, accepting `String`, `Int`, or `UUID` representations.
///
/// Returns `nil` if the key is missing or no conversion succeeds.
func decodeFlexibleString<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> String? {
    if let stringValue = try? container.decode(String.self, forKey: key) {
        return stringValue
    }
    if let intValue = try? container.decode(Int.self, forKey: key) {
        return String(intValue)
    }
    if let uuidValue = try? container.decode(UUID.self, forKey: key) {
        return uuidValue.uuidString
    }
    return nil
}

/// Decodes an ID string, trying a primary key first, then falling back to alternative keys.
///
/// Tries each key in order until one succeeds. Accepts String, Int, or UUID values.
/// Returns an empty string if no key is found.
func decodeResilientID<K: CodingKey>(
    from container: KeyedDecodingContainer<K>,
    primaryKey: K,
    fallbackKeys: [K] = []
) -> String {
    if let value = decodeFlexibleString(from: container, forKey: primaryKey) {
        return value
    }
    for key in fallbackKeys {
        if let value = decodeFlexibleString(from: container, forKey: key) {
            return value
        }
    }
    return ""
}

// MARK: - Comment Resilient Decoding

/// Decodes an array of `Decodable` elements, skipping any elements that fail to decode.
///
/// This prevents a single malformed comment from causing the entire task to fail parsing.
func decodeResiliently<T: Decodable, K: CodingKey>(
    _ type: T.Type,
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> [T]? {
    guard var unkeyedContainer = try? container.nestedUnkeyedContainer(forKey: key) else {
        return nil
    }

    var results: [T] = []
    while !unkeyedContainer.isAtEnd {
        if let element = try? unkeyedContainer.decode(T.self) {
            results.append(element)
        } else {
            // Skip malformed element by advancing past it
            _ = try? unkeyedContainer.decode(AnyCodableSkip.self)
        }
    }
    return results
}

// MARK: - Private Helpers

/// A type used to skip over undecodable elements in an unkeyed container.
private struct AnyCodableSkip: Decodable {
    // Intentionally empty — decodes any JSON value and discards it
}
