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
    var isMuted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, serviceType, name, customURLString, isMuted
    }

    init(id: UUID = UUID(), serviceType: ChatServiceType, name: String? = nil, customURLString: String? = nil, isMuted: Bool = false) {
        self.id = id
        self.serviceType = serviceType
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = (trimmedName?.isEmpty == false) ? trimmedName! : serviceType.rawValue
        self.customURLString = customURLString?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.serviceType = try container.decodeIfPresent(ChatServiceType.self, forKey: .serviceType) ?? .telegram
        let decodedName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.name = decodedName.isEmpty ? self.serviceType.rawValue : decodedName
        self.customURLString = try container.decodeIfPresent(String.self, forKey: .customURLString)
        self.isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(serviceType, forKey: .serviceType)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(customURLString, forKey: .customURLString)
        try container.encode(isMuted, forKey: .isMuted)
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

final class ChatWebView: WKWebView {
    @objc func _setHasActiveNowPlayingSession(_ val: Bool) {}
    @objc func _hasActiveNowPlayingSession() -> Bool { false }
    @objc func _nowPlayingMediaTitleAndArtist(_ completion: ((String?, String?) -> Void)?) {
        completion?(nil, nil)
    }
    @objc func _requestActiveNowPlayingSessionInfo(_ completion: ((Any?) -> Void)?) {
        completion?(nil)
    }
    @objc func _setNowPlayingMetadataObserver(_ block: Any?) {}
    @objc func _updateMediaPlaybackControlsManager() {}
    @objc func _wantsMediaPlaybackControlsView() -> Bool { false }
    @objc func _setWantsMediaPlaybackControlsView(_ val: Bool) {}
    @objc func _isPlayingAudio() -> Bool { false }
    @objc func _mediaMutedState() -> UInt64 { 1 }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if window?.isKeyWindow != true {
            window?.makeKeyAndOrderFront(nil)
        }
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let res = super.becomeFirstResponder()
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        if window?.isKeyWindow != true {
            window?.makeKeyAndOrderFront(nil)
        }
        return res
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
            if newValue != activeInstanceId {
                webViews[activeInstanceId]?.pauseAllMediaPlayback(completionHandler: nil)
            }
        }
        didSet {
            Defaults[.chatActiveInstanceID] = activeInstanceId.uuidString
            if unreadCounts[activeInstanceId] != 0 {
                unreadCounts[activeInstanceId] = 0
            }
            lastActiveTime[activeInstanceId] = Date()
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
    private let sharedProcessPool = WKProcessPool()
    private let defaultUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    private var lastActiveTime: [UUID: Date] = [:]

    @MainActor
    lazy var containerView: ChatTabsContainerView = {
        let v = ChatTabsContainerView(frame: NSRect(x: 0, y: 0, width: 1024, height: 550))
        v.wantsLayer = true
        v.layer?.cornerRadius = 12
        v.layer?.masksToBounds = true
        return v
    }()

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
        let now = Date()
        for inst in loaded {
            self.lastActiveTime[inst.id] = now
        }

        let savedActive = Defaults[.chatActiveInstanceID]
        if let savedUUID = UUID(uuidString: savedActive), loaded.contains(where: { $0.id == savedUUID }) {
            self.activeInstanceId = savedUUID
        } else {
            self.activeInstanceId = loaded.first?.id ?? UUID()
        }

        super.init()
        configureMKeyCompatibility()
    }

    @MainActor
    func focusActiveWebView() {
        guard let active = activeInstance, let wv = webViews[active.id] else { return }
        wv.window?.makeFirstResponder(wv)
    }

    private func configureMKeyCompatibility() {
        // ponytail: auto-whitelist mkey AX direct replacement. Upgrade path: dynamic IME helper.
        let mkeyDomain = "vn.mkey.app" as CFString
        let key = "axIncludeApps" as CFString
        let current = CFPreferencesCopyAppValue(key, mkeyDomain) as? [String] ?? []
        let needed = [
            "com.jinkun1998.anothernotch",
            "com.jinkun1998.anothernotch.debug",
            "com.apple.WebKit.WebContent"
        ]
        var updated = current
        var changed = false
        for item in needed where !updated.contains(item) {
            updated.append(item)
            changed = true
        }
        if changed {
            CFPreferencesSetAppValue(key, updated as CFPropertyList, mkeyDomain)
            CFPreferencesAppSynchronize(mkeyDomain)
        }
        let axKey = "vUseAXReplacement" as CFString
        if (CFPreferencesCopyAppValue(axKey, mkeyDomain) as? Int) != 1 {
            CFPreferencesSetAppValue(axKey, 1 as CFPropertyList, mkeyDomain)
            CFPreferencesAppSynchronize(mkeyDomain)
        }
    }

    func preloadActiveService() {
        guard Defaults[.chatEnabled], let active = activeInstance else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            _ = self.getOrCreateWebView(for: active)
            self.containerView.update(instances: self.instances, activeId: self.activeInstanceId, manager: self)
        }
    }

    func preloadAllServices() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for instance in self.instances {
                _ = self.getOrCreateWebView(for: instance)
            }
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
        if Defaults[.chatHibernateInactiveTabs] {
            let timeout = Double(Defaults[.chatHibernateTimeoutMinutes] * 60)
            let now = Date()
            let idleIds = webViews.keys.filter { id in
                id != activeInstanceId && now.timeIntervalSince(lastActiveTime[id] ?? now) > timeout
            }
            for id in idleIds {
                unloadWebView(for: id)
            }
        }
    }

    func toggleMute(id: UUID) {
        guard let index = instances.firstIndex(where: { $0.id == id }) else { return }
        instances[index].isMuted.toggle()
    }

    func updateZoom(_ zoom: Double) {
        for (_, wv) in webViews {
            wv.pageZoom = zoom
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
        previousCounts.removeValue(forKey: id)
        lastNotificationTime.removeValue(forKey: id)
        lastDirectNotificationTime.removeValue(forKey: id)
        lastNotificationSignature.removeValue(forKey: id)

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
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        let prefs = config.preferences
        for (key, val) in [
            ("mediaSessionEnabled", false),
            ("remotePlaybackEnabled", false),
            ("allowsPictureInPictureMediaPlayback", false),
            ("webAudioEnabled", false),
            ("requiresUserGestureForAudioPlayback", true),
            ("invisibleMediaAutoplayNotPermitted", true),
            ("requiresPageVisibilityToPlayAudio", true)
        ] as [(String, Any)] {
            prefs.setValue(val, forKey: key)
        }
        config.setValue(true, forKey: "requiresUserActionForAudioPlayback")
        config.setValue(false, forKey: "mediaDataLoadsAutomatically")

        let escapedName = instance.displayName
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let scriptSource = """
        (function() {
            if (window.__notchChatInjected) return;
            window.__notchChatInjected = true;

            try {
                if (window.navigator) {
                    delete window.navigator.mediaSession;
                    const dummyMS = {
                        metadata: null,
                        playbackState: "none",
                        setActionHandler: function() {},
                        setPositionState: function() {}
                    };
                    Object.defineProperty(window.navigator, "mediaSession", {
                        get: function() { return dummyMS; },
                        set: function() {},
                        configurable: false
                    });
                }
            } catch(e) {}
            try {
                if (window.HTMLMediaElement) {
                    window.HTMLMediaElement.prototype.disableRemotePlayback = true;
                    window.HTMLMediaElement.prototype.play = function() {
                        try {
                            this.muted = true;
                            this.volume = 0;
                            this.disableRemotePlayback = true;
                            this.pause();
                        } catch(_) {}
                        return Promise.resolve();
                    };
                    Object.defineProperty(window.HTMLMediaElement.prototype, "muted", {
                        get: function() { return true; },
                        set: function() {},
                        configurable: true
                    });
                    Object.defineProperty(window.HTMLMediaElement.prototype, "volume", {
                        get: function() { return 0; },
                        set: function() {},
                        configurable: true
                    });
                }
            } catch(e) {}
            try {
                const AC = window.AudioContext || window.webkitAudioContext;
                if (AC) {
                    if (window.AudioNode && window.AudioNode.prototype) {
                        const origConnect = window.AudioNode.prototype.connect;
                        window.AudioNode.prototype.connect = function(dest) {
                            if (this.context && dest === this.context.destination) {
                                return dest;
                            }
                            return origConnect.apply(this, arguments);
                        };
                    }
                    if (AC.prototype && AC.prototype.createGain) {
                        const origGain = AC.prototype.createGain;
                        AC.prototype.createGain = function() {
                            const g = origGain.apply(this, arguments);
                            try { g.gain.setValueAtTime(0, 0); g.gain.value = 0; } catch(_) {}
                            return g;
                        };
                    }
                }
            } catch(e) {}
            try {
                document.addEventListener('play', function(e) {
                    if (e.target && e.target.pause) {
                        try {
                            e.target.pause();
                            e.target.muted = true;
                            e.target.volume = 0;
                        } catch(_) {}
                    }
                }, true);
            } catch(e) {}
            window.__notchInstanceId = "\(instance.id.uuidString)";
            window.__notchServiceName = "\(escapedName)";

            function cleanPromoBanners() {
                try {
                    const style = document.createElement('style');
                    style.id = '__notchChatCleaner';
                    style.textContent = `
                        .download-banner, .download-apps-banner, .DownloadBanner,
                        [data-testid="download-desktop-banner"],
                        ._2XH9R, ._1ENAC, .landing-wrapper .version-title,
                        .app-download-banner, [aria-label*="Download desktop app"]
                        { display: none !important; }
                    `;
                    (document.head || document.documentElement).appendChild(style);
                } catch(e) {}
            }
            cleanPromoBanners();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', cleanPromoBanners);
            }

            function disablePred(el) {
                if (!el || !el.setAttribute || el.__notchPredDisabled) return;
                el.__notchPredDisabled = true;
                try {
                    el.setAttribute('autocomplete', 'off');
                    el.setAttribute('autocorrect', 'off');
                    el.setAttribute('autocapitalize', 'off');
                    el.setAttribute('spellcheck', 'false');
                    el.setAttribute('data-gramm', 'false');
                    el.setAttribute('data-enable-grammarly', 'false');
                } catch(e) {}
            }
            document.addEventListener('focusin', function(e) {
                var el = e.target;
                if (el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.isContentEditable || (el.getAttribute && el.getAttribute('role') === 'textbox'))) {
                    disablePred(el);
                }
            }, true);

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

            let lastRawTitle = '';
            function checkTitleBadge() {
                try {
                    const rawTitle = (document.title || '').trim();
                    if (!rawTitle || rawTitle === lastRawTitle) return;
                    lastRawTitle = rawTitle;

                    let count = 0;
                    const match = rawTitle.match(/\\((\\d+)\\)/);
                    if (match) {
                        count = parseInt(match[1], 10);
                    } else if (rawTitle.startsWith('*') || rawTitle.startsWith('•')) {
                        count = 1;
                    }

                    window.webkit.messageHandlers.notchBadge.postMessage({
                        instanceId: window.__notchInstanceId || '',
                        count: count,
                        rawTitle: rawTitle
                    });
                } catch(e) {}
            }

            function initTitleObserver() {
                checkTitleBadge();
                const titleElem = document.querySelector('title');
                if (titleElem) {
                    new MutationObserver(checkTitleBadge).observe(titleElem, { subtree: true, characterData: true, childList: true });
                }
                if (document.head) {
                    new MutationObserver(checkTitleBadge).observe(document.head, { subtree: true, characterData: true, childList: true });
                }
            }

            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', initTitleObserver);
            } else {
                initTitleObserver();
            }
            setInterval(checkTitleBadge, 2500);
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

        let initialRect = NSRect(x: 0, y: 0, width: 1024, height: 550)
        let webView = ChatWebView(frame: initialRect, configuration: config)
        let selMute = NSSelectorFromString("_setPageMuted:")
        if webView.responds(to: selMute) {
            typealias SetMutedFn = @convention(c) (AnyObject, Selector, UInt64) -> Void
            let imp = class_getMethodImplementation(type(of: webView), selMute)
            let fn = unsafeBitCast(imp, to: SetMutedFn.self)
            fn(webView, selMute, 1)
        }
        webView.customUserAgent = defaultUserAgent
        webView.pageZoom = Defaults[.chatPageZoom]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.underPageBackgroundColor = NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1.0)
        webView.wantsLayer = true
        webView.canDrawConcurrently = true
        webView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        webView.alphaValue = (instance.id == activeInstanceId) ? 1.0 : 0.0

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
        let instanceId = webViews.first(where: { $0.value === message.webView })?.key
            ?? UUID(uuidString: instanceIdStr)
            ?? activeInstanceId

        if message.name == "notchNotification" {
            let title = (dict["title"] as? String) ?? ""
            let body = (dict["body"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.handleNotification(instanceId: instanceId, title: title, body: body, isDirect: true)
            }
        } else if message.name == "notchBadge" {
            let count = (dict["count"] as? Int) ?? 0
            let rawTitle = (dict["rawTitle"] as? String) ?? ""
            DispatchQueue.main.async { [weak self] in
                self?.handleBadge(instanceId: instanceId, count: count, rawTitle: rawTitle)
            }
        }
    }

    private var lastGlobalNotificationTime: Date = .distantPast
    private var lastNotificationTime: [UUID: Date] = [:]
    private var lastDirectNotificationTime: [UUID: Date] = [:]
    private var lastNotificationSignature: [UUID: String] = [:]
    private var previousCounts: [UUID: Int] = [:]

    @MainActor
    func handleNotification(instanceId: UUID, title: String, body: String, isDirect: Bool = false, isTest: Bool = false) {
        // Skip if chat module not installed or disabled
        guard FeatureModuleRegistry.shared.isAvailable(.chat) else { return }
        guard let instance = instances.first(where: { $0.id == instanceId }) else { return }
        guard !instance.isMuted else { return }
        guard !title.isEmpty || !body.isEmpty else { return }

        let now = Date()

        // Suppress popups ONLY when notch is open and user is actively viewing this exact chat tab
        let isViewingThisChat = AnotherNotchViewCoordinator.shared.isNotchOpen
            && AnotherNotchViewCoordinator.shared.currentView == .chat
            && activeInstanceId == instanceId
        if isViewingThisChat && !isTest {
            unreadCounts[instanceId] = 0
            return
        }

        if !isTest {
            // Deduplicate identical message text within 15s
            let signature = "\(title)|||\(body)"
            if lastNotificationSignature[instanceId] == signature,
               let lastTime = lastNotificationTime[instanceId],
               now.timeIntervalSince(lastTime) < 15.0 {
                return
            }

            if isDirect {
                // Direct notifications bypass badge throttle; throttle identical or rapid fire (< 0.5s)
                if let last = lastDirectNotificationTime[instanceId], now.timeIntervalSince(last) < 0.5 {
                    return
                }
            } else {
                // Indirect badge updates: throttle 1.2s per instance, 0.8s globally
                if let last = lastNotificationTime[instanceId], now.timeIntervalSince(last) < 1.2 {
                    return
                }
                if now.timeIntervalSince(lastGlobalNotificationTime) < 0.8 {
                    return
                }
            }

            lastNotificationTime[instanceId] = now
            lastGlobalNotificationTime = now
            lastNotificationSignature[instanceId] = signature
        }

        if isDirect {
            lastDirectNotificationTime[instanceId] = now
            unreadCounts[instanceId, default: 0] += 1
        }

        let cleanTitle = title.isEmpty ? instance.displayName : title
        latestNotification = ChatNotificationItem(
            instanceId: instanceId,
            serviceType: instance.serviceType,
            instanceName: instance.displayName,
            title: cleanTitle,
            body: body,
            timestamp: now
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
    private func handleBadge(instanceId: UUID, count: Int, rawTitle: String) {
        // Skip if chat module not installed or disabled
        guard FeatureModuleRegistry.shared.isAvailable(.chat) else { return }
        let oldCount = previousCounts[instanceId] ?? 0
        if count != oldCount {
            previousCounts[instanceId] = count
            unreadCounts[instanceId] = count
        }

        guard count > oldCount else { return }

        // Ignore badge title updates if direct Web Notification already dispatched within 3s
        if let lastDirect = lastDirectNotificationTime[instanceId],
           Date().timeIntervalSince(lastDirect) < 3.0 {
            return
        }

        guard let instance = instances.first(where: { $0.id == instanceId }) else { return }

        // Never guess sender from document.title: title reflects active chat, not incoming sender.
        // ponytail: service name title fallback. Upgrade path: per-service DOM parser if direct notifications fail.
        let sender = instance.displayName
        let snippet = count == 1 ? "New message" : "\(count) new messages"
        handleNotification(instanceId: instanceId, title: sender, body: snippet, isDirect: false)
    }

    @MainActor
    func testNotification() {
        guard let instance = activeInstance ?? instances.first else { return }
        handleNotification(
            instanceId: instance.id,
            title: instance.displayName,
            body: "Hello! This is a test notch notification.",
            isDirect: false,
            isTest: true
        )
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let selMute = NSSelectorFromString("_setPageMuted:")
        if webView.responds(to: selMute) {
            typealias SetMutedFn = @convention(c) (AnyObject, Selector, UInt64) -> Void
            let imp = class_getMethodImplementation(type(of: webView), selMute)
            let fn = unsafeBitCast(imp, to: SetMutedFn.self)
            fn(webView, selMute, 1)
        }
    }

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
