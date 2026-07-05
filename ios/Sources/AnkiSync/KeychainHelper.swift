public import Foundation
import Security

public enum KeychainHelper: Sendable {
    private static let service = "com.ankiapp.sync"
    private static let openAIService = "com.ankountant.openai"
    private static let hostKeyAccount = "sync-host-key"
    private static let usernameAccount = "sync-username"
    private static let endpointAccount = "sync-endpoint"
    private static let currentEndpointAccount = "sync-current-endpoint"
    private static let openAIAPIKeyAccount = "openai-api-key"

    // MARK: - Host Key

    public static func saveHostKey(_ key: String) throws {
        try save(account: hostKeyAccount, value: key)
    }

    public static func loadHostKey() -> String? {
        load(account: hostKeyAccount)
    }

    public static func deleteHostKey() {
        delete(account: hostKeyAccount)
    }

    // MARK: - Username

    public static func saveUsername(_ username: String) throws {
        try save(account: usernameAccount, value: username)
    }

    public static func loadUsername() -> String? {
        load(account: usernameAccount)
    }

    public static func deleteUsername() {
        delete(account: usernameAccount)
    }

    // MARK: - Endpoint

    public static func saveEndpoint(_ url: String) throws {
        try save(account: endpointAccount, value: url)
    }

    public static func loadEndpoint() -> String? {
        load(account: endpointAccount)
    }

    public static func deleteEndpoint() {
        delete(account: endpointAccount)
    }

    // MARK: - Current Endpoint
    //
    // Last shard URL the sync server redirected us to. AnkiWeb pins
    // upload/download to a specific shard (e.g. sync5.ankiweb.net) and only
    // emits the redirect on the meta path, so subsequent FullUploadOrDownload
    // calls must already point at the shard. Kept separate from the
    // user-configured endpoint so changing servers can reset it cleanly.

    public static func saveCurrentEndpoint(_ url: String) throws {
        try save(account: currentEndpointAccount, value: url)
    }

    public static func loadCurrentEndpoint() -> String? {
        load(account: currentEndpointAccount)
    }

    public static func deleteCurrentEndpoint() {
        delete(account: currentEndpointAccount)
    }

    public static func saveOpenAIAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw KeychainError.missingOpenAIAPIKey
        }
        try save(serviceName: openAIService, account: openAIAPIKeyAccount, value: trimmedKey)
    }

    public static func loadOpenAIAPIKey() throws -> String? {
        try load(serviceName: openAIService, account: openAIAPIKeyAccount)
    }

    public static func requireOpenAIAPIKey() throws -> String {
        guard let key = try loadOpenAIAPIKey()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else {
            throw KeychainError.missingOpenAIAPIKey
        }
        return key
    }

    public static func deleteOpenAIAPIKey() throws {
        try delete(serviceName: openAIService, account: openAIAPIKeyAccount)
    }

    // MARK: - Internal

    private static func save(account: String, value: String) throws {
        try save(serviceName: service, account: account, value: value)
    }

    private static func save(serviceName: String, account: String, value: String) throws {
        let data = Data(value.utf8)
        try delete(serviceName: serviceName, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private static func load(account: String) -> String? {
        try? load(serviceName: service, account: account)
    }

    private static func load(serviceName: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else {
            throw KeychainError.loadFailed(status)
        }
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidStringData
        }
        return value
    }

    private static func delete(account: String) {
        try? delete(serviceName: service, account: account)
    }

    private static func delete(serviceName: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

public enum KeychainError: Error, LocalizedError, Sendable {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case invalidStringData
    case missingOpenAIAPIKey

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Keychain save failed with status \(status)."
        case .loadFailed(let status):
            "Keychain load failed with status \(status)."
        case .deleteFailed(let status):
            "Keychain delete failed with status \(status)."
        case .invalidStringData:
            "Keychain item could not be decoded as text."
        case .missingOpenAIAPIKey:
            "OpenAI API key is missing."
        }
    }
}
