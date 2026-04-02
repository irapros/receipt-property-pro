import SwiftUI

/// Shows previously processed receipts
struct HistoryView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var dropboxService: DropboxService
    @State private var receipts: [Receipt] = []
    @State private var searchText = ""
    @State private var receiptToDelete: Receipt?
    @State private var showDeleteOptions = false

    var filteredReceipts: [Receipt] {
        if searchText.isEmpty { return receipts }
        return receipts.filter {
            $0.vendor.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText) ||
            propertyName(for: $0).localizedCaseInsensitiveContains(searchText) ||
            String(format: "%.2f", $0.amount).contains(searchText) ||
            String(format: "$%.2f", $0.amount).contains(searchText)
        }
    }

    var body: some View {
        List {
            if filteredReceipts.isEmpty {
                ContentUnavailableView(
                    "No Receipts Yet",
                    systemImage: "doc.text",
                    description: Text("Scan a receipt to get started")
                )
            } else {
                ForEach(filteredReceipts) { receipt in
                    ReceiptRowView(
                        receipt: receipt,
                        propertyName: propertyName(for: receipt),
                        categoryName: categoryName(for: receipt)
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            receiptToDelete = receipt
                            showDeleteOptions = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search receipts")
        .onAppear { loadReceipts() }
        .refreshable { loadReceipts() }
        .confirmationDialog(
            "Delete Receipt",
            isPresented: $showDeleteOptions,
            presenting: receiptToDelete
        ) { receipt in
            Button("Delete Everywhere", role: .destructive) {
                deleteReceipt(receipt, removeFromCSV: true)
            }
            Button("Clear from Device Only") {
                deleteReceipt(receipt, removeFromCSV: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: { receipt in
            Text("\(receipt.vendor) — $\(String(format: "%.2f", receipt.amount))\n\n\"Delete Everywhere\" removes from device AND expense log.\n\n\"Clear from Device Only\" removes from this screen but keeps it in the expense log and Dropbox.")
        }
    }

    private func loadReceipts() {
        receipts = FileManagerService.shared.loadReceipts()
            .sorted { ($0.expenseDate ?? $0.scanDate) > ($1.expenseDate ?? $1.scanDate) }
    }

    private func deleteReceipt(_ receipt: Receipt, removeFromCSV: Bool) {
        var allReceipts = FileManagerService.shared.loadReceipts()
        allReceipts.removeAll { $0.id == receipt.id }

        try? FileManagerService.shared.saveReceipts(allReceipts)

        if removeFromCSV {
            // Rebuild CSV without this entry and sync to Dropbox
            try? FileManagerService.shared.rebuildExpenseLog(
                from: allReceipts,
                properties: settings.properties
            )
            syncCSVToDropbox()
        }
        // If not removing from CSV, the expense log stays untouched

        loadReceipts()
    }

    private func syncCSVToDropbox() {
        guard dropboxService.isAuthenticated else { return }
        guard let csvData = try? Data(contentsOf: FileManagerService.shared.expenseLogURL) else { return }

        let basePath = settings.dropboxBasePath
        let csvPath = basePath.hasPrefix("/") ? basePath : "/\(basePath)"
        let csvDropboxPath = "\(csvPath)/\(settings.fullCSVFileName)"

        Task {
            do {
                try await dropboxService.uploadFile(data: csvData, dropboxPath: csvDropboxPath)
                print("[Dropbox] CSV synced after delete")
            } catch {
                print("[Dropbox] CSV sync after delete failed: \(error.localizedDescription)")
            }
        }
    }

    private func propertyName(for receipt: Receipt) -> String {
        guard let dest = receipt.destination else { return "" }
        switch dest {
        case .property(let propertyId, _):
            return settings.properties.first(where: { $0.id == propertyId })?.name ?? ""
        case .overhead:
            return "Overhead"
        }
    }

    private func categoryName(for receipt: Receipt) -> String {
        guard let dest = receipt.destination else { return "" }
        switch dest {
        case .property(_, let category):
            return category.rawValue
        case .overhead(let category):
            return category.rawValue
        }
    }
}

struct ReceiptRowView: View {
    let receipt: Receipt
    let propertyName: String
    let categoryName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.vendor.isEmpty ? "Unknown Vendor" : receipt.vendor)
                    .font(.headline)

                Text(receipt.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Property & category tag
                if !propertyName.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: propertyName == "Overhead" ? "building.2" : "house")
                            .font(.caption2)
                        Text(propertyName)
                            .font(.caption)
                            .fontWeight(.medium)
                        if !categoryName.isEmpty {
                            Text("·")
                                .font(.caption)
                            Text(categoryName)
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.blue)
                }

                Text(dateString)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "$%.2f", receipt.amount))
                    .font(.headline)
                    .foregroundStyle(receipt.amount > 0 ? .primary : .secondary)

                statusBadge
            }
        }
        .padding(.vertical, 2)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: receipt.expenseDate ?? receipt.scanDate)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch receipt.status {
        case .filed:
            Label("Filed", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .reviewed:
            Label("Reviewed", systemImage: "eye.fill")
                .font(.caption2)
                .foregroundStyle(.blue)
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        default:
            Label("Pending", systemImage: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }
}
