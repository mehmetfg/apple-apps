// One bus event: one line of JSON in `_bus/events/<app>/<device>.jsonl`.
// Format: `_bus/README.md` §4 (v, id, ts, app, device, type, subject, data).
import Foundation

/// A small JSON value for the `data` object of an event.
public enum PDMValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([PDMValue])
    case object([String: PDMValue])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([PDMValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: PDMValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

extension PDMValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByFloatLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .int(v) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(floatLiteral v: Double) { self = .double(v) }
}

public struct PDMEvent: Codable, Hashable, Sendable {
    public var v: Int = 1
    public var id: String
    public var ts: String
    public var app: String
    public var device: String
    public var type: String
    public var subject: String?
    public var data: [String: PDMValue]

    public init(app: String, device: String, type: String, subject: String? = nil,
                data: [String: PDMValue] = [:], date: Date = Date(), id: String = UUID().uuidString) {
        self.id = id
        self.ts = PDMEvent.timestamp(date)
        self.app = app
        self.device = device
        self.type = type
        self.subject = subject
        self.data = data
    }

    /// ISO 8601 in UTC, seconds precision: `2026-10-15T14:30:00Z`.
    /// An app id is a folder name under `_bus/events/`: lower-case letters, digits and "-".
    public static func isSafeApp(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 40 && id.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    }

    public static func timestamp(_ d: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: d)
    }

    /// The event as one JSON line, with the newline.
    public func jsonLine() -> Data? {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard var d = try? e.encode(self) else { return nil }
        d.append(0x0A)
        return d
    }
}

/// Subject helpers: `<kind>:<id>`. Words are lower case, like the hub.
public enum PDMSubject {
    public static func word(_ w: String) -> String {
        "word:" + w.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    public static func grammar(_ id: String) -> String { "grammar:" + id }
    public static func lesson(_ id: String) -> String { "lesson:" + id }
    public static func term(_ id: String) -> String { "term:" + id }
    public static func app(_ id: String) -> String { "app:" + id }
}
