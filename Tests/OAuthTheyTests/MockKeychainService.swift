//
//  File.swift
//  
//
//  Created by Nate Rivard on 05/07/2021.
//

@testable import OAuthThey

struct MockKeychainService: KeychainServicing {
    var storage: [String: Any] = [:]

    func get<T>(key: String) throws -> T where T : Decodable, T : Encodable {
        guard let item = storage[key] as? T else {
            throw KeychainService.Error.resultMissing
        }
        return item
    }

    func set<T>(_ value: T, key: String) throws where T : Decodable, T : Encodable {
        // do nothing
    }

    func remove(key: String) {
        // do nothing
    }
}
