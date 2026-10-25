import AppKit
import Foundation
import WebKit
import Combine
import Defaults

enum ChatServiceType: String, CaseIterable, Identifiable, Codable, Defaults.Serializable {
    case telegram = "Telegram"
    case whatsapp = "WhatsApp"
    case messenger = "Messenger"
    case instagram = "Instagram"
    case discord = "Discord"
    case slack = "Slack"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultURL: URL {
        switch self {
        case .telegram:
            return URL(string: "https://web.telegram.org/a/")!
        case .whatsapp:
            return URL(string: "https://web.whatsapp.org/")!
        case .messenger:
            return URL(string: "https://www.messenger.com/")!
        case .instagram:
            return URL(string: "https://www.instagram.com/direct/inbox/")!
        case .discord:
            return URL(string: "https://discord.com/app")!
        case .slack:
            return URL(string: "https://app.slack.com/client")!
        case .custom:
            return URL(string: "https://google.com")!
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
        case .instagram:
            return "camera.viewfinder"
        case .discord:
            return "gamecontroller.fill"
        case .slack:
            return "number"
        case .custom:
            return "globe"
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
        case .instagram:
            return NSColor(red: 0.88, green: 0.19, blue: 0.42, alpha: 1.0)
        case .discord:
            return NSColor(red: 0.35, green: 0.4, blue: 0.95, alpha: 1.0)
        case .slack:
            return NSColor(red: 0.89, green: 0.11, blue: 0.45, alpha: 1.0)
        case .custom:
            return NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
        }
    }
}

typealias ChatService = ChatServiceType

struct ChatInstance: Identifiable, Codable, Equatable, Hashable, Defaults.Serializable {
    var id: UUID
    var serviceType: ChatServiceType
    var name: String
    var customURLString: String?

    enum CodingKeys: String, CodingKey {
        case id, serviceType, name, customURLString
    }

    init(id: UUID = UUID(), serviceType: ChatServiceType, name: String? = nil, customURLString: String? = nil) {
        self.id = id
        self.serviceType = serviceType
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmedName?.isEmpty == false) ? trimmedName! : serviceType.rawValue
        self.customURLString = customURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.serviceType = try container.decodeIfPresent(ChatServiceType.self, forKey: .serviceType) ?? .telegram
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = decodedName.isEmpty ? self.serviceType.rawValue : decodedName
        self.customURLString = try container.decodeIfPresent(String.self, forKey: .customURLString)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serviceType, forKey: .serviceType)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(customURLString, forKey: .customURLString)
    }

    var displayName: String {
        name.isEmpty ? serviceType.rawValue : name
    }

    var url: URL {
        if let custom = customURLString, !custom.isEmpty, let parsed = URL(string: custom), parsed.scheme != nil {
            return parsed
        }
        return serviceType.defaultURL
    }

    var iconName: String {
        serviceType.iconName
    }

    var accentColor: NSColor {
        serviceType.accentColor
    }
}

struct ChatNotificationItem: Identifiable, Equatable {
    let id = UUID()
    let instanceId: UUID
    let serviceType: ChatServiceType
    let instanceName: String
    let title: String
    let body: String
    let timestamp: Date

    var service: ChatServiceType {
        serviceType
    }
}

final class ChatManager: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    static let shared = ChatManager()

    @Published var instances: [ChatInstance] = [] {
        didSet {
            Defaults[.chatInstances] = instances
        }
    }

    @Published var activeInstanceId: UUID {
        willSet {
            webViews[activeInstanceId]?.pauseAllMediaPlayback(completionHandler: nil)
        }
        didSet {
            Defaults[.chatActiveInstanceID] = activeInstanceId.uuidString
            unreadCounts[activeInstanceId] = 0
        }
    }

    @Published var unreadCounts: [UUID: Int] = [:]
    @Published var latestNotification: ChatNotificationItem?

    var activeInstance: ChatInstance? {
        instances.first { $0.id == activeInstanceId } ?? instances.first
    }

    var activeService: ChatServiceType {
        get { activeInstance?.serviceType ?? .telegram }
        set {
            if let match = instances.first(where: { $0.serviceType == newValue }) {
                activeInstanceId = match.id
            }
        }
    }

    var unreadCount: Int {
        unreadCounts.values.reduce(0, +)
    }

    private var webViews: [UUID: WKWebView] = [:]
    private let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    override private init() {
        var loaded = Defaults[.chatInstances]
        if loaded.isEmpty {
            loaded = [
                ChatInstance(id: UUID(uuidString: "967D8441-F236-48FC-99F2-3AF317CAD73A")!, serviceType: .telegram, name: "Telegram"),
                ChatInstance(id: UUID(uuidString: "CB69F377-25D0-4A4A-9570-838A2EB6F96D")!, serviceType: .whatsapp, name: "WhatsApp"),
                ChatInstance(id: UUID(uuidString: "6D656D41-E0DB-4250-AEC2-E8CAE1634D21")!, serviceType: .messenger, name: "Messenger"),
                ChatInstance(id: UUID(uuidString: "5E96A192-38B4-4D6F-9C81-79A5BB673412")!, serviceType: .instagram, name: "Instagram"),
                ChatInstance(id: UUID(uuidString: "48F6A38B-50AB-4E4B-B724-01AB4C6DB03A")!, serviceType: .discord, name: "Discord"),
                ChatInstance(id: UUID(uuidString: "7BDE24F5-58CC-4E07-8457-4362E1FD45D4")!, serviceType: .slack, name: "Slack")
            ]
        }

        var needsResave = false
        for i in 0..<loaded.count {
            let u = loaded[i].id.uuid
            let version = (u.6 & 0xF0) >> 4
            let variant = (u.8 & 0xC0) >> 6
            if version != 4 || variant != 2 {
                loaded[i].id = UUID()
                needsResave = true
            }
        }
        if needsResave {
            Defaults[.chatInstances] = loaded
        }

        self.instances = loaded

        let savedActive = Defaults[.chatActiveInstanceID]
        if let savedUUID = UUID(uuidString: savedActive), loaded.contains(where: { $0.id == savedUUID }) {
            self.activeInstanceId = savedUUID
        } else {
            self.activeInstanceId = loaded.first?.id ?? UUID()
        }

        super.init()
    }

    func preloadActiveService() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let active = self.activeInstance else { return }
            _ = self.getOrCreateWebView(for: active)
        }
    }

    func unloadWebView(for instanceId: UUID) {
        guard let wv = webViews.removeValue(forKey: instanceId) else { return }
        wv.stopLoading()
        wv.pauseAllMediaPlayback(completionHandler: nil)
        wv.navigationDelegate = nil
        wv.uiDelegate = nil
        wv.removeFromSuperview()
    }

    func unloadInactiveWebViews() {
        let inactiveIds = webViews.keys.filter { $0 != activeInstanceId }
        for id in inactiveIds {
            unloadWebView(for: id)
        }
    }

    func pauseAll() {
        for (_, wv) in webViews {
            wv.pauseAllMediaPlayback(completionHandler: nil)
        }
    }

    func moveInstance(from sourceId: UUID, to destinationId: UUID) {
        guard sourceId != destinationId,
              let sourceIndex = instances.firstIndex(where: { $0.id == sourceId }),
              let destIndex = instances.firstIndex(where: { $0.id == destinationId })
        else { return }
        var updated = instances
        let item = updated.remove(at: sourceIndex)
        updated.insert(item, at: destIndex)
        instances = updated
    }

    func moveInstanceUp(id: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == id }), index > 0 else { return }
        var updated = instances
        updated.swapAt(index, index - 1)
        instances = updated
    }

    func moveInstanceDown(id: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == id }), index < instances.count - 1 else { return }
        var updated = instances
        updated.swapAt(index, index + 1)
        instances = updated
    }

    @discardableResult
    func addInstance(serviceType: ChatServiceType, name: String? = nil, customURL: String? = nil) -> ChatInstance {
        let count = instances.filter { $0.serviceType == serviceType }.count
        let defaultName: String
        if let name = name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            defaultName = name
        } else if count == 0 {
            defaultName = serviceType.rawValue
        } else {
            defaultName = "\(serviceType.rawValue) \(count + 1)"
        }

        let newInstance = ChatInstance(
            id: UUID(),
            serviceType: serviceType,
            name: defaultName,
            customURLString: customURL
        )
        instances.append(newInstance)
        activeInstanceId = newInstance.id
        return newInstance
    }

    func duplicateInstance(id: UUID) {
        guard let source = instances.first(where: { $0.id == id }) else { return }
        let count = instances.filter { $0.serviceType == source.serviceType }.count
        let newName = "\(source.displayName) \(count + 1)"
        let copy = ChatInstance(
            id: UUID(),
            serviceType: source.serviceType,
            name: newName,
            customURLString: source.customURLString
        )
        instances.append(copy)
        activeInstanceId = copy.id
    }

    func updateInstance(_ updated: ChatInstance) {
        guard let index = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        let oldURL = instances[index].url
        instances[index] = updated
        if oldURL != updated.url, let wv = webViews[updated.id] {
            wv.load(URLRequest(url: updated.url))
        }
    }

    func removeInstance(id: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances.remove(at: index)
        webViews[id]?.stopLoading()
        webViews.removeValue(forKey: id)
        unreadCounts.removeValue(forKey: id)

        // Delete isolated persistent web data store from disk
        WKWebsiteDataStore.remove(forIdentifier: id) { _ in }

        if activeInstanceId == id {
            if let next = instances.first {
                activeInstanceId = next.id
            }
        }
    }

    @MainActor
    func getOrCreateWebView(for instance: ChatInstance) -> WKWebView {
        if let existing = webViews[instance.id] {
            return existing
        }

        let config = WKWebViewConfiguration()
        // Isolated persistent website data store per instance
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: instance.id)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let escapedName = instance.displayName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        (function() {
            if (window.__notchChatInjected) return;
            window.__notchChatInjected = true;
            window.__notchInstanceId = "\(instance.id.uuidString)";
            window.__notchServiceName = "\(escapedName)";

            function MockNotification(title, options) {
                try {
                    window.webkit.messageHandlers.notchNotification.postMessage({
                        instanceId: window.__notchInstanceId || '',
                        service: window.__notchServiceName || '',
                        title: String(title || ''),
                        body: String((options && options.body) || ''),
                        tag: String((options && options.tag) || '')
                    });
                } catch(e) {}
                this.title = title;
                this.options = options;
                this.close = function() {};
                this.addEventListener = function() {};
                this.removeEventListener = function() {};
                this.dispatchEvent = function() { return false; };
            }

            MockNotification.requestPermission = function(cb) {
                if (typeof cb === 'function') cb('granted');
                return Promise.resolve('granted');
            };

            try {
                Object.defineProperty(MockNotification, 'permission', {
                    get: function() { return 'granted'; },
                    configurable: true
                });
                Object.defineProperty(MockNotification, 'maxActions', {
                    get: function() { return 2; },
                    configurable: true
                });
                window.Notification = MockNotification;
            } catch(e) {
                window.Notification = MockNotification;
            }

            try {
                if (typeof ServiceWorkerRegistration !== 'undefined') {
                    ServiceWorkerRegistration.prototype.showNotification = function(title, options) {
                        try {
                            window.webkit.messageHandlers.notchNotification.postMessage({
                                instanceId: window.__notchInstanceId || '',
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
            let lastTitle = '';
            function checkTitleBadge() {
                try {
                    const rawTitle = document.title || '';
                    if (rawTitle === lastTitle) return;
                    lastTitle = rawTitle;

                    let count = 0;
                    const match = rawTitle.match(/\\((\\d+)\\)/);
                    if (match) {
                        count = parseInt(match[1], 10);
                    } else if (rawTitle.startsWith('*') || rawTitle.startsWith('•')) {
                        count = 1;
                    }

                    if (count !== lastCount) {
                        const isNew = (count > lastCount && lastCount >= 0);
                        lastCount = count;
                        window.webkit.messageHandlers.notchBadge.postMessage({
                            instanceId: window.__notchInstanceId || '',
                            count: count,
                            rawTitle: rawTitle,
                            isNew: isNew
                        });
                    }
                } catch(e) {}
            }

            function initTitleObserver() {
                const titleElem = document.querySelector('title');
                if (titleElem) {
                    new MutationObserver(checkTitleBadge).observe(titleElem, { subtree: true, characterData: true, childList: true });
                } else if (document.head) {
                    new MutationObserver(checkTitleBadge).observe(document.head, { subtree: true, characterData: true, childList: true });
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', initTitleObserver);
            } else {
                initTitleObserver();
            }
            setInterval(checkTitleBadge, 20000);
        })();
        """

        let userScript = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentStart,
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

        webView.load(URLRequest(url: instance.url))
        webViews[instance.id] = webView
        return webView
    }

    @MainActor
    func getOrCreateWebView(for service: ChatServiceType) -> WKWebView {
        if let match = instances.first(where: { $0.serviceType == service }) {
            return getOrCreateWebView(for: match)
        }
        let added = addInstance(serviceType: service)
        return getOrCreateWebView(for: added)
    }

    func reloadCurrent() {
        guard let id = activeInstance?.id else { return }
        webViews[id]?.reload()
    }

    func goBack() {
        guard let id = activeInstance?.id else { return }
        if webViews[id]?.canGoBack == true {
            webViews[id]?.goBack()
        }
    }

    func goForward() {
        guard let id = activeInstance?.id else { return }
        if webViews[id]?.canGoForward == true {
            webViews[id]?.goForward()
        }
    }

    func clearData(for instanceId: UUID? = nil, completion: @escaping () -> Void) {
        if let id = instanceId {
            webViews[id]?.stopLoading()
            webViews.removeValue(forKey: id)
            unreadCounts[id] = 0
            WKWebsiteDataStore.remove(forIdentifier: id) { _ in
                DispatchQueue.main.async {
                    completion()
                }
            }
        } else {
            for inst in instances {
                webViews[inst.id]?.stopLoading()
                WKWebsiteDataStore.remove(forIdentifier: inst.id) { _ in }
            }
            webViews.removeAll()
            unreadCounts.removeAll()
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any] else { return }
        let instanceIdStr = dict["instanceId"] as? String ?? ""
        let instanceId = UUID(uuidString: instanceIdStr) ?? activeInstanceId

        if message.name == "notchNotification" {
            let title = (dict["title"] as? String) ?? ""
            let body = (dict["body"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.handleNotification(instanceId: instanceId, title: title, body: body)
            }
        } else if message.name == "notchBadge" {
            let count = (dict["count"] as? Int) ?? 0
            let rawTitle = (dict["rawTitle"] as? String) ?? ""
            let isNew = (dict["isNew"] as? Bool) ?? false
            DispatchQueue.main.async { [weak self] in
                self?.handleBadge(instanceId: instanceId, count: count, rawTitle: rawTitle, isNew: isNew)
            }
        }
    }

    private var lastNotificationTime: [UUID: Date] = [:]

    @MainActor
    func handleNotification(instanceId: UUID, title: String, body: String) {
        guard let instance = instances.first(where: { $0.id == instanceId }) else { return }
        guard !title.isEmpty || !body.isEmpty else { return }

        // Throttle notifications per instance within 1.2s to prevent duplicates
        if let last = lastNotificationTime[instanceId], Date().timeIntervalSince(last) < 1.2 {
            return
        }
        lastNotificationTime[instanceId] = Date()

        let cleanTitle = title.isEmpty ? instance.displayName : title
        unreadCounts[instanceId, default: 0] += 1
        latestNotification = ChatNotificationItem(
            instanceId: instanceId,
            serviceType: instance.serviceType,
            instanceName: instance.displayName,
            title: cleanTitle,
            body: body,
            timestamp: Date()
        )

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
            subtitle: body.isEmpty ? "New message" : body,
            icon: instance.iconName
        )
    }

    @MainActor
    private func handleBadge(instanceId: UUID, count: Int, rawTitle: String, isNew: Bool) {
        unreadCounts[instanceId] = count
        if isNew && count > 0 {
            guard let instance = instances.first(where: { $0.id == instanceId }) else { return }
            var clean = rawTitle
            if let match = clean.range(of: #"^\\((\\d+)\\)\\s*"#, options: .regularExpression) {
                clean = String(clean[match.upperBound...])
            } else if clean.hasPrefix("*") || clean.hasPrefix("•") {
                clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

            let sender: String
            let snippet: String
            if clean.contains(":") {
                let parts = clean.split(separator: ":", maxSplits: 1).map(String.init)
                sender = parts[0].trimmingCharacters(in: .whitespaces)
                snippet = parts[1].trimmingCharacters(in: .whitespaces)
            } else if !clean.isEmpty && clean.lowercased() != instance.displayName.lowercased() && clean.lowercased() != instance.serviceType.rawValue.lowercased() {
                sender = clean
                snippet = "New message"
            } else {
                sender = instance.displayName
                snippet = "New message"
            }

            handleNotification(instanceId: instanceId, title: sender, body: snippet)
        }
    }

    @MainActor
    func testNotification() {
        guard let instance = activeInstance ?? instances.first else { return }
        handleNotification(
            instanceId: instance.id,
            title: instance.displayName,
            body: "Hello! This is a test notch notification."
        )
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            let instance = instances.first(where: { webViews[$0.id] == webView }) ?? activeInstance
            if let instance = instance, !isInternalChatURL(url, instance: instance) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    private func isInternalChatURL(_ url: URL, instance: ChatInstance) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if let instHost = instance.url.host?.lowercased(), host.contains(instHost) || instHost.contains(host) {
            return true
        }
        return host.contains("telegram.org")
            || host.contains("whatsapp.com")
            || host.contains("whatsapp.net")
            || host.contains("messenger.com")
            || host.contains("facebook.com")
            || host.contains("instagram.com")
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
