import Foundation

public enum PackSource: String, Codable, Sendable { case bundled, installed }
public struct PackLocation: Codable, Hashable, Sendable {
    public var source: PackSource
    public var version: String
    public init(source: PackSource, version: String) { self.source = source; self.version = version }
}
public struct PackState: Equatable, Sendable {
    public var current: PackLocation?
    public var previous: PackLocation?
    public var pins: [UUID: String]
    public init(current: PackLocation? = nil, previous: PackLocation? = nil, pins: [UUID: String] = [:]) {
        self.current = current; self.previous = previous; self.pins = pins
    }
}

extension PackState: Codable {
    private enum CodingKeys: String, CodingKey { case current, previous, pins }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decodeIfPresent(PackLocation.self, forKey: .current)
        previous = try container.decodeIfPresent(PackLocation.self, forKey: .previous)
        let rawPins = try container.decode([String: String].self, forKey: .pins)
        var pins: [UUID: String] = [:]
        for (id, version) in rawPins {
            guard let uuid = UUID(uuidString: id) else {
                throw DecodingError.dataCorruptedError(forKey: .pins, in: container, debugDescription: "invalid attempt UUID")
            }
            pins[uuid] = version
        }
        self.pins = pins
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(current, forKey: .current)
        try container.encode(previous, forKey: .previous)
        try container.encode(Dictionary(uniqueKeysWithValues: pins.map { ($0.key.uuidString, $0.value) }), forKey: .pins)
    }
}
