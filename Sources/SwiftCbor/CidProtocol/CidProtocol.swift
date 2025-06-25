//
//  CidProtocol.swift
//  swift-cbor
//
//  Created by Christopher Jr Riley on 2025-06-25.
//

import Foundation

public protocol CidProtocol: Sendable, Codable {

    var rawData: Data { get throws }

    init(from decoder: Decoder) throws

    func encode(to encoder: Encoder) throws
}
