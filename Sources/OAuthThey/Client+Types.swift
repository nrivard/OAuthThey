//
//  Client+Types.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/14/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import AuthenticationServices

@available(iOS 15, macOS 12, *)
extension Client {

    /// signature methods supported
    public enum SignatureMethod: String, Codable {
        /// the only signature method currently supported
        case plaintext = "PLAINTEXT"
    }

    /// configures a `Client`
    public struct Configuration {
        /// the given OAuth consumer key
        public let consumerKey: String

        /// the given OAuth consumer secret
        public let consumerSecret: String

        /// the given user agent to include as part of the headers in each request
        public let userAgent: String

        /// where in the Keychain the service should be stored
        public let keychainServiceKey: String

        /// the signature method this client will use to communicate with the OAuth provider
        public let signatureMethod: SignatureMethod

        /// the session to use to make requests
        public let urlSession: URLSession

        public init(consumerKey: String, consumerSecret: String, userAgent: String, keychainServiceKey: String, signatureMethod: SignatureMethod = .plaintext, urlSession: URLSession = .shared) {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            self.userAgent = userAgent
            self.keychainServiceKey = keychainServiceKey
            self.signatureMethod = signatureMethod
            self.urlSession = urlSession
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidToken
        case invalidAuthorizeURL
        case invalidVerifier
        case invalidAccessToken
        case cancelled
        case authorizationInProgress

        public var description: String {
            switch self {
            case .invalidToken, .invalidVerifier, .invalidAuthorizeURL, .invalidAccessToken:
                return "There was a problem connecting with your provider’s OAuth service."
            case .cancelled:
                return "You cancelled authorization with your provider’s OAuth service."
            case .authorizationInProgress:
                return "Authorization is already in progress."
            }
        }
    }

    public struct AuthRequest {
        public let requestURL: URL
        public let authorizeURL: URL
        public let accessTokenURL: URL

        public let window: ASPresentationAnchor

        public init(requestURL: URL, authorizeURL: URL, accessTokenURL: URL, window: ASPresentationAnchor = PlatformApplication.currentWindow) {
            self.requestURL = requestURL
            self.authorizeURL = authorizeURL
            self.accessTokenURL = accessTokenURL
            self.window = window
        }
    }
}

@available(iOS 15, macOS 12, *)
extension Client {

    struct RequestTokenResponse {
        let token: String
        let tokenSecret: String
        let callbackConfirmed: Bool

        init?(components: [URLQueryItem]) {
            guard let token = components.first(where: { $0.name == "oauth_token" })?.value,
                  let tokenSecret = components.first(where: { $0.name == "oauth_token_secret"})?.value,
                  let callbackConfirmedString = components.first(where: { $0.name == "oauth_callback_confirmed" })?.value,
                  let callbackConfirmed = Bool(callbackConfirmedString)
            else {
                return nil
            }

            self.token = token
            self.tokenSecret = tokenSecret
            self.callbackConfirmed = callbackConfirmed
        }
    }

    struct AuthorizeResponse {
        let token: String
        let tokenSecret: String
        let verifier: String

        init?(components: [URLQueryItem], tokenSecret: String) {
            guard let token = components.first(where: { $0.name == "oauth_token" })?.value,
                  let verifier = components.first(where: { $0.name == "oauth_verifier"})?.value
            else {
                return nil
            }

            self.init(token: token, tokenSecret: tokenSecret, verifier: verifier)
        }

        init(token: String, tokenSecret: String, verifier: String) {
            self.token = token
            self.tokenSecret = tokenSecret
            self.verifier = verifier
        }
    }

    enum AuthPhase {
        /// the first phase of authentication
        case requestingToken

        /// the second phase of authentication. Requires an `AuthorizeResponse` to properly fill out
        case requestingAccessToken(AuthorizeResponse)

        /// used when already authenticated and need to "sign" a request
        case authenticated
    }

    enum HTTPContentType: String {
        case urlEncoded = "application/x-www-form-urlencoded; charset=utf-8"
    }

    enum HTTPMethod: String {
        case GET
        case POST
    }
}
