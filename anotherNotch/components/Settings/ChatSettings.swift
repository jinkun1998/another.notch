import Defaults
import SwiftUI
import WebKit

struct ChatSettings: View {
    @Default(.chatEnabled) private var chatEnabled
    @Default(.chatShowNotificationsInNotch) private var showNotifications
    @Default(.chatPlaySound) private var playSound
    @ObservedObject private var chatManager = ChatManager.shared
    @State private var showingClearConfirmation = false
    @State private var clearedDataNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                Section {
                    Defaults.Toggle("Enable Chat in Notch", key: .chatEnabled)
                        .onChange(of: chatEnabled) { _, newValue in
                            if newValue {
                                FeatureModuleRegistry.shared.install(.chat)
                            }
                        }

                    Defaults.Toggle("Show message previews in notch", key: .chatShowNotificationsInNotch)
                        .disabled(!chatEnabled)

                    Defaults.Toggle("Play notification sound", key: .chatPlaySound)
                        .disabled(!chatEnabled)
                }

                Section("Supported Services") {
                    ForEach(ChatService.allCases) { service in
                        HStack {
                            Image(systemName: service.iconName)
                                .foregroundStyle(Color(nsColor: service.accentColor))
                                .frame(width: 20)
                            Text(service.rawValue)
                            Spacer()
                            Text(service.url.host ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Session & Data") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Chat Sessions")
                                .font(.body)
                            Text("Logs out of all messaging accounts and deletes cached data.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear Data", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog(
            "Clear all chat website data?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Data & Sign Out", role: .destructive) {
                chatManager.clearData {
                    clearedDataNotice = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove cookies, stored logins, and offline cache for Telegram, WhatsApp, Discord, Slack, and Messenger.")
        }
    }
}
