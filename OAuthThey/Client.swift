//
//  Client.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/10/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import Foundation

public class Client {

    public let consumerKey: String
    public let consumerSecret: String

    public var signatureMethod: SignatureMethod = .plaintext

    public init(consumerKey: String, consumerSecret: String) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
    }
}

// MARK: - Initiating authentication
extension Client {

    /// signature methods supported
    public enum SignatureMethod: String {
        /// the only signature method currently supported
        case plaintext = "PLAINTEXT"
    }

    public enum ContentType: String {
        case urlEncoded = "application/x-www-form-urlencoded"
        case JSON = "application/json"
    }

    public struct AuthRequest {
        public let requestURL: URL
        public let authorizeURL: URL
        public let accessTokenURL: URL
        public let callbackURL: URL

        public init(requestURL: URL, authorizeURL: URL, accessTokenURL: URL, callbackURL: URL) {
            self.requestURL = requestURL
            self.authorizeURL = authorizeURL
            self.accessTokenURL = accessTokenURL
            self.callbackURL = callbackURL
        }
    }

    public func startAuthorization(with request: AuthRequest, session: URLSession = .shared, completion: (Result<Token, Error>) -> Void = { _ in }) {
        getRequestToken(with: request) { requestTokenResult in
            
        }
    }

    private func getRequestToken(with request: AuthRequest, completion: (Result<Any, Error>) -> Void) {

    }
}

extension Client {

    public func authorizeRequest(_ request: inout URLRequest, contentType: ContentType) {

    }
}

extension Client {

    private var oauthHeaders: [String] {
        return [
            "oauth_version=1.0",
            "oauth_signature_method=\(signatureMethod.rawValue)",
            "oauth_consumer_key=\(consumerKey)",
            "oauth_timestamp=\(floor(Date().timeIntervalSince1970))",
            "oauth_nonce=\(UUID().uuidString)"
        ]
    }
}
