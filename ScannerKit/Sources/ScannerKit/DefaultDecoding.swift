import Foundation

extension KeyedDecodingContainer {
    /// The value for the key, or this one when the key is missing, as in settings saved before it existed; a value that cannot be read still throws.
    func decode<T: Decodable>(_ key: Key, or value: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? value
    }
}
