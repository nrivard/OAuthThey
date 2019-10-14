//
//  Client+Types.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/14/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import UIKit

extension Client {

    /// signature methods supported
    public enum SignatureMethod: String {
        /// the only signature method currently supported
        case plaintext = "PLAINTEXT"
    }

    public enum HTTPContentType: String {
        case urlEncoded = "application/x-www-form-urlencoded"
        case JSON = "application/json"
    }

    public enum HTTPMethod: String {
        case GET
        case POST
        case PUT
        case DELETE
    }

    public enum Error: Swift.Error {
        case invalidToken
        case invalidAuthorizeURL
        case invalidVerifier
        case invalidAccessToken
    }

    public struct AuthRequest {
        public let requestURL: URL
        public let authorizeURL: URL
        public let accessTokenURL: URL

        public let window: UIWindow

        public init(requestURL: URL, authorizeURL: URL, accessTokenURL: URL, window: UIWindow) {
            self.requestURL = requestURL
            self.authorizeURL = authorizeURL
            self.accessTokenURL = accessTokenURL
            self.window = window
        }
    }
}
