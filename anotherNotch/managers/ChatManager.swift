import AppKit
import Foundation
import WebKit
import Combine
import Defaults

enum ChatService: String, CaseIterable, Identifiable, Codable {
    case telegram = "Telegram"
    case whatsapp = "WhatsApp"
    case messenger = "Messenger"
    case discord = "Discord"
    case slack = "Slack"

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .telegram:
            return URL(string: "https://web.telegram.org/a/")!
        case .whatsapp:
            return URL(string: "https://web.whatsapp.org/")!
        case .messenger:
            return URL(string: "https://www.messenger.com/")!
        case .discord:
            return URL(string: "https://discord.com/app")!
        case .slack:
            return URL(string: "https://app.slack.com/client")!
        }
    }

    var iconName: String {
        switch self {
        case .telegram:
            return "paperplane.fill"
        case .whatsapp:
            return "phone.bubble.fill"
        case .messenger:
            return "bubble.right.fill"
        case .discord:
            return "gamecontroller.fill"
        case .slack:
            return "number"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .telegram:
            return NSColor(red: 0.16, green: 0.63, blue: 0.95, alpha: 1.0)
        case .whatsapp:
            return NSColor(red: 0.15, green: 0.83, blue: 0.44, alpha: 1.0)
        case .messenger:
            return NSColor(red: 0.0, green: 0.52, blue: 1.0, alpha: 1.0)
        case .discord:
            return NSColor(red: 0.35, green: 0.4, blue: 0.95, alpha: 1.0)
        case .slack:
            return NSColor(red: 0.89, green: 0.11, blue: 0.45, alpha: 1.0)
        }
    }
}

struct ChatNotificationItem: Identifiable, Equatable {
    let id = UUID()
    let service: ChatService
    let title: String
    let body: String
    let timestamp: Date
}

final class ChatManager: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let shared = ChatManager()

    @Published var activeService: ChatService {
        didSet {
            Defaults[.chatSelectedService] = activeService.rawValue
            unreadCounts[activeService] = 0
        }
    }

    @Published var unreadCounts: [ChatService: Int] = [:]
    @Published var latestNotification: ChatNotificationItem?

    var unreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    private var webViews: [ChatService: WKWebView] = [:]
    private let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    override private init() {
        let saved = Defaults[.chatSelectedService]
        self.activeService = ChatService(rawValue: saved) ?? .telegram
        super.init()
    }

    func preloadActiveService() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            _ = self.getOrCreateWebView(for: self.activeService)
        }
    }

    @MainActor
    func getOrCreateWebView(for service: ChatService) -> WKWebView {
        if let existing = webViews[service] {
            return existing
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let scriptSource = """
        (function() {
            if (window.__notchChatInjected) return;
            window.__notchChatInjected = true;
            window.__notchServiceName = "\(service.rawValue)";

            try {
                const OrigNotification = window.Notification;
                window.Notification = function(title, options) {
                    try {
                        window.webkit.messageHandlers.notchNotification.postMessage({
                            service: window.__notchServiceName || '',
                            title: String(title || ''),
                            body: String((options && options.body) || ''),
                            tag: String((options && options.tag) || '')
                        });
                    } catch(e) {}
                    return {
                        close: function() {},
                        addEventListener: function() {},
                        removeEventListener: function() {},
                        dispatchEvent: function() { return false; }
                    };
                };
                window.Notification.permission = 'granted';
                window.Notification.requestPermission = function(cb) {
                    if (cb) cb('granted');
                    return Promise.resolve('granted');
                };
            } catch(e) {}

            try {
                if (window.ServiceWorkerRegistration && window.ServiceWorkerRegistration.prototype.showNotification) {
                    window.ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                        try {
                            window.webkit.messageHandlers.notchNotification.postMessage({
                                service: window.__notchServiceName || '',
                                title: String(title || ''),
                                body: String((options && options.body) || ''),
                                tag: String((options && options.tag) || '')
                            });
                        } catch(e) {}
                        return Promise.resolve();
                    };
                }
            } catch(e) {}

            let lastCount = -1;
            function checkTitleBadge() {
                try {
                    const title = document.title || '';
                    const match = title.match(/\\((\\d+)\\)/);
                    let count = 0;
                    if (match) {
                        count = parseInt(match[1], 10);
                    } else if (title.startsWith('*') || title.startsWith('•')) {
                        count = 1;
                    }
                    if (count !== lastCount) {
                        lastCount = count;
                        window.webkit.messageHandlers.notchBadge.postMessage({
                            service: window.__notchServiceName || '',
                            count: count
                        });
                    }
                } catch(e) {}
            }

            const titleElem = document.querySelector('title');
            if (titleElem) {
                new MutationObserver(checkTitleBadge).observe(titleElem, { subtree: true, characterData: true, childList: true });
            } else if (document.head) {
                new MutationObserver(checkTitleBadge).observe(document.head, { subtree: true, characterData: true, childList: true });
            }
            setInterval(checkTitleBadge, 2000);
        })();
        """

        let userScript = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        )
        config.userContentController.addUserScript(userScript)
        config.userContentController.add(self, name: "notchNotification")
        config.userContentController.add(self, name: "notchBadge")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = defaultUserAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        webView.load(URLRequest(url: service.url))
        webViews[service] = webView
        return webView
    }

    func reloadCurrent() {
        webViews[activeService]?.reload()
    }

    func goBack() {
        if webViews[activeService]?.canGoBack == true {
            webViews[activeService]?.goBack()
        }
    }

    func goForward() {
        if webViews[activeService]?.canGoForward == true {
            webViews[activeService]?.goForward()
        }
    }

    func clearData(completion: @escaping () -> Void) {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            DispatchQueue.main.async {
                self?.webViews.removeAll()
                self?.unreadCounts.removeAll()
                completion()
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        let serviceRaw = dict["service"] as? String ?? ""
        let service = ChatService(rawValue: serviceRaw) ?? activeService

        if message.name == "notchNotification" {
            let title = (dict["title"] as? String) ?? ""
            let body = (dict["body"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.handleNotification(service: service, title: title, body: body)
            }
        } else if message.name == "notchBadge" {
            let count = (dict["count"] as? Int) ?? 0
            DispatchQueue.main.async { [weak self] in
                self?.handleBadge(service: service, count: count)
            }
        }
    }

    @MainActor
    private func handleNotification(service: ChatService, title: String, body: String) {
        guard !title.isEmpty || !body.isEmpty else { return }
        let cleanTitle = title.isEmpty ? service.rawValue : title
        unreadCounts[service, default: 0] += 1
        latestNotification = ChatNotificationItem(service: service, title: cleanTitle, body: body, timestamp: Date())

        guard Defaults[.chatShowNotificationsInNotch] else { return }

        if Defaults[.chatPlaySound] {
            AudioPlayer().play(fileName: "Knock", fileExtension: "caf")
        }
        HapticFeedback.perform(.generic)

        let coordinator = AnotherNotchViewCoordinator.shared
        coordinator.toggleExpandingView(
            status: true,
            type: .chatNotification,
            title: cleanTitle,
            subtitle: body,
            icon: service.iconName
        )
    }

    @MainActor
    private func handleBadge(service: ChatService, count: Int) {
        unreadCounts[service] = count
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            if !isInternalChatURL(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    private func isInternalChatURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host.contains("telegram.org")
            || host.contains("whatsapp.com")
            || host.contains("whatsapp.net")
            || host.contains("messenger.com")
            || host.contains("facebook.com")
            || host.contains("discord.com")
            || host.contains("discordapp.com")
            || host.contains("slack.com")
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.grant)
    }
}
