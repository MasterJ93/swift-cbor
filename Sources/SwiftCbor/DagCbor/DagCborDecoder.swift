import Foundation

open class DagCborDecoder: CborDecoder {
    public override init() {
        super.init()
    }

    public override func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let scanner = CborScanner(data: data)
        let value = scanner.scan()

        // 🔍 Pre-validate DAG-CBOR constraints
        try validateDagCbor(value, codingPath: [])

        // ✅ Decode only after validating
        let decoder = _CborDecoder(from: value) // Not DagCborDecoder; no override needed
        return try decoder.unwrap(as: T.self)
    }

    internal func validateDagCbor(_ value: CborValue, codingPath: [CodingKey]) throws {
        switch value {
            case .none:
                return

            case .literal(let literal):
                switch literal {
                    case .float16, .float32, .float64:
                        throw DecodingError.dataCorrupted(DecodingError.Context(
                            codingPath: codingPath,
                            debugDescription: "DAG-CBOR forbids floating-point numbers"
                        ))

                    case .break:
                        throw DecodingError.dataCorrupted(DecodingError.Context(
                            codingPath: codingPath,
                            debugDescription: "DAG-CBOR forbids indefinite-length items"
                        ))

                    default:
                        return
                }

            case .array(let elements, let isIndefinite):
                if isIndefinite {
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "DAG-CBOR forbids indefinite-length arrays"
                    ))
                }

                for (index, element) in elements.enumerated() {
                    try validateDagCbor(element, codingPath: codingPath + [CborKey(index: index)])
                }

            case .map(let pairs, let isIndefinite):
                if isIndefinite {
                    throw DecodingError.dataCorrupted(DecodingError.Context(
                        codingPath: codingPath,
                        debugDescription: "DAG-CBOR forbids indefinite-length maps"
                    ))
                }

                var seenKeys: Set<String> = []
                for i in stride(from: 0, to: pairs.count, by: 2) {
                    let key = pairs[i]
                    let val = pairs[i + 1]

                    // Require that the key is a string literal
                    if case .literal(.str(let keyData)) = key {
                        let keyStr = String(decoding: keyData, as: UTF8.self)
                        if !seenKeys.insert(keyStr).inserted {
                            throw DecodingError.dataCorrupted(DecodingError.Context(
                                codingPath: codingPath,
                                debugDescription: "Duplicate map key '\(keyStr)' found in DAG-CBOR"
                            ))
                        }
                    } else {
                        throw DecodingError.dataCorrupted(DecodingError.Context(
                            codingPath: codingPath,
                            debugDescription: "DAG-CBOR requires map keys to be strings"
                        ))
                    }

                    try validateDagCbor(val, codingPath: codingPath + [CborKey(stringValue: "key: \(i)")])
                }

            case .tagged(_, let inner):
                try validateDagCbor(inner, codingPath: codingPath)
        }
    }

}


internal class _DagCborDecoder: _CborDecoder {

    public func unwrapDagCbor<T: Decodable>(as type: T.Type) throws -> T {
        // Reject indefinite-length arrays
        if case .array(_, true) = value {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "DAG-CBOR forbids indefinite-length arrays"
            ))
        }

        if case .map(_, true) = value {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "DAG-CBOR forbids indefinite-length maps"
            ))
        }

        return try super.unwrap(as: type)
    }



    override func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key : CodingKey {
        guard case .map = value else {
            throw DecodingError.typeMismatch([String: Any].self, DecodingError.Context(
                codingPath: codingPath,
                debugDescription: "Expected to decode \([String: Any].self) but found \(value.debugDataTypeDescription) instead."
            ))
        }

        let dictionary = CborKeyedDecodingContainer<Key>.asDictionary(value: value, using: self)
        var seen: Set<String> = []
        for key in dictionary.keys {
            guard seen.insert(key).inserted else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Duplicate map key '\(key)' found in DAG-CBOR"
                ))
            }
        }
        return KeyedDecodingContainer(CborKeyedDecodingContainer<Key>(referencing: self, container: value))
    }
}
