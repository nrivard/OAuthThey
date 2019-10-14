//
//  Client.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/10/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import AuthenticationServices
import Foundation

public class Client {

    public let consumerKey: String
    public let consumerSecret: String
    public let userAgent: String

    /// the session to use to make requests
    public let session: URLSession

    /// the signature method this client will use to communicate with the OAuth provider
    public var signatureMethod: SignatureMethod = .plaintext

    /// token returned after successfully authenticating or `nil` if not currently logged in
    public var token: Token? {
        didSet {
            if let token = token {
                try? keychainService.set(token, key: Client.keychainKey)
            } else {
                try? keychainService.remove(key: Client.keychainKey)
            }
        }
    }

    /// returns whether this client is currently authenticated with the OAuth provider
    public var isAuthenticated: Bool {
        return token != nil
    }

    /// we need to retain these during the web authentication phase
    private var authContextProvider: ClientContextProvider?
    private var authSession: ASWebAuthenticationSession?

    private let keychainService = KeychainService(service: "com.oauththey")

    public init(consumerKey: String, consumerSecret: String, userAgent: String, session: URLSession = .shared) {
        self.consumerKey = consumerKey
        self.consumerSecret = consumerSecret
        self.userAgent = userAgent
        self.session = session

        // attempt to load a persisted token
        self.token = try? keychainService.get(key: Client.keychainKey)
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

    public func startAuthorization(with request: AuthRequest, completion: @escaping (Result<Token, Swift.Error>) -> Void = { _ in }) {
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
                                completion(.success(token))
                            } catch {
                                completion(.failure(error))
                            }
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            } catch {
                completion(.failure(error))
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
            self?.authSession = nil
            self?.authContextProvider = nil

            if let error = error {
                completion(.failure(error))
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

        authContextProvider = ClientContextProvider(window: request.window)
        authSession!.presentationContextProvider = authContextProvider!

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
        /// the first phase of authentication. must pass the callback URL
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

    /// fill out headers necessary for an authentication gated endpoint
    public func authorizeRequest(_ request: inout URLRequest) {
        authorizeRequest(&request, contentType: nil, phase: .authenticated)
    }

    /// fill out headers necessary for an authentication gated endpoint. this private function is able to include
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
            headers.append(.init(name: "oauth_callback", value: callbackURL))
        case .requestingAccessToken(let authResponse):
            headers += [
                .init(name: "oauth_token", value: authResponse.token),
                .init(name: "oauth_verifier", value: authResponse.verifier)
            ]
        case .authenticated:
            // nothing to add here
            break
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
