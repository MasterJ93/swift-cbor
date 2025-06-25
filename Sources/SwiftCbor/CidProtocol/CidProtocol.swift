import Foundation

public protocol CidProtocol: Sendable, Codable {

    var rawData: Data { get throws }

    init(from decoder: Decoder) throws

    func encode(to encoder: Encoder) throws
}
