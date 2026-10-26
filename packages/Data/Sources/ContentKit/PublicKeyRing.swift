import CryptoKit
import Foundation

public enum PublicKeyRingError: Error, Equatable, Sendable { case invalidKey(String) }

/// 鍵のローテーションのため複数の公開鍵を保持する。秘密鍵は扱わない。
public struct PublicKeyRing: Sendable {
    let keys: [String: Curve25519.Signing.PublicKey]
    public var keyIDs: [String] { keys.keys.sorted() }
    public init(data: Data) throws {
        let encoded = try JSONDecoder().decode([String: String].self, from: data)
        var keys: [String: Curve25519.Signing.PublicKey] = [:]
        for (id, value) in encoded {
            guard !id.isEmpty, let raw = Data(base64Encoded: value), raw.count == 32,
                  raw.base64EncodedString() == value else { throw PublicKeyRingError.invalidKey(id) }
            keys[id] = try Curve25519.Signing.PublicKey(rawRepresentation: raw)
        }
        self.keys = keys
    }
}
