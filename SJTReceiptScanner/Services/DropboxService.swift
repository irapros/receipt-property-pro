import Foundation
import UIKit
import CryptoKit

// MARK: - Dropbox OAuth & File Upload Service

/// Handles Dropbox OAuth 2.0 PKCE flow and file operations
/// Uses Dropbox HTTP API directly — no SwiftyDropbox SDK dependency
final class DropboxService: ObservableObject {

    // MARK: - Published State
    @Published var isAuthenticated = false
    @Published var isUploading = false
    @Published var uploadProgress: String = ""

    // MARK: - OAuth Constants
    /// Register your app at https://www.dropbox.com/developers/apps
    /// Set redirect URI to: receiptpropertypro://oauth/callback
    static let appKey = ""  // User sets in Settings
    static let redirectURI = "receiptpropertypro://oauth/callback"

    private let authURL = "https://www.dropbox.com/oauth2/authorize"
    private let tokenURL = "https://api.dropboxapi.com/oauth2/token"
    private let uploadURL = "https://content.dropboxapi.com/2/files/upload"
    private let createFolderURL = "https://api.dropboxapi.com/2/files/create_folder_v2"
    private let listFolderURL = "https://api.dropboxapi.com/2/files/list_folder"

    // MARK: - Stored Tokens
    private var accessToken: String? {
        get { KeychainHelper.load(key: "dropbox_access_token") }
        set {
            if let v = newValue { KeychainHelper.save(key: "dropbox_access_token", value: v) }
            else { KeychainHelper.delete(key: "dropbox_access_token") }
        }
    }

    private var refreshToken: String? {
        get { KeychainHelper.load(key: "dropbox_refresh_token") }
        set {
            if let v = newValue { KeychainHelper.save(key: "dropbox_refresh_token", value: v) }
            else { KeychainHelper.delete(key: "dropbox_refresh_token") }
        }
    }

    private var tokenExpiry: Date? {
        get {
            guard let str = KeychainHelper.load(key: "dropbox_token_expiry") else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }
        set {
            if let d = newValue {
                KeychainHelper.save(key: "dropbox_token_expiry", value: ISO8601DateFormatter().string(from: d))
            } else {
                KeychainHelper.delete(key: "dropbox_token_expiry")
            }
        }
    }

    // PKCE verifier stored during auth flow
    private var codeVerifier: String?

    init() {
        isAuthenticated = accessToken != nil
    }

    // MARK: - OAuth 2.0 PKCE Flow

    /// Generate the authorization URL for the user to open in Safari
    func authorizationURL(appKey: String) -> URL? {
        let verifier = generateCodeVerifier()
        codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: appKey),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "token_access_type", value: "offline"),
        ]
        return components.url
    }

    /// Handle the OAuth callback URL and exchange the code for tokens
    func handleCallback(_ url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let verifier = codeVerifier else {
            throw DropboxError.invalidCallback
        }

        let appKey = UserDefaults.standard.string(forKey: "dropbox_app_key") ?? Self.appKey

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "code=\(code)",
            "grant_type=authorization_code",
            "client_id=\(appKey)",
            "redirect_uri=\(Self.redirectURI)",
            "code_verifier=\(verifier)",
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DropboxError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.access_token
        refreshToken = tokenResponse.refresh_token
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))

        await MainActor.run {
            isAuthenticated = true
        }
    }

    /// Refresh the access token using the stored refresh token
    private func refreshAccessToken() async throws {
        guard let refresh = refreshToken else { throw DropboxError.notAuthenticated }

        let appKey = UserDefaults.standard.string(forKey: "dropbox_app_key") ?? Self.appKey

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refresh)",
            "client_id=\(appKey)",
        ].joined(separator: "&")

        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DropboxError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokenResponse.access_token
        if let newRefresh = tokenResponse.refresh_token {
            refreshToken = newRefresh
        }
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expires_in))
    }

    /// Get a valid access token, refreshing if expired
    private func validToken() async throws -> String {
        guard let token = accessToken else { throw DropboxError.notAuthenticated }

        if let expiry = tokenExpiry, Date() > expiry.addingTimeInterval(-60) {
            try await refreshAccessToken()
            return self.accessToken!
        }

        return token
    }

    func disconnect() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        Task { @MainActor in
            isAuthenticated = false
        }
    }

    // MARK: - File Operations

    /// Build a properly JSON-encoded Dropbox-API-Arg header value
    private func dropboxAPIArg(path: String) -> String {
        let args: [String: Any] = [
            "path": path,
            "mode": "overwrite",
            "autorename": false,
            "mute": false
        ]
        // JSONSerialization properly escapes special characters in the path
        guard let data = try? JSONSerialization.data(withJSONObject: args),
              let str = String(data: data, encoding: .utf8) else {
            // Fallback: manually escape quotes and backslashes
            let escaped = path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "{\"path\":\"\(escaped)\",\"mode\":\"overwrite\",\"autorename\":false,\"mute\":false}"
        }
        return str
    }

    /// Upload a file to Dropbox
    func uploadFile(data: Data, dropboxPath: String) async throws {
        let token = try await validToken()

        // Ensure path starts with /
        let normalizedPath = dropboxPath.hasPrefix("/") ? dropboxPath : "/\(dropboxPath)"

        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        request.setValue(dropboxAPIArg(path: normalizedPath), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data

        print("[Dropbox] Uploading to path: \(normalizedPath) (\(data.count) bytes)")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DropboxError.uploadFailed("No response")
        }

        let responseBody = String(data: responseData, encoding: .utf8) ?? "(no body)"
        print("[Dropbox] Response \(httpResponse.statusCode): \(responseBody.prefix(500))")

        switch httpResponse.statusCode {
        case 200:
            return  // Success
        case 401:
            // Token expired, try refresh and retry once
            try await refreshAccessToken()
            try await uploadFile(data: data, dropboxPath: normalizedPath)
        case 409:
            // Path not found — try creating parent folder then retry
            let folderPath = (normalizedPath as NSString).deletingLastPathComponent
            print("[Dropbox] Creating folder: \(folderPath)")
            try await createFolder(path: folderPath)
            try await uploadFileNoRetry(data: data, dropboxPath: normalizedPath)
        default:
            throw DropboxError.uploadFailed("HTTP \(httpResponse.statusCode): \(responseBody.prefix(200))")
        }
    }

    private func uploadFileNoRetry(data: Data, dropboxPath: String) async throws {
        let token = try await validToken()
        let normalizedPath = dropboxPath.hasPrefix("/") ? dropboxPath : "/\(dropboxPath)"

        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        request.setValue(dropboxAPIArg(path: normalizedPath), forHTTPHeaderField: "Dropbox-API-Arg")
        request.httpBody = data

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DropboxError.uploadFailed("No response on retry")
        }

        let responseBody = String(data: responseData, encoding: .utf8) ?? "(no body)"
        print("[Dropbox] Retry response \(httpResponse.statusCode): \(responseBody.prefix(500))")

        guard httpResponse.statusCode == 200 else {
            throw DropboxError.uploadFailed("Retry HTTP \(httpResponse.statusCode): \(responseBody.prefix(200))")
        }
    }

    /// Create a folder in Dropbox (ignores "already exists" errors)
    func createFolder(path: String) async throws {
        let token = try await validToken()
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"

        var request = URLRequest(url: URL(string: createFolderURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bodyString = "{\"path\":\"\(normalizedPath)\",\"autorename\":false}"
        request.httpBody = bodyString.data(using: .utf8)

        print("[Dropbox] Creating folder: \(normalizedPath)")

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return }

        let responseBody = String(data: responseData, encoding: .utf8) ?? ""
        print("[Dropbox] Create folder response \(httpResponse.statusCode): \(responseBody.prefix(300))")

        // 409 means folder already exists, which is fine
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 409 {
            throw DropboxError.folderCreationFailed
        }
    }

    /// Check if a path exists in Dropbox
    func pathExists(_ path: String) async throws -> Bool {
        let token = try await validToken()

        var request = URLRequest(url: URL(string: "https://api.dropboxapi.com/2/files/get_metadata")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["path": path]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        return httpResponse.statusCode == 200
    }

    /// Upload a receipt PDF to the correct Dropbox path
    func fileReceiptToDropbox(
        pdfData: Data,
        filename: String,
        destination: ExpenseDestination,
        properties: [Property],
        basePath: String,
        taxYear: Int
    ) async throws -> String {
        let folderPath = destination.dropboxPath(
            properties: properties,
            basePath: basePath,
            taxYear: taxYear
        )
        let fullPath = "\(folderPath)/\(filename)"

        await MainActor.run {
            isUploading = true
            uploadProgress = "Uploading \(filename)..."
        }

        defer {
            Task { @MainActor in
                isUploading = false
                uploadProgress = ""
            }
        }

        try await uploadFile(data: pdfData, dropboxPath: fullPath)
        return fullPath
    }

    // MARK: - PKCE Helpers

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - ExpenseDestination Dropbox Paths

extension ExpenseDestination {
    func dropboxPath(properties: [Property], basePath: String, taxYear: Int) -> String {
        let root = basePath.hasPrefix("/") ? basePath : "/\(basePath)"
        switch self {
        case .property(let propertyId, let category):
            let propertyName = properties.first(where: { $0.id == propertyId })?.name ?? "Unknown"
            return "\(root)/Property Specific Files/\(propertyName)/\(category.rawValue)"
        case .overhead(let category):
            return "\(root)/Overhead Expenses/\(category.rawValue)"
        }
    }
}

// MARK: - Token Response

private struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
    let scope: String?
    let uid: String?
    let account_id: String?
}

// MARK: - Errors

enum DropboxError: LocalizedError {
    case notAuthenticated
    case invalidCallback
    case tokenExchangeFailed
    case tokenRefreshFailed
    case uploadFailed(String)
    case folderCreationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not connected to Dropbox. Please sign in."
        case .invalidCallback: return "Invalid OAuth callback."
        case .tokenExchangeFailed: return "Failed to exchange authorization code."
        case .tokenRefreshFailed: return "Session expired. Please reconnect to Dropbox."
        case .uploadFailed(let detail): return "Upload failed: \(detail)"
        case .folderCreationFailed: return "Could not create folder in Dropbox."
        }
    }
}

// MARK: - Keychain Helper

/// Simple keychain wrapper for storing OAuth tokens securely
enum KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.receiptpropertypro",
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.receiptpropertypro",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.receiptpropertypro",
        ]
        SecItemDelete(query as CFDictionary)
    }
}
