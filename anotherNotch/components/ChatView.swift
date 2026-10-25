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

    var body: some View {
        VStack(spacing: 8) {
            // Service Selector Toolbar
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(ChatService.allCases) { service in
                            serviceButton(for: service)
                        }
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

                    Button {
                        NSWorkspace.shared.open(chatManager.activeService.url)
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
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Webview Container
            ChatWebViewRepresentable(webView: chatManager.getOrCreateWebView(for: chatManager.activeService))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func serviceButton(for service: ChatService) -> some View {
        let isSelected = chatManager.activeService == service
        let unread = chatManager.unreadCounts[service, default: 0]

        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                chatManager.activeService = service
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: service.iconName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color(nsColor: service.accentColor) : .secondary)

                Text(service.rawValue)
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
    }
}
