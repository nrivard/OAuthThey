//
//  Client.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/10/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import AuthenticationServices
import Foundation
import Combine

/// OAuth 1.0a client that can be used to initiate authorization, authorize `URLRequest`s using the received OAuth token, or logout.
/// By default, this type saves the token to the secure keychain up receipt, loads any stored token on `init`, and removes the token when logged out.
public actor Client {
    /// configuration for this `Client`
    public let configuration: Configuration

    /// token used to authorize requests
    public private(set) var token: Token? {
        didSet {
            if let token = token {
                try? keychainService.set(token, key: Client.keychainKey)
            } else {
                keychainService.remove(key: Client.keychainKey)
            }
        }
    }

    /// Injected keychain service
    private let keychainService: KeychainServicing

    /// Create a `Client` with the given `Configuration`
    public convenience init(configuration: Configuration) {
        self.init(configuration: configuration, keychainService: KeychainService(service: configuration.keychainServiceKey))
    }

    /// internal `init` to inject a mock keychain service for testing
    init(configuration: Configuration, keychainService: KeychainServicing) {
        self.configuration = configuration
        self.keychainService = keychainService

        // attempt to load a persisted token
        token = try? keychainService.get(key: Client.keychainKey) as Token
    }
}

// MARK: - Initiating authentication
extension Client {

    /// convenience that checks whether this client has an authenticated token
    public var isAuthenticated: Bool {
        return token != nil
    }

    /// initiates an OAuth 1.0a authorization flow
    @discardableResult
    public func startAuthorization(with request: AuthRequest) async throws -> Token {
        let tokenResponse = try await requestToken(for: request)
        let authorizeResponse = try await presentAuthorization(for: request, tokenResponse: tokenResponse)

        token = try await accessToken(for: request, authorizeResponse: authorizeResponse)
        return token!
    }

    /// fills out `Authorization` and `User-Agent` headers necessary for an authentication gated endpoint
    public func authorizeRequest(_ request: inout URLRequest) {
        authorizeRequest(&request, contentType: nil, phase: .authenticated)
    }

    /// removes existing Token and cleans up the persisted token in keychain
    public func logout() {
        self.token = nil
    }
}

extension Client {

    func requestToken(for request: AuthRequest) async throws -> RequestTokenResponse {
        var urlReqest = URLRequest(url: request.requestURL)
        authorizeRequest(&urlReqest, contentType: .urlEncoded, phase: .requestingToken)

        let (data, _) = try await configuration.urlSession.data(for: urlReqest)

        guard let dataString = String(data: data, encoding: .utf8),
              let components = URLComponents(string: "?" + dataString)?.queryItems,
              let response = RequestTokenResponse(components: components)
        else {
            throw Error.invalidToken
        }

        return response
    }

    @MainActor
    func presentAuthorization(for request: AuthRequest, tokenResponse: RequestTokenResponse) async throws -> AuthorizeResponse {
        guard var components = URLComponents(url: request.authorizeURL, resolvingAgainstBaseURL: false) else {
            throw Error.invalidAuthorizeURL
        }

        components.queryItems = [.init(name: "oauth_token", value: tokenResponse.token)]

        guard let authorizeURL = components.url else {
            throw Error.invalidAuthorizeURL
        }

        let delegate = WebAuthenticationSessionContext(anchor: request.window)

        return try await withCheckedThrowingContinuation { continuation in
            let authSession = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: Client.callbackURL.scheme) { url, error in
                if let error = error {
                    if (error as NSError).code == 1 {
                        continuation.resume(throwing: Error.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }

                guard let url = url,
                      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                      let authorizeResponse = AuthorizeResponse(components: components, tokenSecret: tokenResponse.tokenSecret)
                else {
                    continuation.resume(throwing: Error.invalidVerifier)
                    return
                }

                continuation.resume(returning: authorizeResponse)
            }

            authSession.presentationContextProvider = delegate
            authSession.start()
        }
    }

    func accessToken(for request: AuthRequest, authorizeResponse: AuthorizeResponse) async throws -> Token {
        var urlRequest = URLRequest(url: request.accessTokenURL)
        urlRequest.httpMethod = HTTPMethod.POST.rawValue
        authorizeRequest(&urlRequest, contentType: .urlEncoded, phase: .requestingAccessToken(authorizeResponse))

        let (data, _) = try await configuration.urlSession.data(for: urlRequest)

        guard let dataString = String(data: data, encoding: .utf8),
              let components = URLComponents(string: "?" + dataString)?.queryItems,
              let token = Token(components: components)
        else {
            throw Error.invalidAccessToken
        }

        return token
    }
}

extension Client {

    static let callbackURL = URL(string: "oauththey:success")!
    static let keychainKey = "credentials"

    /// fills out headers necessary for an authentication gated endpoint. this private function is able to include
    /// a `Content-Type` as well as customize those headers depending on what auth phase the user is currently in
    func authorizeRequest(_ request: inout URLRequest, contentType: HTTPContentType?, phase: AuthPhase) {
        if let contentType = contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")

        let oauthHeaders = "OAuth " + generateOAuthHeaders(for: phase)
            .map { "\($0.name)=\"\($0.value!)\"" }
            .joined(separator: ", ")

        request.setValue(oauthHeaders, forHTTPHeaderField: "Authorization")
    }

    func generateOAuthHeaders(for phase: AuthPhase) -> [URLQueryItem] {
        // use our real token or a temporary generated one to fill out the signature
        let currentToken: Token = token ?? temporaryToken(for: phase)

        // need to round to nearest integer value
        let timestamp = Int(Date().timeIntervalSince1970)

        var headers: [URLQueryItem] = [
            .init(name: "oauth_consumer_key", value: configuration.consumerKey),
            .init(name: "oauth_nonce", value: UUID().uuidString),
            .init(name: "oauth_signature", value: currentToken.signature(with: configuration.consumerSecret)),
            .init(name: "oauth_signature_method", value: configuration.signatureMethod.rawValue),
            .init(name: "oauth_timestamp", value: "\(timestamp)"),
            .init(name: "oauth_version", value: "1.0")
        ]

        switch phase {
        case .requestingToken:
            let callbackURL = Client.callbackURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
            headers += [
                .init(name: "oauth_callback", value: callbackURL)
            ]
        case .requestingAccessToken(let authResponse):
            headers += [
                .init(name: "oauth_token", value: authResponse.token),
                .init(name: "oauth_verifier", value: authResponse.verifier)
            ]
        case .authenticated:
            headers += [
                .init(name: "oauth_token", value: currentToken.key)
            ]
        }

        return headers
    }
}

extension Client {

    private func temporaryToken(for phase: AuthPhase) -> Token {
        switch phase {
        case .authenticated, .requestingToken:
            return .init(key: "", secret: "")
        case .requestingAccessToken(let authResponse):
            return .init(key: "", secret: authResponse.tokenSecret)
        }
    }
}

extension Client {

    @objc private class WebAuthenticationSessionContext: NSObject, ASWebAuthenticationPresentationContextProviding {
        let anchor: ASPresentationAnchor

        init(anchor: ASPresentationAnchor) {
            self.anchor = anchor
        }

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            anchor
        }
    }
}
