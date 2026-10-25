import SwiftUI
import WebKit

struct ChatWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct ChatView: View {
    @ObservedObject private var chatManager = ChatManager.shared
    @State private var renamingInstance: ChatInstance?
    @State private var renameText: String = ""
    @State private var isShowingCustomAlert: Bool = false
    @State private var customServiceName: String = ""
    @State private var customServiceURL: String = "https://"

    var body: some View {
        VStack(spacing: 8) {
            // Service Selector Toolbar
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(chatManager.instances) { instance in
                            instanceButton(for: instance)
                        }

                        Menu {
                            ForEach(ChatServiceType.allCases) { type in
                                Button {
                                    if type == .custom {
                                        customServiceName = "Custom"
                                        customServiceURL = "https://"
                                        isShowingCustomAlert = true
                                    } else {
                                        chatManager.addInstance(serviceType: type)
                                    }
                                } label: {
                                    Label("Add \(type.rawValue)", systemImage: type.iconName)
                                }
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .menuStyle(.borderlessButton)
                        .frame(width: 22, height: 22)
                        .help("Add Chat Service")
                    }
                    .padding(.vertical, 1)
                }

                Spacer(minLength: 8)

                // Navigation & Browser Actions
                HStack(spacing: 4) {
                    Button {
                        chatManager.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Back")

                    Button {
                        chatManager.goForward()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Forward")

                    Button {
                        chatManager.reloadCurrent()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reload page")

                    if let active = chatManager.activeInstance {
                        Button {
                            NSWorkspace.shared.open(active.url)
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Open in browser")
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Webview Container
            if let active = chatManager.activeInstance {
                ChatWebViewRepresentable(webView: chatManager.getOrCreateWebView(for: active))
                    .id(active.id)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            } else {
                VStack(spacing: 12) {
                    Text("No chat services added.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Button("Add Telegram") {
                        chatManager.addInstance(serviceType: .telegram)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("Rename Account", isPresented: Binding(
            get: { renamingInstance != nil },
            set: { if !$0 { renamingInstance = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if var target = renamingInstance {
                    target.name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    chatManager.updateInstance(target)
                }
                renamingInstance = nil
            }
            Button("Cancel", role: .cancel) {
                renamingInstance = nil
            }
        }
        .alert("Add Custom Chat Service", isPresented: $isShowingCustomAlert) {
            TextField("Service Name", text: $customServiceName)
            TextField("URL", text: $customServiceURL)
            Button("Add") {
                chatManager.addInstance(
                    serviceType: .custom,
                    name: customServiceName,
                    customURL: customServiceURL
                )
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func instanceButton(for instance: ChatInstance) -> some View {
        let isSelected = chatManager.activeInstanceId == instance.id
        let unread = chatManager.unreadCounts[instance.id, default: 0]

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                chatManager.activeInstanceId = instance.id
            }
        } label: {
            HStack(spacing: 5) {
                ChatServiceIconView(icon: instance.iconName, size: 12)
                    .opacity(isSelected ? 1.0 : 0.6)

                Text(instance.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)

                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.white.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .fixedSize()
        .contextMenu {
            Button("Rename...") {
                renameText = instance.displayName
                renamingInstance = instance
            }
            Button("Duplicate Account") {
                chatManager.duplicateInstance(id: instance.id)
            }
            Button("Reload") {
                chatManager.getOrCreateWebView(for: instance).reload()
            }
            Button("Clear Session Data") {
                chatManager.clearData(for: instance.id) {}
            }
            Button("Unload from Memory") {
                chatManager.unloadWebView(for: instance.id)
            }
            Divider()
            if chatManager.instances.count > 1 {
                Button("Remove Service", role: .destructive) {
                    chatManager.removeInstance(id: instance.id)
                }
            }
        }
    }
}
