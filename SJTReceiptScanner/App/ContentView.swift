import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var processor: ReceiptProcessor
    @State private var showScanner = false
    @State private var showDocScanner = false
    @State private var showReview = false
    @State private var showDocSave = false
    @State private var showLimitReached = false
    @State private var scannedDocImages: [UIImage] = []
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // MARK: - Scan Tab
            NavigationStack {
                VStack(spacing: 24) {
                    Spacer()

                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("Receipt Property Pro")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Scan receipts or documents with your camera")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    // Receipt Scanner Button
                    Button {
                        if settings.canScanReceipt {
                            showScanner = true
                        } else {
                            showLimitReached = true
                        }
                    } label: {
                        Label("Scan Receipt", systemImage: "camera.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)

                    // Document Scanner Button
                    Button {
                        showDocScanner = true
                    } label: {
                        Label("Scan Document", systemImage: "doc.viewfinder")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 40)

                    // Free tier usage indicator
                    if settings.subscriptionTier == .free {
                        Text("\(settings.receiptsThisMonth)/\(settings.subscriptionTier.maxReceiptsPerMonth) receipts this month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if processor.isProcessing {
                        ProgressView(processor.processingStep)
                            .padding()
                    }

                    if let error = processor.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }

                    Spacer()
                }
                .navigationTitle("Scan")
                .sheet(isPresented: $showScanner) {
                    DocumentScannerView { images in
                        showScanner = false
                        settings.incrementReceiptCount()
                        Task {
                            await processor.processImages(images)
                            if processor.currentReceipt != nil {
                                showReview = true
                            }
                        }
                    }
                }
                .sheet(isPresented: $showDocScanner) {
                    DocumentScannerView { images in
                        showDocScanner = false
                        scannedDocImages = images
                        if !images.isEmpty {
                            showDocSave = true
                        }
                    }
                }
                .sheet(isPresented: $showReview) {
                    if let receipt = processor.currentReceipt {
                        ReceiptReviewView(receipt: receipt)
                            .environmentObject(settings)
                            .environmentObject(processor)
                    }
                }
                .sheet(isPresented: $showDocSave) {
                    DocumentSaveView(images: scannedDocImages)
                        .environmentObject(settings)
                }
                .alert("Receipt Limit Reached", isPresented: $showLimitReached) {
                    Button("OK") {}
                    // TODO: Add upgrade button when StoreKit is integrated
                } message: {
                    Text("You've reached the free plan limit of \(settings.subscriptionTier.maxReceiptsPerMonth) receipts per month. Upgrade to Pro for unlimited scanning.")
                }
            }
            .tabItem {
                Label("Scan", systemImage: "camera.fill")
            }
            .tag(0)

            // MARK: - History Tab
            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "clock.fill")
            }
            .tag(1)

            // MARK: - Settings Tab
            NavigationStack {
                SettingsView()
                    .environmentObject(settings)
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}
