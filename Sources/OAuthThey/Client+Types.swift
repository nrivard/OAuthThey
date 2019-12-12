//
//  Client+Types.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/14/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import AuthenticationServices

extension Client {

    /// signature methods supported
    public enum SignatureMethod: String, Codable {
        /// the only signature method currently supported
        case plaintext = "PLAINTEXT"
    }

    public enum Error: Swift.Error {
        case invalidToken
        case invalidAuthorizeURL
        case invalidVerifier
        case invalidAccessToken
        case cancelled
    }

    public struct AuthRequest {
        public let requestURL: URL
        public let authorizeURL: URL
        public let accessTokenURL: URL

        public let window: ASPresentationAnchor

        public init(requestURL: URL, authorizeURL: URL, accessTokenURL: URL, window: ASPresentationAnchor) {
            self.requestURL = requestURL
            self.authorizeURL = authorizeURL
            self.accessTokenURL = accessTokenURL
            self.window = window
        }
    }
}
