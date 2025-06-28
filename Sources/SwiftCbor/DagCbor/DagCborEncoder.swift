import Foundation

open class DagCborEncoder: CborEncoder {
    public override init() {
        super.init()
    }

    public override func encode(_ value: some Encodable) throws -> Data {
        let value: CborEncodedValue = try encodeAsDagCborValue(value)
        let writer = CborValue.Writer()
        let bytes = writer.writeValue(value)
        return Data(bytes)
    }

    func encodeAsDagCborValue<T: Encodable>(_ value: T) throws -> CborEncodedValue {
        let encoder = _DagCborEncoder(codingPath: [])
        guard let result = try encoder.wrapEncodable(value, for: CodingKey?.none) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Top-level \(T.self) did not encode any values."))
        }
        return result
    }
}

internal class _DagCborEncoder: _CborEncoder {
    public func wrapFloat<F: FloatingPoint & DataNumber>(_ value: F, for additionalKey: CodingKey?) throws -> CborEncodedValue {
        throw EncodingError.invalidValue(value, EncodingError.Context(
            codingPath: codingPath,
            debugDescription: "DAG-CBOR forbids floating-point numbers")
        )
    }

    public func wrapEncodable(_ encodable: some Encodable, for additionalKey: CodingKey?) throws -> CborEncodedValue? {
        if let cid = encodable as? CidProtocol {
            let rawData = try cid.rawData
            let bytes = [0x00] + [UInt8](rawData)
            let tag = try wrapUInt(UInt64(42), majorType: 0b1100_0000, for: additionalKey)
            return .tagged(tag: tag, value: .literal(bytes))
        }

        if let double = encodable as? Double {
            guard double.isFinite else {
                throw EncodingError.invalidValue(double, EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "DAG-CBOR forbids NaN or Infinity values")
                )
            }
        }
        if let float = encodable as? Float {
            guard float.isFinite else {
                throw EncodingError.invalidValue(float, EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "DAG-CBOR forbids NaN or Infinity values")
                )
            }
        }

        return try super.wrapEncodable(encodable, for: additionalKey)
    }
}
