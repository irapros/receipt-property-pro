import SwiftUI

@main
struct SJTReceiptScannerApp: App {
    @StateObject private var settings = AppSettings.load()
    @StateObject private var processor = ReceiptProcessor()
    @StateObject private var dropboxService = DropboxService()

    var body: some Scene {
        WindowGroup {
            Group {
                if settings.hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(settings)
            .environmentObject(processor)
            .environmentObject(dropboxService)
            .onAppear {
                // Wire up processor with services
                processor.settings = settings
                processor.dropboxService = dropboxService
                processor.refreshAIService()
            }
            .onChange(of: settings.aiProvider) { _, _ in
                processor.refreshAIService()
            }
            .onChange(of: settings.claudeAPIKey) { _, _ in
                processor.refreshAIService()
            }
            .onChange(of: settings.openaiAPIKey) { _, _ in
                processor.refreshAIService()
            }
            .onChange(of: settings.geminiAPIKey) { _, _ in
                processor.refreshAIService()
            }
            .onOpenURL { url in
                // Handle Dropbox OAuth callback
                guard url.scheme == "receiptpropertypro",
                      url.host == "oauth" else { return }
                Task {
                    try? await dropboxService.handleCallback(url)
                }
            }
        }
    }
}
