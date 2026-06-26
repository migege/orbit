import Foundation

/// Three-state value for PATCH request bodies: distinguish *leave unchanged* (omit the key)
/// from *clear* (send an explicit JSON `null`) from *set to a value*. The web detaches an
/// assignment by sending `{assigneeId: null}` and leaves it untouched by omitting the key — a
/// plain Swift `Optional` can't express both, because `encodeIfPresent` drops `nil` and so an
/// explicit null is unreachable. Parent request types own a custom `encode(to:)` that calls
/// `encode(into:forKey:)` for each three-state field.
public enum FieldUpdate<Value: Codable & Sendable & Equatable>: Sendable, Equatable {
    /// Omit the key from the payload (server leaves the field unchanged).
    case keep
    /// Send an explicit JSON `null` (server clears the field).
    case clear
    /// Send the value.
    case set(Value)

    public func encode<K: CodingKey>(into container: inout KeyedEncodingContainer<K>, forKey key: K) throws {
        switch self {
        case .keep: break
        case .clear: try container.encodeNil(forKey: key)
        case .set(let value): try container.encode(value, forKey: key)
        }
    }
}
