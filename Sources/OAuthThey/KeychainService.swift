//
//  KeychainService.swift
//  PlinthKit
//
//  Created by Nate Rivard on 6/11/19.
//

import Combine
import Foundation
import Security

protocol KeychainServicing {
    func get<T: Codable>(key: String) throws -> T
    func set<T: Codable>(_ value: T, key: String) throws
    func remove(key: String)
}

/// lightweight object that wraps only the keychain access that is necessary to store our token
struct KeychainService: KeychainServicing {

    enum Error: Swift.Error {
        case unknown
        case resultMissing
        case resultNotData
        case unexpectedType

        /// a keychain originated error occurred and contains the underlying keychain code
        case keychain(OSStatus)
    }

    typealias Query = [CFString: CFTypeRef]

    var service: String

    /// configured JSON decoder
    let decoder: JSONDecoder

    /// configured JSON encoder
    let encoder: JSONEncoder

    init(service: String, decoder: JSONDecoder = JSONDecoder(), encoder: JSONEncoder = JSONEncoder()) {
        self.service = service
        self.decoder = decoder
        self.encoder = encoder
    }

    /// retrieves the `Codable` type at the given key
    func get<T: Codable>(key: String) throws -> T {
        var query = self.query(key: key)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = kCFBooleanTrue

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw Error.resultNotData }

            return try decoder.decode(T.self, from: data)
        case errSecItemNotFound:
            throw Error.resultMissing
        default:
            throw Error.keychain(status)
        }
    }

    /// adds or updates the `Codable` type at the given key
    func set<T: Codable>(_ value: T, key: String) throws {
        let data = try encoder.encode(value)

        // first we do a fetch to see if this object exists or not. Adds =/= updates.
        let result = try? get(key: key) as T
        let shouldAdd = result == nil

        let status: OSStatus
        if shouldAdd {
            let attributes = self.attributes(value: data).merging(self.query(key: key), uniquingKeysWith: { $1 })
            status = SecItemAdd(attributes as CFDictionary, nil)
        } else {
            // if it already exists, update the item by finding the match and setting our new attributes on it
            let query = self.query(key: key)
            let attributes = self.attributes(value: data)

            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }

        if status != errSecSuccess {
            throw Error.keychain(status)
        }
    }

    /// removes the value at the given key
    func remove(key: String) {
        let query = self.query(key: key)

        // there's not much we can do if it fails
        let _ = SecItemDelete(query as CFDictionary)
    }
}

extension KeychainService {

    private func query(key: String) -> Query {
        var query: Query = [:]

        query[kSecClass] = kSecClassGenericPassword
        query[kSecAttrSynchronizable] = kSecAttrSynchronizableAny
        query[kSecAttrService] = service as CFString
        query[kSecAttrAccount] = key as CFString

        return query
    }

    private func attributes(value: Data) -> Query {
        var attributes: Query = [:]

        attributes[kSecValueData] = value as CFData
        attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
        attributes[kSecAttrSynchronizable] = kCFBooleanFalse

        return attributes
    }
}
