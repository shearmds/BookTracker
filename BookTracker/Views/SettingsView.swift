import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("appTheme") private var themeName: String = AppTheme.ocean.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeName) ?? .ocean }
    private let columns = Array(repeating: GridItem(.flexible()), count: 6)

    @State private var syncCode = SyncService.shared.token
    @State private var linkCode = ""
    @State private var copied = false
    @State private var showLinkConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }

            Text("Theme")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AppTheme.allCases, id: \.self) { t in
                    Button { themeName = t.rawValue } label: {
                        ZStack {
                            Circle().fill(t.gradient).frame(width: 32, height: 32)
                            if t == theme {
                                Circle().strokeBorder(.white, lineWidth: 2).frame(width: 32, height: 32)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Sync")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Use this code on another device to share this library.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text(syncCode)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                Button(copied ? "Copied" : "Copy") {
                    copyToClipboard(syncCode)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
            }

            Text("Link another device")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("Paste a sync code", text: $linkCode)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                Button("Link") { showLinkConfirm = true }
                    .disabled(linkCode.trimmingCharacters(in: .whitespacesAndNewlines).count < 32)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 380, height: 440)
        .alert("Link this device?", isPresented: $showLinkConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Link") { linkDevice() }
        } message: {
            Text("This device's books will be merged into the library for that code, and both devices will then stay in sync.")
        }
    }

    private func linkDevice() {
        SyncService.shared.token = linkCode
        syncCode = SyncService.shared.token
        linkCode = ""
        Task { await SyncService.shared.syncNow(context: modelContext) }
    }

    private func copyToClipboard(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
