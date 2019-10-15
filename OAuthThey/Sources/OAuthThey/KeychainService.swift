//
//  KeychainService.swift
//  PlinthKit
//
//  Created by Nate Rivard on 6/11/19.
//

import Combine
import Foundation
import Security

/// lightweight object that wraps only keychain access that is necessary to store our token
final class KeychainService {

    enum Error: Swift.Error {
        case unknown
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

    /// retrieves the NSCoding type at the given key
    func get<T: Codable>(key: String) throws -> T? {
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
            return nil
        default:
            throw Error.keychain(status)
        }
    }

    /// adds or updates the NSCoding type at the given key
    func set<T: Codable>(_ value: T, key: String) throws {
        let data = try encoder.encode(value)

        // first we do a fetch to see if this object exists or not. Adds =/= updates.
        let result: T? = try get(key: key)
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
    func remove(key: String) throws {
        let query = self.query(key: key)

        let status = SecItemDelete(query as CFDictionary)
        switch status {
        case errSecSuccess, errSecMissingValue:
            return
        default:
            throw Error.unknown
        }
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
