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

@objc
public class Client: NSObject {

    /// the given OAuth consumer key
    public let consumerKey: String

    /// the given OAuth consumer secret
    public let consumerSecret: String

    /// the given user agent to include as part of the headers in each request
    public let userAgent: String

    /// the session to use to make requests
    public let session: URLSession

    /// the signature method this client will use to communicate with the OAuth provider
    public var signatureMethod: SignatureMethod = .plaintext

    /// token returned after successfully authenticating or `nil` if not currently logged in
    public private(set) var token: Token? {
        didSet {
            if let token = token {
                try? keychainService.set(token, key: Client.keychainKey)
            } else {
                keychainService.remove(key: Client.keychainKey)
            }

            authenticationSubject.value = token != nil
        }
    }

    /// returns whether this client is currently authenticated with the OAuth provider
    public var isAuthenticated: Bool {
        return authenticationSubject.value
    }

    public var isAuthorizing: Bool = false

    /// underying storage type for subcribing to authentication changes
    private let authenticationSubject: CurrentValueSubject<Bool, Never>

    /// publisher that will send new values when authentication status changes
    public var authenticationPublisher: AnyPublisher<Bool, Never>

    /// we need to retain these during the web authentication phase
    private weak var authAnchor: ASPresentationAnchor?
    private var authSession: ASWebAuthenticationSession?

    private let keychainService = KeychainService(service: "com.oauththey")

    public init(consumerKey: String, consumerSecret: String, userAgent: String, session: URLSession = .shared) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.userAgent = userAgent
        self.session = session

        // attempt to load a persisted token. Since this is in `init`, it won't trigger the persistence portion in `didSet`
        self.token = try? keychainService.get(key: Client.keychainKey)

        // the current value should be whether we are currently subscribed or not
        self.authenticationSubject = CurrentValueSubject(self.token != nil)
        self.authenticationPublisher = authenticationSubject.eraseToAnyPublisher()
    }
}

// MARK: - Initiating authentication
extension Client {

    private struct RequestTokenResponse {
        let token: String
        let tokenSecret: String
        let callbackConfirmed: Bool

        init?(components: [URLQueryItem]) {
            guard let token = components.first(where: { $0.name == "oauth_token" })?.value,
                let tokenSecret = components.first(where: { $0.name == "oauth_token_secret"})?.value,
                let callbackConfirmedString = components.first(where: { $0.name == "oauth_callback_confirmed" })?.value,
                let callbackConfirmed = Bool(callbackConfirmedString) else
            {
                return nil
            }

            self.token = token
            self.tokenSecret = tokenSecret
            self.callbackConfirmed = callbackConfirmed
        }
    }

    private struct AuthorizeResponse {
        let token: String
        let tokenSecret: String
        let verifier: String

        init?(components: [URLQueryItem], tokenSecret: String) {
            guard let token = components.first(where: { $0.name == "oauth_token" })?.value,
                let verifier = components.first(where: { $0.name == "oauth_verifier"})?.value else
            {
                return nil
            }

            self.token = token
            self.tokenSecret = tokenSecret
            self.verifier = verifier
        }
    }

    /// start an OAuth based authorization flow using the given `request`
    public func startAuthorization(with request: AuthRequest, completion: @escaping (Result<Token, Swift.Error>) -> Void = { _ in }) {
        guard !isAuthorizing else { return }

        isAuthorizing = true

        let authCompletion: (Result<Token, Swift.Error>) -> Void = { [weak self] result in
            self?.isAuthorizing = false
            completion(result)
        }

        getRequestToken(with: request) { [weak self] requestTokenResult in
            do {
                let tokenResponse = try requestTokenResult.get()
                self?.presentAuthorization(with: request, tokenResponse: tokenResponse) { authResult in
                    do {
                        let authorizeResponse = try authResult.get()
                        self?.getAccessToken(with: request, authorizeResponse: authorizeResponse) { accessResult in
                            do {
                                let token = try accessResult.get()
                                self?.token = token
                                authCompletion(.success(token))
                            } catch {
                                authCompletion(.failure(error))
                            }
                        }
                    } catch {
                        authCompletion(.failure(error))
                    }
                }
            } catch {
                authCompletion(.failure(error))
            }
        }
    }

    private func getRequestToken(with request: AuthRequest, completion: @escaping (Result<RequestTokenResponse, Swift.Error>) -> Void) {
        var urlReqest = URLRequest(url: request.requestURL)
        authorizeRequest(&urlReqest, contentType: .urlEncoded, phase: .requestingToken)

        let task = session.dataTask(with: urlReqest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                let dataString = String(data: data, encoding: .utf8),
                let components = URLComponents(string: "?" + dataString)?.queryItems,
                let response = RequestTokenResponse(components: components) else
            {
                completion(.failure(Error.invalidToken))
                return
            }

            completion(.success(response))
        }

        task.resume()
    }

    private func presentAuthorization(with request: AuthRequest, tokenResponse: RequestTokenResponse, completion: @escaping (Result<AuthorizeResponse, Swift.Error>) -> Void) {
        guard var components = URLComponents(url: request.authorizeURL, resolvingAgainstBaseURL: false) else {
            completion(.failure(Error.invalidAuthorizeURL))
            return
        }

        components.queryItems = [.init(name: "oauth_token", value: tokenResponse.token)]

        guard let authorizeURL = components.url else {
            completion(.failure(Error.invalidAuthorizeURL))
            return
        }

        authSession = ASWebAuthenticationSession(url: authorizeURL, callbackURLScheme: Client.callbackURL.scheme) { [weak self] url, error in
            defer {
                self?.authSession = nil
                self?.authAnchor = nil
            }

            if let error = error {
                if (error as NSError).code == 1 {
                    // cancellation
                    completion(.failure(Error.cancelled))
                } else {
                    completion(.failure(error))
                }

                return
            }

            guard let url = url,
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                let authorizeResponse = AuthorizeResponse(components: components, tokenSecret: tokenResponse.tokenSecret) else
            {
                completion(.failure(Error.invalidVerifier))
                return
            }

            completion(.success(authorizeResponse))
        }

        authAnchor = request.window
        authSession!.presentationContextProvider = self

        authSession!.start()
    }

    private func getAccessToken(with request: AuthRequest, authorizeResponse: AuthorizeResponse, completion: @escaping (Result<Token, Swift.Error>) -> Void) {
        var urlRequest = URLRequest(url: request.accessTokenURL)
        urlRequest.httpMethod = HTTPMethod.POST.rawValue
        authorizeRequest(&urlRequest, contentType: .urlEncoded, phase: .requestingAccessToken(authorizeResponse))

        let task = session.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                let dataString = String(data: data, encoding: .utf8),
                let components = URLComponents(string: "?" + dataString)?.queryItems,
                let token = Token(components: components) else
            {
                completion(.failure(Error.invalidAccessToken))
                return
            }

            completion(.success(token))
        }

        task.resume()
    }
}

extension Client {

    private static let callbackURL = URL(string: "oauththey:success")!
    private static let keychainKey = "credentials"

    private enum AuthPhase {
        /// the first phase of authentication
        case requestingToken

        /// the second phase of authentication. Requires an `AuthorizeResponse` to properly fill out
        case requestingAccessToken(AuthorizeResponse)

        /// used when already authenticated and need to "sign" a request
        case authenticated
    }

    private enum HTTPContentType: String {
        case urlEncoded = "application/x-www-form-urlencoded; charset=utf-8"
    }

    private enum HTTPMethod: String {
        case GET
        case POST
    }

    /// removes persisted credentials and removes existing Token
    public func logout() {
        self.token = nil
    }

    /// fills out `Authorization` and `User-Agent` headers necessary for an authentication gated endpoint
    public func authorizeRequest(_ request: inout URLRequest) {
        authorizeRequest(&request, contentType: nil, phase: .authenticated)
    }

    /// fills out headers necessary for an authentication gated endpoint. this private function is able to include
    /// a `Content-Type` as well as customize those headers depending on what auth phase the user is currently in
    private func authorizeRequest(_ request: inout URLRequest, contentType: HTTPContentType?, phase: AuthPhase) {
        if let contentType = contentType {
            request.setValue(contentType.rawValue, forHTTPHeaderField: "Content-Type")
        }
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(generateOAuthHeaders(for: phase), forHTTPHeaderField: "Authorization")
    }

    private func generateOAuthHeaders(for phase: AuthPhase) -> String {
        // use our real token or a temporary generated one to fill out the signatured
        let currentToken: Token = token ?? temporaryToken(for: phase)

        // need to round to nearest integer value
        let timestamp = Int(Date().timeIntervalSince1970)

        var headers: [URLQueryItem] = [
            .init(name: "oauth_version", value: "1.0"),
            .init(name: "oauth_signature_method", value: signatureMethod.rawValue),
            .init(name: "oauth_signature", value: currentToken.signature(with: consumerSecret)),
            .init(name: "oauth_consumer_key", value: consumerKey),
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

        let mappedHeaders = headers
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\"\($0.value!)\"" }
            .joined(separator: ", ")

        return "OAuth " + mappedHeaders
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

extension Client: ASWebAuthenticationPresentationContextProviding {

    /// `authAnchor` needs to be set and non-nil or this will crash
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return authAnchor!
    }
}
