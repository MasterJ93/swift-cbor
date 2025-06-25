import Foundation

class CborScanner {
    internal let data: Data
    internal var off: Int
    init(data: Data) {
        self.data = data
        off = 0
    }

    internal func read(_ n: Int) -> Data {
        defer {
            off += n
        }
        return data[off ..< (off + n)]
    }

    func scan() -> CborValue {
        switch readOpCode() {
            case let .uint(a):
                scanUInt(additional: a)
            case let .nint(a):
                scanNInt(additional: a)
            case let .bin(a):
                scanBinaryString(additional: a)
            case let .str(a):
                scanString(additional: a)
            case let .tagged(a):
                scanTaggedValue(additional: a)
            case let .float(a):
                scanFloat(additional: a)
            case let .array(a):
                scanArray(additional: a)
            case let .map(a):
                scanMap(additional: a)
            case .end:
                    .none
        }
    }

    internal func scanUInt(additional c: UInt8) -> CborValue {
        let (data, type) = _scanUInt(c: c)
        return .literal(.uint(data, type))
    }

    internal func scanNInt(additional c: UInt8) -> CborValue {
        let (data, type) = _scanUInt(c: c)
        return .literal(.int(data, type))
    }

    internal func scanBinaryString(additional: UInt8) -> CborValue {
        .literal(.bin(scanSequence(additional: additional)))
    }

    internal func scanString(additional: UInt8) -> CborValue {
        .literal(.str(scanSequence(additional: additional)))
    }

    internal func scanSequence(additional c: UInt8) -> Data {
        if let n = getLength(c: c) {
            return read(n)
        } else {
            let start = off
            while data[off] != 0xFF {
                off += 1
            }
            return data[start ..< off]
        }
    }

    internal func scanFloat(additional c: UInt8) -> CborValue {
        switch c {
            case 0x00 ... 0x13:
                    .literal(.uint(.init([c]), UInt8.self))
            case 0x14:
                    .literal(.bool(false))
            case 0x15:
                    .literal(.bool(true))
            case 0x16, 0x17:
                    .literal(.nil)
            case 0x18:
                    .literal(.uint(read(1 << 0), UInt8.self))
            case 0x19:
                    .literal(.float16(read(1 << 1)))
            case 0x1A:
                    .literal(.float32(read(1 << 2)))
            case 0x1B:
                    .literal(.float64(read(1 << 3)))
            case 0x1F:
                    .literal(.break)
            default:
                    .none
        }
    }

    internal func scanTaggedValue(additional c: UInt8) -> CborValue {
        let (data, type) = _scanUInt(c: c)
        return .tagged(tag: .uint(data, type), value: scan())
    }

    internal func scanArray(additional c: UInt8) -> CborValue {
        var a: [CborValue] = []
        let indefinite: Bool
        if let n = getLength(c: c) {
            indefinite = false
            a.reserveCapacity(n)
            for _ in 0..<n {
                a.append(scan())
            }
        } else {
            indefinite = true
            while true {
                let e = scan()
                if case .literal(.break) = e {
                    break
                }
                a.append(e)
            }
        }
        return .array(a, isIndefinite: indefinite)
    }

    internal func scanMap(additional c: UInt8) -> CborValue {
        var a: [CborValue] = []
        let indefinite: Bool
        if let n = getLength(c: c) {
            indefinite = false
            a.reserveCapacity(n)
            for _ in 0..<n {
                a.append(scan())
                a.append(scan())
            }
        } else {
            indefinite = true
            while true {
                let k = scan()
                if case .literal(.break) = k {
                    break
                }
                let v = scan()
                if case .literal(.break) = v {
                    break
                }
                a.append(k)
                a.append(v)
            }
        }
        return .map(a, isIndefinite: indefinite)
    }


    internal func getLength(c: UInt8) -> Int? {
        guard c != 0x1F else { return nil }
        let (data, type) = _scanUInt(c: c)
        return Int(truncatingIfNeeded: bigEndianFixedWidthInt(data, as: type))
    }

    internal func _scanUInt(c: UInt8) -> (Data, any FixedWidthInteger.Type) {
        switch c {
            case 0x00 ... 0x17:
                (.init([c]), UInt8.self)
            case 0x18:
                (read(1 << 0), UInt8.self)
            case 0x19:
                (read(1 << 1), UInt16.self)
            case 0x1A:
                (read(1 << 2), UInt32.self)
            case 0x1B:
                (read(1 << 3), UInt64.self)
            default:
                fatalError()
        }
    }

    internal func readOpCode() -> CborOpCode {
        if off < data.count {
            defer {
                off += 1
            }
            return CborOpCode(ch: data[off])
        } else {
            return .end
        }
    }
}
