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
    public let key: String

    /// The OAuth token secret
    public let secret: String

    public init(key: String, secret: String) {
        self.key = key
        self.secret = secret
    }
}

extension Token {

    init?(components: [URLQueryItem]) {
        guard let key = components.first(where: { $0.name == "oauth_token"})?.value,
              let secret = components.first(where: { $0.name == "oauth_token_secret"})?.value
        else {
            return nil
        }

        self.init(key: key, secret: secret)
    }
}

extension Token {

    /// the signature method for this token
    var signatureMethod: Client.SignatureMethod {
        return .plaintext
    }

    /// the signature using this token
    func signature(with consumerSecret: String) -> String {
        switch signatureMethod {
        case .plaintext:
            return "\(consumerSecret)&\(secret)"
        }
    }
}
