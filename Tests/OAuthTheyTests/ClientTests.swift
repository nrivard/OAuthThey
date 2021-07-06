//
//  File.swift
//  
//
//  Created by Nate Rivard on 02/07/2021.
//

import XCTest
@testable import OAuthThey

@available(iOS 15, macOS 12, *)
final class ClientTests: XCTestCase {

    let client: Client = {
        let config = Client.Configuration(consumerKey: "OAuthTheyTest", consumerSecret: "shhh", userAgent: "", keychainServiceKey: "TestDomain")
        let token = Token(key: "key", secret: "secret")

        let keychainService = MockKeychainService()
        try! keychainService.set(token, key: Client.keychainKey)

        let client = Client(configuration: config, keychainService: keychainService)

        return client
    }()

    func testCommonOAuthHeaders() throws {
        let headers = client.generateOAuthHeaders(for: .authenticated)

        let version = try XCTUnwrap(headers.first(where: { $0.name == "oauth_version" }))
        XCTAssertEqual(version.value, "1.0")

        let signatureMethod = try XCTUnwrap(headers.first(where: { $0.name == "oauth_signature_method" }))
        XCTAssertEqual(signatureMethod.value, Client.SignatureMethod.plaintext.rawValue)

        let signature = try XCTUnwrap(headers.first(where: { $0.name == "oauth_signature" }))
        XCTAssertEqual(signature.value, "shhh&secret")

        let consumerKey = try XCTUnwrap(headers.first(where: { $0.name == "oauth_consumer_key" }))
        XCTAssertEqual(consumerKey.value, "OAuthTheyTest")

        XCTAssertNotNil(headers.first(where: { $0.name == "oauth_timestamp"}))
        XCTAssertNotNil(headers.first(where: { $0.name == "oauth_nonce"}))
    }

    func testAuthenticatedOAuthHeaders() throws {
        let headers = client.generateOAuthHeaders(for: .authenticated)

        let token = try XCTUnwrap(headers.first(where: { $0.name == "oauth_token" }))
        XCTAssertEqual(token.value, "key")
    }

    func testRequestingTokenOAuthHeaders() throws {
        let headers = client.generateOAuthHeaders(for: .requestingToken)

        let callback = try XCTUnwrap(headers.first(where: { $0.name == "oauth_callback" }))
        XCTAssertEqual(callback.value, Client.callbackURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed))
    }

    func testRequestingAccessTokenOAuthHeaders() throws {
        let authorizeResponse = Client.AuthorizeResponse(token: "token", tokenSecret: "tokenSecret", verifier: "verifier")
        let headers = client.generateOAuthHeaders(for: .requestingAccessToken(authorizeResponse))

        let token = try XCTUnwrap(headers.first(where: { $0.name == "oauth_token" }))
        XCTAssertEqual(token.value, authorizeResponse.token)

        let verifier = try XCTUnwrap(headers.first(where: { $0.name == "oauth_verifier" }))
        XCTAssertEqual(verifier.value, authorizeResponse.verifier)
    }
}
