import SwiftUI

/// App configuration screen
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var dropboxService: DropboxService
    @State private var showAddProperty = false
    @State private var newPropertyName = ""
    @State private var dropboxAppKey = ""

    var body: some View {
        Form {
            // MARK: - Company / Branding
            Section {
                TextField("Company Name (optional)", text: $settings.companyName)
                    .autocapitalization(.words)
            } header: {
                Text("Company")
            } footer: {
                Text("Used as a prefix for your expense log filename. Leave blank for personal use.")
            }

            // MARK: - AI Provider
            Section {
                Picker("AI Provider", selection: $settings.aiProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }

                if settings.aiProvider != .none {
                    SecureField(settings.aiProvider.apiKeyPlaceholder, text: apiKeyBinding)
                        .textContentType(.password)
                        .autocapitalization(.none)

                    if let url = URL(string: settings.aiProvider.apiKeyURL) {
                        Link("Get API Key", destination: url)
                            .font(.caption)
                    }
                }

                Toggle("Use AI as OCR fallback", isOn: $settings.useAIFallback)
                Toggle("Auto-suggest category", isOn: $settings.autoSuggestCategory)
            } header: {
                Text("AI Assist")
            } footer: {
                if settings.aiProvider == .none {
                    Text("Uses Apple Vision only. Select an AI provider and add your own API key for better accuracy on hard-to-read receipts.")
                } else {
                    Text("Your API key is stored on-device only and used to call \(settings.aiProvider.displayName) when Vision OCR can't read the receipt clearly.")
                }
            }

            // MARK: - Dropbox
            Section {
                if dropboxService.isAuthenticated {
                    HStack {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Disconnect") {
                            dropboxService.disconnect()
                        }
                        .foregroundStyle(.red)
                    }
                } else {
                    SecureField("Dropbox App Key", text: $dropboxAppKey)
                        .autocapitalization(.none)
                    Button {
                        connectDropbox()
                    } label: {
                        Label("Connect to Dropbox", systemImage: "link")
                    }
                    .disabled(dropboxAppKey.isEmpty)
                }
            } header: {
                Text("Dropbox Sync")
            } footer: {
                Text(dropboxService.isAuthenticated
                     ? "Receipts will be uploaded to Dropbox automatically when filed."
                     : "Create an app at dropbox.com/developers and enter the App Key. Receipts are saved locally either way.")
            }

            // MARK: - File Storage
            Section {
                TextField("Dropbox Path", text: $settings.dropboxBasePath)
                    .font(.caption)
                    .autocapitalization(.none)

                Stepper("Tax Year: \(String(settings.taxYear))", value: $settings.taxYear, in: 2020...2030)

                TextField("CSV Filename", text: $settings.csvFileName)
                    .font(.caption)
                    .autocapitalization(.none)

                Text("Full name: \(settings.fullCSVFileName)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Storage")
            } footer: {
                Text("Base path in Dropbox where receipts are filed. The folder structure mirrors Property Specific Files/ and Overhead Expenses/.")
            }

            // MARK: - Properties
            Section {
                if settings.subscriptionTier == .free && settings.properties.count >= settings.subscriptionTier.maxProperties {
                    Label("Free plan: \(settings.subscriptionTier.maxProperties) properties max", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(settings.properties) { property in
                    HStack {
                        Text(property.name)
                        Spacer()
                        if property.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: "circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleProperty(property.id)
                    }
                }
                .onDelete { indexSet in
                    settings.properties.remove(atOffsets: indexSet)
                    settings.save()
                }

                Button {
                    if settings.subscriptionTier == .free && settings.properties.count >= settings.subscriptionTier.maxProperties {
                        // TODO: Show upgrade prompt
                    } else {
                        showAddProperty = true
                    }
                } label: {
                    Label("Add Property", systemImage: "plus")
                }
                .disabled(settings.subscriptionTier == .free && settings.properties.count >= settings.subscriptionTier.maxProperties)
            } header: {
                Text("Properties (\(settings.properties.filter { $0.isActive }.count) active)")
            } footer: {
                Text("Tap to toggle active/inactive. These match your Dropbox folder names under Property Specific Files/.")
            }

            // MARK: - Subscription
            Section {
                HStack {
                    Text("Plan")
                    Spacer()
                    Text(settings.subscriptionTier.rawValue)
                        .foregroundStyle(settings.subscriptionTier == .pro ? .blue : .secondary)
                        .fontWeight(settings.subscriptionTier == .pro ? .semibold : .regular)
                }

                if settings.subscriptionTier == .free {
                    HStack {
                        Text("Receipts this month")
                        Spacer()
                        Text("\(settings.receiptsThisMonth) / \(settings.subscriptionTier.maxReceiptsPerMonth)")
                            .foregroundStyle(.secondary)
                    }

                    // TODO: Add upgrade button linked to StoreKit
                    Button {
                        // Placeholder for StoreKit purchase flow
                    } label: {
                        Label("Upgrade to Pro", systemImage: "star.fill")
                    }
                    .tint(.blue)
                }
            } header: {
                Text("Subscription")
            } footer: {
                if settings.subscriptionTier == .free {
                    Text("Free: \(settings.subscriptionTier.maxProperties) properties, \(settings.subscriptionTier.maxReceiptsPerMonth) receipts/month. Pro unlocks unlimited properties, cloud filing, CSV export, and custom categories.")
                } else {
                    Text("You have full access to all features.")
                }
            }

            // MARK: - Data
            Section("Data") {
                Button {
                    exportCSV()
                } label: {
                    Label("Export Expense Log", systemImage: "square.and.arrow.up")
                }
                .disabled(settings.subscriptionTier == .free && !settings.subscriptionTier.hasCSVExport)

                let receiptCount = FileManagerService.shared.loadReceipts().count
                Text("\(receiptCount) receipts processed")
                    .foregroundStyle(.secondary)
            }

            // MARK: - About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("OCR Engine")
                    Spacer()
                    if settings.aiProvider != .none {
                        Text("Apple Vision + \(settings.aiProvider.displayName)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Apple Vision")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: settings.companyName) { _, _ in settings.save() }
        .onChange(of: settings.aiProvider) { _, _ in settings.save() }
        .onChange(of: settings.claudeAPIKey) { _, _ in settings.save() }
        .onChange(of: settings.openaiAPIKey) { _, _ in settings.save() }
        .onChange(of: settings.geminiAPIKey) { _, _ in settings.save() }
        .onChange(of: settings.useAIFallback) { _, _ in settings.save() }
        .onChange(of: settings.dropboxBasePath) { _, _ in settings.save() }
        .onChange(of: settings.autoSuggestCategory) { _, _ in settings.save() }
        .onChange(of: settings.taxYear) { _, _ in settings.save() }
        .onChange(of: settings.csvFileName) { _, _ in settings.save() }
        .alert("Add Property", isPresented: $showAddProperty) {
            TextField("Property name (e.g., 123 Main Street)", text: $newPropertyName)
            Button("Add") { addProperty() }
            Button("Cancel", role: .cancel) { newPropertyName = "" }
        } message: {
            Text("Enter the property name exactly as it appears in your folder structure.")
        }
    }

    // MARK: - Helpers

    /// Binding for the active provider's API key
    private var apiKeyBinding: Binding<String> {
        switch settings.aiProvider {
        case .none: return .constant("")
        case .claude: return $settings.claudeAPIKey
        case .openai: return $settings.openaiAPIKey
        case .gemini: return $settings.geminiAPIKey
        }
    }

    private func toggleProperty(_ id: UUID) {
        if let idx = settings.properties.firstIndex(where: { $0.id == id }) {
            settings.properties[idx].isActive.toggle()
            settings.save()
        }
    }

    private func addProperty() {
        guard !newPropertyName.isEmpty else { return }
        settings.properties.append(Property(name: newPropertyName))
        settings.save()
        newPropertyName = ""
    }

    private func connectDropbox() {
        UserDefaults.standard.set(dropboxAppKey, forKey: "dropbox_app_key")
        guard let url = dropboxService.authorizationURL(appKey: dropboxAppKey) else { return }
        UIApplication.shared.open(url)
    }

    private func exportCSV() {
        let url = FileManagerService.shared.expenseLogURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
