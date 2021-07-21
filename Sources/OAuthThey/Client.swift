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

public class Client {
    /// configuration for this `Client`
    public let configuration: Configuration

    /// publisher that will send new values with authentication status changes
    public let authenticationPublisher: AnyPublisher<Token?, Never>

    /// underlying storage type for subcribing to authentication changes
    private let tokenSubject: CurrentValueSubject<Token?, Never>

    /// Injected keychain service
    private let keychainService: KeychainServicing

    /// Keep a subscription to the token subject so we can update keychain
    private var tokenCanceller: AnyCancellable?

    /// Create a `Client` with the given `Configuration`
    public convenience init(configuration: Configuration) {
        self.init(configuration: configuration, keychainService: KeychainService(service: configuration.keychainServiceKey))
    }

    /// internal `init` to inject a mock keychain service for testing
    init(configuration: Configuration, keychainService: KeychainServicing) {
        self.configuration = configuration
        self.keychainService = keychainService

        // attempt to load a persisted token
        let token = try? self.keychainService.get(key: Client.keychainKey) as Token

        // the current value should be whether we are currently subscribed or not
        self.tokenSubject = CurrentValueSubject(token)
        self.authenticationPublisher = tokenSubject.eraseToAnyPublisher()

        // the subject is our source of truth so we just have to clean up Keychain when its value changes
        self.tokenCanceller = authenticationPublisher
            .receive(on: DispatchQueue.global())
            .sink {
                if let token = $0 {
                    try? keychainService.set(token, key: Client.keychainKey)
                } else {
                    keychainService.remove(key: Client.keychainKey)
                }
            }
    }
}

// MARK: - Initiating authentication
extension Client {

    /// returns whether this client is currently authenticated with the OAuth provider
    public var isAuthenticated: Bool {
        return tokenSubject.value != nil
    }

    /// initiates an OAuth 1.0a authorization flow
    public func startAuthorization(with request: AuthRequest) async throws {
        let tokenResponse = try await requestToken(for: request)
        let authorizeResponse = try await presentAuthorization(for: request, tokenResponse: tokenResponse)

        // setting this will trigger subscriptions
        self.tokenSubject.value = try await accessToken(for: request, authorizeResponse: authorizeResponse)
    }

    /// fills out `Authorization` and `User-Agent` headers necessary for an authentication gated endpoint
    public func authorizeRequest(_ request: inout URLRequest) {
        authorizeRequest(&request, contentType: nil, phase: .authenticated)
    }

    /// removes existing Token and cleans up the persisted token in keychain
    public func logout() {
        self.tokenSubject.value = nil
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
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\"\($0.value!)\"" }
            .joined(separator: ", ")

        request.setValue(oauthHeaders, forHTTPHeaderField: "Authorization")
    }

    func generateOAuthHeaders(for phase: AuthPhase) -> [URLQueryItem] {
        // use our real token or a temporary generated one to fill out the signature
        let currentToken: Token = tokenSubject.value ?? temporaryToken(for: phase)

        // need to round to nearest integer value
        let timestamp = Int(Date().timeIntervalSince1970)

        var headers: [URLQueryItem] = [
            .init(name: "oauth_version", value: "1.0"),
            .init(name: "oauth_signature_method", value: configuration.signatureMethod.rawValue),
            .init(name: "oauth_signature", value: currentToken.signature(with: configuration.consumerSecret)),
            .init(name: "oauth_consumer_key", value: configuration.consumerKey),
            .init(name: "oauth_timestamp", value: "\(timestamp)"),
            .init(name: "oauth_nonce", value: UUID().uuidString),
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
