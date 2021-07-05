//
//  File.swift
//  
//
//  Created by Nate Rivard on 02/07/2021.
//

import XCTest
@testable import OAuthThey

@available(iOS 15, macOS 12, *)
final class TokenTests: XCTestCase {

    func testInitFromComponents() throws {
        var components: [URLQueryItem] = [
            .init(name: "oauth_token", value: "key"),
            .init(name: "oauth_token_secret", value: "secret")
        ]

        let token = try XCTUnwrap(Token(components: components))
        XCTAssertEqual(token.key, "key")
        XCTAssertEqual(token.secret, "secret")

        components = [
            .init(name: "wrong", value: "who cares")
        ]

        XCTAssertNil(Token(components: components))
    }

    func testSignature() throws {
        let token = Token(key: "key", secret: "secret")
        let signature = token.signature(with: "consumerSecret")
        XCTAssertEqual("consumerSecret&secret", signature)
    }
}
