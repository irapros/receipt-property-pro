import Foundation

// MARK: - AI Provider Configuration

/// Supported AI providers for receipt analysis
enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case none = "None (Vision Only)"
    case claude = "Claude (Anthropic)"
    case openai = "OpenAI (GPT)"
    case gemini = "Google Gemini"

    var id: String { rawValue }

    /// Display name for the provider
    var displayName: String { rawValue }

    /// Placeholder text for the API key field
    var apiKeyPlaceholder: String {
        switch self {
        case .none: return ""
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        case .gemini: return "AIza..."
        }
    }

    /// URL where user can get an API key
    var apiKeyURL: String {
        switch self {
        case .none: return ""
        case .claude: return "https://console.anthropic.com"
        case .openai: return "https://platform.openai.com/api-keys"
        case .gemini: return "https://aistudio.google.com/apikey"
        }
    }
}

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable {
    case free = "Free"
    case pro = "Pro"

    var maxProperties: Int {
        switch self {
        case .free: return 2
        case .pro: return 999
        }
    }

    var maxReceiptsPerMonth: Int {
        switch self {
        case .free: return 10
        case .pro: return 999999
        }
    }

    var hasCloudFiling: Bool { self == .pro }
    var hasCSVExport: Bool { self == .pro }
    var hasCustomCategories: Bool { self == .pro }
}

// MARK: - App Settings

/// Persistent app configuration
class AppSettings: ObservableObject, Codable {

    // MARK: - Company / Branding
    @Published var companyName: String = ""
    @Published var appDisplayName: String = "Receipt Property Pro"

    // MARK: - AI Provider
    @Published var aiProvider: AIProvider = .none
    @Published var claudeAPIKey: String = ""
    @Published var openaiAPIKey: String = ""
    @Published var geminiAPIKey: String = ""
    @Published var useAIFallback: Bool = true

    // MARK: - Cloud Storage
    @Published var dropboxBasePath: String = ""
    @Published var dropboxConnected: Bool = false

    // MARK: - Filing
    @Published var autoSuggestCategory: Bool = true
    @Published var taxYear: Int = Calendar.current.component(.year, from: Date())
    @Published var csvFileName: String = "Expense_Log"

    // MARK: - Properties
    @Published var properties: [Property] = []

    // MARK: - Subscription
    @Published var subscriptionTier: SubscriptionTier = .free
    @Published var receiptsThisMonth: Int = 0
    @Published var receiptCountResetDate: Date = Date()

    // MARK: - Onboarding
    @Published var hasCompletedOnboarding: Bool = false

    /// The active API key for the selected provider
    var activeAPIKey: String {
        switch aiProvider {
        case .none: return ""
        case .claude: return claudeAPIKey
        case .openai: return openaiAPIKey
        case .gemini: return geminiAPIKey
        }
    }

    /// Whether AI assist is available (provider selected + key entered)
    var isAIAvailable: Bool {
        aiProvider != .none && !activeAPIKey.isEmpty && useAIFallback
    }

    /// Check if user can scan more receipts this month
    var canScanReceipt: Bool {
        // Reset counter if new month
        let calendar = Calendar.current
        if !calendar.isDate(receiptCountResetDate, equalTo: Date(), toGranularity: .month) {
            return true // Will be reset on next scan
        }
        return subscriptionTier == .pro || receiptsThisMonth < subscriptionTier.maxReceiptsPerMonth
    }

    /// Increment receipt count, resetting if new month
    func incrementReceiptCount() {
        let calendar = Calendar.current
        if !calendar.isDate(receiptCountResetDate, equalTo: Date(), toGranularity: .month) {
            receiptsThisMonth = 0
            receiptCountResetDate = Date()
        }
        receiptsThisMonth += 1
        save()
    }

    /// The CSV filename with company prefix
    var fullCSVFileName: String {
        if companyName.isEmpty {
            return "\(csvFileName).csv"
        }
        return "\(companyName)_\(csvFileName).csv"
    }

    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case companyName, appDisplayName
        case aiProvider, claudeAPIKey, openaiAPIKey, geminiAPIKey, useAIFallback
        case dropboxBasePath, dropboxConnected
        case autoSuggestCategory, taxYear, csvFileName
        case properties
        case subscriptionTier, receiptsThisMonth, receiptCountResetDate
        case hasCompletedOnboarding
    }

    init() {}

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        companyName = try c.decodeIfPresent(String.self, forKey: .companyName) ?? ""
        appDisplayName = try c.decodeIfPresent(String.self, forKey: .appDisplayName) ?? "Receipt Property Pro"
        aiProvider = try c.decodeIfPresent(AIProvider.self, forKey: .aiProvider) ?? .none
        claudeAPIKey = try c.decodeIfPresent(String.self, forKey: .claudeAPIKey) ?? ""
        openaiAPIKey = try c.decodeIfPresent(String.self, forKey: .openaiAPIKey) ?? ""
        geminiAPIKey = try c.decodeIfPresent(String.self, forKey: .geminiAPIKey) ?? ""
        useAIFallback = try c.decodeIfPresent(Bool.self, forKey: .useAIFallback) ?? true
        dropboxBasePath = try c.decodeIfPresent(String.self, forKey: .dropboxBasePath) ?? ""
        dropboxConnected = try c.decodeIfPresent(Bool.self, forKey: .dropboxConnected) ?? false
        autoSuggestCategory = try c.decodeIfPresent(Bool.self, forKey: .autoSuggestCategory) ?? true
        taxYear = try c.decodeIfPresent(Int.self, forKey: .taxYear) ?? Calendar.current.component(.year, from: Date())
        csvFileName = try c.decodeIfPresent(String.self, forKey: .csvFileName) ?? "Expense_Log"
        properties = try c.decodeIfPresent([Property].self, forKey: .properties) ?? []
        subscriptionTier = try c.decodeIfPresent(SubscriptionTier.self, forKey: .subscriptionTier) ?? .free
        receiptsThisMonth = try c.decodeIfPresent(Int.self, forKey: .receiptsThisMonth) ?? 0
        receiptCountResetDate = try c.decodeIfPresent(Date.self, forKey: .receiptCountResetDate) ?? Date()
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(companyName, forKey: .companyName)
        try c.encode(appDisplayName, forKey: .appDisplayName)
        try c.encode(aiProvider, forKey: .aiProvider)
        try c.encode(claudeAPIKey, forKey: .claudeAPIKey)
        try c.encode(openaiAPIKey, forKey: .openaiAPIKey)
        try c.encode(geminiAPIKey, forKey: .geminiAPIKey)
        try c.encode(useAIFallback, forKey: .useAIFallback)
        try c.encode(dropboxBasePath, forKey: .dropboxBasePath)
        try c.encode(dropboxConnected, forKey: .dropboxConnected)
        try c.encode(autoSuggestCategory, forKey: .autoSuggestCategory)
        try c.encode(taxYear, forKey: .taxYear)
        try c.encode(csvFileName, forKey: .csvFileName)
        try c.encode(properties, forKey: .properties)
        try c.encode(subscriptionTier, forKey: .subscriptionTier)
        try c.encode(receiptsThisMonth, forKey: .receiptsThisMonth)
        try c.encode(receiptCountResetDate, forKey: .receiptCountResetDate)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }

    // MARK: - Persistence
    private static let storageKey = "com.receiptpropertypro.settings"

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }
}
