//
//  Token.swift
//  OAuthThey
//
//  Created by Nate Rivard on 10/10/19.
//  Copyright © 2019 Nate Rivard. All rights reserved.
//

import Foundation

public struct Token: Codable {

    /// The OAuth token key
    let key: String

    /// The OAuth token secret
    let secret: String

    /// The OAuth token session
    let session: String

    /// The OAuth token verifier
//    let verifier: String

    public init(key: String, secret: String, session: String) {
        self.key = key
        self.secret = secret
        self.session = session
    }
}

extension Token {

    init?(queryParameters: [URLQueryItem]) {
        guard let key = queryParameters.first(where: { $0.name == "oauth_token"})?.value,
            let secret = queryParameters.first(where: { $0.name == "oauth_token_secret"})?.value else { return nil }

        // this can be empty
        let session = queryParameters.first(where: { $0.name == "oauth_session_handle"})?.value ?? ""

        self.init(key: key, secret: secret, session: session)
    }
}

extension Token {

    /// the signature method for this token
    public var signatureMethod: Client.SignatureMethod {
        return .plaintext
    }

    /// the signature using this token
    public func signature(with consumerSecret: String) -> String {
        switch signatureMethod {
        case .plaintext:
            return "\(consumerSecret)&\(secret)"
        }
    }
}
