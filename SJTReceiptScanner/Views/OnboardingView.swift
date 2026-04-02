import SwiftUI

/// First-launch onboarding walkthrough
struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var dropboxService: DropboxService
    @State private var currentStep = 0
    @State private var dropboxAppKey = ""
    @State private var newPropertyName = ""

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<totalSteps, id: \.self) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            TabView(selection: $currentStep) {
                welcomeStep.tag(0)
                companyStep.tag(1)
                propertiesStep.tag(2)
                connectionsStep.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)

            // Navigation buttons
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button {
                        withAnimation { currentStep += 1 }
                    } label: {
                        Text("Next")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                } else {
                    Button {
                        finishOnboarding()
                    } label: {
                        Text("Get Started")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Welcome to\nReceipt Property Pro")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text("Scan receipts, categorize expenses by rental property, and file everything to the cloud automatically.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "camera.fill", color: .blue, text: "Scan receipts with your camera")
                featureRow(icon: "brain", color: .purple, text: "AI-powered data extraction")
                featureRow(icon: "building.2.fill", color: .green, text: "Organize by rental property")
                featureRow(icon: "icloud.and.arrow.up", color: .orange, text: "Auto-file to Dropbox")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Step 2: Company Name

    private var companyStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "building.2.crop.circle")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Your Company")
                .font(.title)
                .fontWeight(.bold)

            Text("If you manage properties under a company name, enter it below. This prefixes your expense log filename. Leave blank for personal use.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            TextField("Company Name (optional)", text: $settings.companyName)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.words)
                .padding(.horizontal, 40)

            if !settings.companyName.isEmpty {
                Text("CSV will be named: \(settings.fullCSVFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Step 3: Properties

    private var propertiesStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "house.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Your Properties")
                .font(.title)
                .fontWeight(.bold)

            Text("Add the rental properties you manage. Receipts will be filed into folders matching these names. You can always add more later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Add property input
            HStack {
                TextField("e.g., 123 Main Street", text: $newPropertyName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    addProperty()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .disabled(newPropertyName.isEmpty)
            }
            .padding(.horizontal, 40)

            // Current properties list
            if !settings.properties.isEmpty {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(settings.properties) { property in
                            HStack {
                                Image(systemName: "building.2.fill")
                                    .foregroundStyle(.blue)
                                Text(property.name)
                                Spacer()
                                Button {
                                    removeProperty(property.id)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(.red.opacity(0.6))
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.blue.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .padding(.horizontal, 40)
                }
                .frame(maxHeight: 200)
            }

            if settings.subscriptionTier == .free {
                Text("Free plan: up to \(settings.subscriptionTier.maxProperties) properties")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()
        }
    }

    // MARK: - Step 4: Connections

    private var connectionsStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            Text("Connect Your Services")
                .font(.title)
                .fontWeight(.bold)

            Text("Optional: connect Dropbox for automatic cloud filing, and add an AI provider for smarter receipt reading.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                // Dropbox
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Dropbox", systemImage: "externaldrive.fill")
                            .font(.headline)

                        if dropboxService.isAuthenticated {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        } else {
                            SecureField("Dropbox App Key", text: $dropboxAppKey)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .font(.subheadline)

                            TextField("Base folder path", text: $settings.dropboxBasePath)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .font(.subheadline)

                            Button {
                                connectDropbox()
                            } label: {
                                Text("Connect")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            .disabled(dropboxAppKey.isEmpty)
                        }
                    }
                }

                // AI Provider
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("AI Assist", systemImage: "brain")
                            .font(.headline)

                        Picker("Provider", selection: $settings.aiProvider) {
                            ForEach(AIProvider.allCases) { provider in
                                Text(provider.displayName).tag(provider)
                            }
                        }
                        .pickerStyle(.menu)

                        if settings.aiProvider != .none {
                            SecureField(settings.aiProvider.apiKeyPlaceholder, text: apiKeyBinding)
                                .textFieldStyle(.roundedBorder)
                                .autocapitalization(.none)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .padding(.horizontal, 32)

            Text("You can set these up later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Helpers

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }

    private var apiKeyBinding: Binding<String> {
        switch settings.aiProvider {
        case .none: return .constant("")
        case .claude: return $settings.claudeAPIKey
        case .openai: return $settings.openaiAPIKey
        case .gemini: return $settings.geminiAPIKey
        }
    }

    private func addProperty() {
        guard !newPropertyName.isEmpty else { return }
        if settings.subscriptionTier == .free && settings.properties.count >= settings.subscriptionTier.maxProperties {
            return
        }
        settings.properties.append(Property(name: newPropertyName))
        newPropertyName = ""
    }

    private func removeProperty(_ id: UUID) {
        settings.properties.removeAll { $0.id == id }
    }

    private func connectDropbox() {
        UserDefaults.standard.set(dropboxAppKey, forKey: "dropbox_app_key")
        guard let url = dropboxService.authorizationURL(appKey: dropboxAppKey) else { return }
        UIApplication.shared.open(url)
    }

    private func finishOnboarding() {
        settings.hasCompletedOnboarding = true
        settings.save()
    }
}
