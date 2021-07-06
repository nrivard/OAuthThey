//
//  File.swift
//  
//
//  Created by Nate Rivard on 05/07/2021.
//

@testable import OAuthThey
import Foundation

final class MockKeychainService: KeychainServicing {
    var storage: [String: Data] = [:]

    func get<T>(key: String) throws -> T where T : Decodable, T : Encodable {
        guard let data = storage[key] else {
            throw KeychainService.Error.resultMissing
        }

        let item = try JSONDecoder().decode(T.self, from: data)

        return item
    }

    func set<T>(_ value: T, key: String) throws where T : Decodable, T : Encodable {
        storage[key] = try JSONEncoder().encode(value)
    }

    func remove(key: String) {
        storage.removeValue(forKey: key)
    }
}
