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
    /// 提出後も固定を残している受験（古い順）。pins のキーの部分集合。
    public var retained: [UUID]
    public init(current: PackLocation? = nil, previous: PackLocation? = nil, pins: [UUID: String] = [:], retained: [UUID] = []) {
        self.current = current; self.previous = previous; self.pins = pins; self.retained = retained
    }
}

extension PackState: Codable {
    private enum CodingKeys: String, CodingKey { case current, previous, pins, retained }
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
        // retained 導入前の state.json は欠落を空として読む。
        retained = try container.decodeIfPresent([UUID].self, forKey: .retained) ?? []
    }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(current, forKey: .current)
        try container.encode(previous, forKey: .previous)
        try container.encode(Dictionary(uniqueKeysWithValues: pins.map { ($0.key.uuidString, $0.value) }), forKey: .pins)
        try container.encode(retained, forKey: .retained)
    }
}
