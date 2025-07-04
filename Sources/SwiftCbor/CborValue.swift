import Foundation

public enum CborValueLiteralType {
    case `nil`
    case `break`
    case bool(Bool)
    case int(Data, any FixedWidthInteger.Type)
    case uint(Data, any FixedWidthInteger.Type)
    case float16(Data)
    case float32(Data)
    case float64(Data)
    case str(Data)
    case bin(Data)
}

extension CborValueLiteralType {
    var debugDataTypeDescription: String {
        switch self {
            case .nil:
                "nil"
            case .break:
                "break"
            case .bool:
                "bool"
            case let .int(_, type):
                String(describing: type).lowercased()
            case let .uint(_, type):
                String(describing: type).lowercased()
            case .float16:
                "float16"
            case .float32:
                "float32"
            case .float64:
                "float64"
            case .str:
                "str"
            case .bin:
                "bin"
        }
    }
}

indirect enum CborEncodedValue {
    case none
    case literal([UInt8])
    case array([CborEncodedValue])
    case map([CborEncodedValue])
    case tagged(tag: CborEncodedValue, value: CborEncodedValue)

    static let Nil = literal([0xF6])

    var debugDataTypeDescription: String {
        switch self {
            case .none: "nil"
            case .literal: "literal"
            case .array: "array"
            case .map: "map"
            case .tagged: "tagged"
        }
    }
}

extension CborEncodedValue {
    func asMap() -> CborEncodedValue {
        switch self {
            case .none, .literal, .tagged:
                return .map([])
            case let .array(a):
                if a.count % 2 != 0 {
                    return .map([])
                }
                return .map(a)
            case .map:
                return self
        }
    }
}

struct CborStringKey {
    let stringValue: String
    let CborValue: CborEncodedValue
}

public indirect enum CborValue {
    case none
    case literal(CborValueLiteralType)
    case array([CborValue])
    case map([CborValue])
    case tagged(tag: CborValueLiteralType, value: CborValue)

    static let `break`: CborValue = .literal(.break)
}

extension CborValue {
    func asArray() -> [CborValue] {
        switch self {
            case .none:
                []
            case .literal, .tagged:
                [self]
            case let .array(a), let .map(a):
                a
        }
    }

    func asDictionary() throws -> [(CborValue, CborValue)] {
        let elements: [CborValue]
        switch self {
            case .map(let m): elements = m
            case .array(let a): elements = a
            default: return []
        }

        if elements.count % 2 != 0 { return [] }
        var seenKeys = Set<Data>()
        var result: [(CborValue, CborValue)] = []
        let writer = CborValue.Writer()
        for i in stride(from: 0, to: elements.count, by: 2) {
            let key = elements[i]
            let value = elements[i + 1]
            let keyEncoded = writer.writeValue(key.toEncodedValue())
            guard seenKeys.insert(Data(keyEncoded)).inserted else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Duplicate map key in DAG-CBOR"))
            }
            result.append((key, value))
        }
        return result
    }

    private func toEncodedValue() -> CborEncodedValue {
        switch self {
            case .none:
                return .none
            case .literal(let lit):
                switch lit {
                    case .nil: return .literal([0xF6])
                    case .bool(let b): return .literal([b ? 0xF5 : 0xF4])
                    case .str(let data):
                        let length = data.count
                        if length <= Int.fixMax {
                            return .literal([UInt8(0x60 + length)] + data)
                        } else {
                            return .literal([0x78, UInt8(length)] + data)
                        }
                    case .bin(let data):
                        let length = data.count
                        if length <= Int.fixMax {
                            return .literal([UInt8(0x40 + length)] + data)
                        } else {
                            return .literal([0x58, UInt8(length)] + data)
                        }
                    default:
                        return .literal([]) // Simplified
                }
            case .array(let a):
                return .array(a.map { $0.toEncodedValue() })
            case .map(let m):
                return .map(m.map { $0.toEncodedValue() })
            case .tagged(let tag, let inner):
                return .tagged(tag: .literal([]), value: inner.toEncodedValue())
        }
    }
}

extension CborValue {
    var debugDataTypeDescription: String {
        switch self {
            case .none:
                "none"
            case let .literal(v):
                v.debugDataTypeDescription
            case .array:
                "an array"
            case .map:
                "a map"
            case .tagged:
                "a tagged value"
        }
    }
}

extension CborValue {
    struct Writer {
        func writeValue(_ value: CborEncodedValue) -> [UInt8] {
            var bytes: [UInt8] = .init()
            writeValue(value, into: &bytes)
            return bytes
        }

        private func writeValue(_ value: CborEncodedValue, into bytes: inout [UInt8]) {
            switch value {
                case let .literal(data):
                    bytes.append(contentsOf: data)
                case let .tagged(tag, value):
                    writeValue(tag, into: &bytes)
                    writeValue(value, into: &bytes)
                case let .array(array):
                    let n = array.count
                    if n <= Int.fixMax {
                        bytes.append(contentsOf: [UInt8(0x80 + n)])
                    } else if n <= UInt8.max {
                        bytes.append(contentsOf: [UInt8(0x98), UInt8(n)])
                    } else if n <= UInt16.max {
                        bytes.append(contentsOf: [UInt8(0x99)] + n.bigEndianBytes(as: UInt16.self))
                    } else if n <= UInt32.max {
                        bytes.append(contentsOf: [UInt8(0x9A)] + n.bigEndianBytes(as: UInt32.self))
                    } else if n <= Int.max {
                        bytes.append(contentsOf: [UInt8(0x9B)] + n.bigEndianBytes(as: UInt64.self))
                    }
                    for item in array {
                        writeValue(item, into: &bytes)
                    }
                case let .map(a):
                    writeSortedMap(a, into: &bytes)
                default:
                    break
            }
        }
    }
}

enum CborOpCode {
    case uint(UInt8)
    case nint(UInt8)
    case bin(UInt8)
    case str(UInt8)
    case tagged(UInt8)
    case float(UInt8)
    case array(UInt8)
    case map(UInt8)
    case end

    init(ch c: UInt8) {
        let majorType: UInt8 = (c & 0b1110_0000) >> 5
        let additional: UInt8 = c & 0b0001_1111
        switch majorType {
            case 0:
                self = .uint(additional)
            case 1:
                self = .nint(additional)
            case 2:
                self = .bin(additional)
            case 3:
                self = .str(additional)
            case 4:
                self = .array(additional)
            case 5:
                self = .map(additional)
            case 6:
                self = .tagged(additional)
            case 7:
                self = .float(additional)
            default:
                fatalError()
        }
    }
}

extension CborValue.Writer {
    private func writeSortedMap(_ map: [CborEncodedValue], into bytes: inout [UInt8]) {
        let pairs = stride(from: 0, to: map.count, by: 2).map { (map[$0], map[$0 + 1]) }
        let sorted = pairs.sorted { lhs, rhs in
            let lhsBytes = writeValue(lhs.0)
            let rhsBytes = writeValue(rhs.0)
            return lhsBytes.lexicographicallyPrecedes(rhsBytes)
        }

        let n = sorted.count
        if n <= Int.fixMax {
            bytes.append(UInt8(0xA0 + n))
        } else if n <= UInt8.max {
            bytes.append(contentsOf: [0xB8, UInt8(n)])
        } else if n <= UInt16.max {
            bytes.append(contentsOf: [0xB9] + n.bigEndianBytes(as: UInt16.self))
        } else if n <= UInt32.max {
            bytes.append(contentsOf: [0xBA] + n.bigEndianBytes(as: UInt32.self))
        } else {
            bytes.append(contentsOf: [0xBB] + n.bigEndianBytes(as: UInt64.self))
        }

        for (k, v) in sorted {
            writeValue(k, into: &bytes)
            writeValue(v, into: &bytes)
        }
    }
}
