import AppKit
import ApplicationServices
import Combine
import Defaults
import Foundation
import ImageIO
import SwiftUI

extension Defaults.Keys {
    public static let airDropHUDReplacement = Key<Bool>("airDropHUDReplacement", default: true)
}

enum AirDropTransferStatus: Equatable {
    case prompt
    case transferring
    case completed
    case declined
    case failed
}

struct AirDropIncomingTransfer: Identifiable, Equatable {
    let id: String
    let senderName: String
    let itemsDescription: String
    var previewImage: NSImage?
    var status: AirDropTransferStatus
    var progress: Double

    static func == (lhs: AirDropIncomingTransfer, rhs: AirDropIncomingTransfer) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status && abs(lhs.progress - rhs.progress) < 0.01 && (lhs.previewImage != nil) == (rhs.previewImage != nil)
    }
}

// MARK: - Native Sharing.framework Observer Proxy

private final class AirDropNativeObserverProxy: NSObject {
    weak var manager: AirDropManager?

    init(manager: AirDropManager) {
        self.manager = manager
        super.init()
    }

    @objc func updatedTransfer(_ transfer: AnyObject) {
        Task { @MainActor [weak self] in
            self?.manager?.handleNativeTransferUpdate(transfer)
        }
    }

    @objc func removedTransfer(_ transfer: AnyObject) {
        Task { @MainActor [weak self] in
            self?.manager?.handleNativeTransferRemoved(transfer)
        }
    }
}

// MARK: - AirDropManager

@MainActor
final class AirDropManager: NSObject, ObservableObject {
    static let shared = AirDropManager()

    @Published private(set) var currentTransfer: AirDropIncomingTransfer?
    @Published private(set) var isClosing: Bool = false

    // Native Sharing.framework observer
    private var nativeObserver: AnyObject?
    private var nativeObserverDelegate: AirDropNativeObserverProxy?
    private var activeNativeTransfer: AnyObject?

    // AX observation state
    private var axObserver: AXObserver?
    private var axRunLoopSource: CFRunLoopSource?
    private var axObservedPID: pid_t = 0
    private var pollTimer: Timer?
    private var axNativeWindow: AXUIElement?
    private var axAcceptButton: AXUIElement?
    private var axDeclineButton: AXUIElement?

    private let scanQueue = DispatchQueue(label: "com.anothernotch.airdrop.scan", qos: .utility)
    private var scanDebounceWorkItem: DispatchWorkItem?
    private var dismissTask: Task<Void, Never>?
    private var imagePollTask: Task<Void, Never>?

    private var motion: NotchMotionPolicy {
        NotchMotionPolicy(reduceMotion: false)
    }

    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        if Defaults[.airDropHUDReplacement] {
            setupObservers()
        }
        Defaults.publisher(.airDropHUDReplacement)
            .dropFirst()
            .sink { [weak self] change in
                Task { @MainActor in
                    if change.newValue {
                        self?.setupObservers()
                    } else {
                        self?.teardownObservers()
                    }
                }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] notif in
                guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
                Task { @MainActor in
                    self?.setupAXNotificationObserver()
                }
            }
            .store(in: &cancellables)
    }

    // ponytail: SFAirDropTransferObserver + AX window interceptor; upgrade path: public Apple AirDrop API when available.
    private func setupObservers() {
        setupNativeAirDropObserver()
        setupAXNotificationObserver()
    }

    private func teardownObservers() {
        teardownNativeAirDropObserver()
        teardownAXNotificationObserver()
        hideNotificationBanner(hidden: false)
        currentTransfer = nil
        isClosing = false
    }

    // MARK: - Presentation & Notch Animation Lifecycle

    func presentHUD(transfer: AirDropIncomingTransfer) {
        dismissTask?.cancel()
        isClosing = false
        withAnimation(motion.openShellAnimation) {
            self.currentTransfer = transfer
        }
    }

    func dismissHUD() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            withAnimation(self.motion.expandedContentHideAnimation) {
                self.isClosing = true
            }
            try? await Task.sleep(nanoseconds: UInt64(self.motion.expandedContentHideDuration * 1_000_000_000))
            guard self.isClosing else { return }

            withAnimation(self.motion.closeShellAnimation) {
                self.currentTransfer = nil
            }
            self.hideNotificationBanner(hidden: false)

            try? await Task.sleep(nanoseconds: UInt64(self.motion.closeDuration * 1_000_000_000))
            self.isClosing = false
        }
    }

    private func startPollingForIncomingImage() {
        imagePollTask?.cancel()
        imagePollTask = Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard let self = self, self.currentTransfer != nil else { return }
                if self.currentTransfer?.previewImage == nil {
                    if let img = self.findRecentAirDropImage(maxAgeSeconds: 30) {
                        withAnimation(self.motion.expandedContentRevealAnimation) {
                            if var curr = self.currentTransfer {
                                curr.previewImage = img
                                self.currentTransfer = curr
                            }
                        }
                        return
                    }
                }
            }
        }
    }

    // MARK: - Native Sharing Observer (SFAirDropTransferObserver)

    private func setupNativeAirDropObserver() {
        teardownNativeAirDropObserver()
        dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_NOW)
        guard let obsClass = NSClassFromString("SFAirDropTransferObserver") as? NSObject.Type else { return }

        let delegate = AirDropNativeObserverProxy(manager: self)
        self.nativeObserverDelegate = delegate

        let obs = obsClass.init()
        obs.setValue(delegate, forKey: "delegate")
        obs.perform(NSSelectorFromString("activate"))
        self.nativeObserver = obs
    }

    private func teardownNativeAirDropObserver() {
        if let obs = nativeObserver as? NSObject {
            obs.perform(NSSelectorFromString("invalidate"))
        }
        nativeObserver = nil
        nativeObserverDelegate = nil
        activeNativeTransfer = nil
    }

    fileprivate func handleNativeTransferUpdate(_ transfer: AnyObject) {
        guard Defaults[.airDropHUDReplacement] else { return }
        self.activeNativeTransfer = transfer

        // Hide native Notification Center banner
        hideNotificationBanner(hidden: true)

        guard let meta = transfer.value(forKey: "metaData") as? NSObject else { return }

        let sender = (meta.value(forKey: "senderCompositeName") as? String)
            ?? (meta.value(forKey: "senderComputerName") as? String)
            ?? "iPhone"

        let itemsDesc = (meta.value(forKey: "itemsDescription") as? String) ?? "Incoming file"

        let isSameiCloud = (meta.value(forKey: "senderIsMe") as? Bool ?? false)
            || (meta.value(forKey: "didAutoAccept") as? Bool ?? false)
            || (meta.value(forKey: "canAutoAccept") as? Bool ?? false)

        let needsAction = (transfer.value(forKey: "needsAction") as? Bool) ?? false
        let transferState = (transfer.value(forKey: "transferState") as? UInt) ?? 0

        var preview = extractImage(from: meta.value(forKey: "previewImage"))
            ?? extractImage(from: meta.value(forKey: "smallPreviewImage"))

        if preview == nil, let urls = transfer.value(forKey: "completedURLs") as? [URL] ?? (transfer.value(forKey: "completedURLs") as? Set<URL>).map(Array.init) {
            for u in urls {
                if let img = imageFromFile(at: u) {
                    preview = img
                    break
                }
            }
        }
        if preview == nil {
            preview = findRecentAirDropImage(maxAgeSeconds: 30) ?? currentTransfer?.previewImage
        }

        var progressValue: Double = 0.0
        if let p = transfer.value(forKey: "transferProgress") as? Progress {
            progressValue = p.fractionCompleted
        }

        let status: AirDropTransferStatus = {
            if isSameiCloud || transferState == 3 {
                return .completed
            }
            if transferState == 4 {
                return .declined
            }
            if transferState == 5 {
                return .failed
            }
            if needsAction {
                return .prompt
            }
            if progressValue > 0 || transferState == 2 || transferState == 1 {
                return .transferring
            }
            return .prompt
        }()

        let transferId = (transfer.value(forKey: "identifier") as? String) ?? "native_airdrop"
        let item = AirDropIncomingTransfer(
            id: transferId,
            senderName: sender,
            itemsDescription: itemsDesc,
            previewImage: preview,
            status: status,
            progress: isSameiCloud ? 1.0 : progressValue
        )

        presentHUD(transfer: item)

        if preview == nil {
            startPollingForIncomingImage()
        }

        if isSameiCloud || status == .completed {
            dismissTask?.cancel()
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_800_000_000)
                self.dismissHUD()
            }
        }
    }

    fileprivate func handleNativeTransferRemoved(_ transfer: AnyObject) {
        if let active = activeNativeTransfer,
           let idA = active.value(forKey: "identifier") as? String,
           let idB = transfer.value(forKey: "identifier") as? String,
           idA == idB {
            activeNativeTransfer = nil
            dismissHUD()
        }
    }

    // MARK: - Image Utilities

    private func extractImage(from value: Any?) -> NSImage? {
        guard let value = value else { return nil }
        if let img = value as? NSImage {
            return img
        }
        if CFGetTypeID(value as CFTypeRef) == CGImage.typeID {
            let cg = value as! CGImage
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        if let data = value as? Data, let img = NSImage(data: data) {
            return img
        }
        if let list = value as? [Any], let first = list.first {
            return extractImage(from: first)
        }
        if let url = value as? URL {
            return imageFromFile(at: url)
        }
        return nil
    }

    private func imageFromFile(at url: URL) -> NSImage? {
        if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        return NSImage(contentsOf: url)
    }

    nonisolated func findRecentAirDropImage(maxAgeSeconds: TimeInterval = 60) -> NSImage? {
        let fm = FileManager.default
        let dirs = [
            fm.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            fm.urls(for: .picturesDirectory, in: .userDomainMask).first,
            fm.urls(for: .desktopDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        let imageExtensions: Set<String> = ["heic", "jpg", "jpeg", "png", "webp", "gif", "tiff"]
        var candidates: [(URL, Date)] = []
        let now = Date()

        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in files {
                guard imageExtensions.contains(url.pathExtension.lowercased()) else { continue }
                let vals = try? url.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey, .creationDateKey])
                if let d = vals?.addedToDirectoryDate ?? vals?.contentModificationDate ?? vals?.creationDate {
                    if maxAgeSeconds <= 0 || now.timeIntervalSince(d) <= maxAgeSeconds {
                        candidates.append((url, d))
                    }
                }
            }
        }

        candidates.sort { $0.1 > $1.1 }

        for (url, _) in candidates.prefix(5) {
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
            if let img = NSImage(contentsOf: url) {
                return img
            }
        }

        return nil
    }

    private func fallbackTestImage() -> NSImage? {
        let paths = [
            "/System/Library/Desktop Pictures/.thumbnails/The Beach.heic",
            "/System/Library/Desktop Pictures/Sonoma.heic",
            "/System/Library/Desktop Pictures/Mac Blue.heic"
        ]
        for p in paths {
            if let img = NSImage(contentsOfFile: p) {
                return img
            }
        }
        return nil
    }

    // MARK: - AX Notification Center Observer

    private func setupAXNotificationObserver() {
        teardownAXNotificationObserver()

        guard let ncApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui" || $0.localizedName == "Notification Center"
        }) else {
            startPollingTimer()
            return
        }

        let pid = ncApp.processIdentifier
        var obs: AXObserver?
        let err = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon = refcon else { return }
            let manager = Unmanaged<AirDropManager>.fromOpaque(refcon).takeUnretainedValue()
            Task { @MainActor in
                manager.requestScan()
            }
        }, &obs)

        if err == .success, let obs = obs {
            let appElem = AXUIElementCreateApplication(pid)
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            AXObserverAddNotification(obs, appElem, kAXWindowCreatedNotification as CFString, selfPtr)
            AXObserverAddNotification(obs, appElem, kAXFocusedWindowChangedNotification as CFString, selfPtr)
            let src = AXObserverGetRunLoopSource(obs)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            self.axObserver = obs
            self.axRunLoopSource = src
            self.axObservedPID = pid
        }

        startPollingTimer()
        requestScan()
    }

    private func teardownAXNotificationObserver() {
        if let obs = axObserver, let src = axRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            let appElem = AXUIElementCreateApplication(axObservedPID)
            AXObserverRemoveNotification(obs, appElem, kAXWindowCreatedNotification as CFString)
            AXObserverRemoveNotification(obs, appElem, kAXFocusedWindowChangedNotification as CFString)
        }
        axObserver = nil
        axRunLoopSource = nil
        axObservedPID = 0
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func startPollingTimer() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.requestScan()
            }
        }
    }

    func requestScan() {
        scanDebounceWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.performBackgroundScan()
        }
        scanDebounceWorkItem = item
        scanQueue.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    nonisolated func scanNotificationCenterWindows() {
        performBackgroundScan()
    }

    nonisolated private func hideNotificationBanner(hidden: Bool) {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
        guard let f_conn = dlsym(handle, "SLSMainConnectionID"),
              let f_alpha = dlsym(handle, "SLSSetWindowAlpha") else { return }
        typealias F_SLSMainConnectionID = @convention(c) () -> Int32
        typealias F_SLSSetWindowAlpha = @convention(c) (Int32, UInt32, Float) -> Int32
        let SLSMainConnectionID = unsafeBitCast(f_conn, to: F_SLSMainConnectionID.self)
        let SLSSetWindowAlpha = unsafeBitCast(f_alpha, to: F_SLSSetWindowAlpha.self)
        let cid = SLSMainConnectionID()

        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in list {
            let owner = w[kCGWindowOwnerName as String] as? String ?? ""
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if owner.contains("Notification") && layer >= 20 {
                if let wid = w[kCGWindowNumber as String] as? UInt32 {
                    _ = SLSSetWindowAlpha(cid, wid, hidden ? 0.0 : 1.0)
                }
            }
        }
    }

    @discardableResult
    nonisolated private func dismissAirDropBanner(in elem: AXUIElement) -> Bool {
        var descRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        let desc = descRef as? String ?? ""

        var subroleRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subroleRef)
        let subrole = subroleRef as? String ?? ""

        if subrole == "AXNotificationCenterBanner" || desc.localizedCaseInsensitiveContains("airdrop") {
            var actionsRef: CFArray?
            AXUIElementCopyActionNames(elem, &actionsRef)
            if let actions = actionsRef as? [String] {
                for act in actions where act.contains("Close") || act.contains("Dismiss") || act == "AXCancel" {
                    return AXUIElementPerformAction(elem, act as CFString) == .success
                }
            }
        }

        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for c in children {
                if dismissAirDropBanner(in: c) { return true }
            }
        }
        return false
    }

    nonisolated private func performBackgroundScan() {
        guard Defaults[.airDropHUDReplacement] else { return }

        guard let ncApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui" || $0.localizedName == "Notification Center"
        }) else { return }

        let pid = ncApp.processIdentifier
        let appElem = AXUIElementCreateApplication(pid)
        var windowsRef: AnyObject?
        guard AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            Task { @MainActor in self.checkWindowDisappeared() }
            return
        }

        var foundWindow: AXUIElement?
        var foundAccept: AXUIElement?
        var foundDecline: AXUIElement?
        var foundSender = "iPhone"
        var foundDesc = "Incoming file"
        var isSameiCloud = false
        let previewImg = findRecentAirDropImage(maxAgeSeconds: 30)

        for win in windows {
            var subroleRef: AnyObject?
            AXUIElementCopyAttributeValue(win, kAXSubroleAttribute as CFString, &subroleRef)
            let subrole = subroleRef as? String ?? ""
            guard subrole == "AXSystemDialog" || subrole == "AXDialog" else { continue }

            var texts: [String] = []
            var buttons: [(elem: AXUIElement, title: String, subrole: String)] = []
            collectElements(win, texts: &texts, buttons: &buttons)

            let hasAirDrop = texts.contains { $0.localizedCaseInsensitiveContains("airdrop") }
            guard hasAirDrop else { continue }

            foundWindow = win
            hideNotificationBanner(hidden: true)

            for b in buttons {
                let t = b.title.lowercased()
                let sub = b.subrole
                if t.contains("accept") || t.contains("chấp nhận") || t.contains("save") || t.contains("lưu") || t.contains("open") || t.contains("mở") {
                    foundAccept = b.elem
                } else if t.contains("decline") || t.contains("từ chối") || t.contains("cancel") || t.contains("hủy") || sub == "AXCloseButton" {
                    foundDecline = b.elem
                }
            }

            let cleaned = texts.filter {
                !$0.localizedCaseInsensitiveContains("airdrop") &&
                !$0.localizedCaseInsensitiveContains("notification") &&
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }

            for item in cleaned {
                let lower = item.lowercased()
                if lower.contains("wants to share") || lower.contains("muốn chia sẻ") || lower.contains("photo") || lower.contains("item") || lower.contains("file") || lower.contains("tệp") || lower.contains("sent") || lower.contains("đã gửi") || lower.contains("received") || lower.contains("đã nhận") {
                    foundDesc = item
                } else if foundSender == "iPhone" {
                    foundSender = item
                }
            }

            if foundDesc == "Incoming file", cleaned.count > 1 {
                foundDesc = cleaned[1]
            }

            if let parsed = parseSenderAndItems(from: foundDesc) {
                if foundSender == "iPhone" || foundSender == foundDesc {
                    foundSender = parsed.sender
                }
                foundDesc = parsed.items
            }

            let hasSentText = texts.contains { t in
                let l = t.lowercased()
                return l.contains("sent") || l.contains("đã gửi") || l.contains("received") || l.contains("đã nhận") || l.contains("saved") || l.contains("đã lưu")
            }
            isSameiCloud = (foundAccept == nil) || hasSentText

            if isSameiCloud {
                dismissAirDropBanner(in: win)
                scanQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.hideNotificationBanner(hidden: false)
                }
            }
            break
        }

        Task { @MainActor in
            self.handleScanResult(
                pid: pid,
                window: foundWindow,
                acceptBtn: foundAccept,
                declineBtn: foundDecline,
                sender: foundSender,
                desc: foundDesc,
                previewImage: previewImg,
                isSameiCloud: isSameiCloud
            )
        }
    }

    private func handleScanResult(
        pid: pid_t,
        window: AXUIElement?,
        acceptBtn: AXUIElement?,
        declineBtn: AXUIElement?,
        sender: String,
        desc: String,
        previewImage: NSImage?,
        isSameiCloud: Bool
    ) {
        guard let window = window else {
            checkWindowDisappeared()
            return
        }

        self.axNativeWindow = window
        self.axAcceptButton = acceptBtn
        self.axDeclineButton = declineBtn

        let status: AirDropTransferStatus = isSameiCloud ? .completed : (currentTransfer?.status ?? .prompt)
        let resolvedImage = previewImage ?? currentTransfer?.previewImage ?? findRecentAirDropImage(maxAgeSeconds: 30)

        if currentTransfer == nil || currentTransfer?.status == .prompt {
            let transfer = AirDropIncomingTransfer(
                id: "ax_airdrop_\(pid)",
                senderName: sender,
                itemsDescription: desc,
                previewImage: resolvedImage,
                status: status,
                progress: isSameiCloud ? 1.0 : (currentTransfer?.progress ?? 0.0)
            )
            presentHUD(transfer: transfer)

            if resolvedImage == nil {
                startPollingForIncomingImage()
            }

            if isSameiCloud {
                dismissTask?.cancel()
                dismissTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_800_000_000)
                    self.dismissHUD()
                }
            }
        } else if var curr = currentTransfer, curr.previewImage == nil, let img = resolvedImage {
            withAnimation(motion.expandedContentRevealAnimation) {
                curr.previewImage = img
                self.currentTransfer = curr
            }
        }
    }

    nonisolated private func parseSenderAndItems(from str: String) -> (sender: String, items: String)? {
        let pattern = #"^(.+?)\s+(?:sent|has sent|đã gửi|wants to share|muốn chia sẻ)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
              match.numberOfRanges >= 3,
              let r1 = Range(match.range(at: 1), in: str),
              let r2 = Range(match.range(at: 2), in: str) else {
            return nil
        }
        let sender = String(str[r1]).trimmingCharacters(in: .whitespacesAndNewlines)
        var items = String(str[r2]).trimmingCharacters(in: .whitespacesAndNewlines)
        if items.hasSuffix(".") { items.removeLast() }
        return (sender, items)
    }

    private func checkWindowDisappeared() {
        guard let curr = currentTransfer, curr.id.starts(with: "ax_airdrop_") else { return }
        hideNotificationBanner(hidden: false)

        if curr.status == .transferring {
            var completed = curr
            completed.status = .completed
            completed.progress = 1.0
            withAnimation(motion.openShellAnimation) {
                self.currentTransfer = completed
            }
            dismissTask?.cancel()
            dismissTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.dismissHUD()
            }
        } else if curr.status == .prompt {
            dismissHUD()
        }
        axNativeWindow = nil
        axAcceptButton = nil
        axDeclineButton = nil
    }

    nonisolated private func collectElements(_ elem: AXUIElement, texts: inout [String], buttons: inout [(elem: AXUIElement, title: String, subrole: String)]) {
        var roleRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        var titleRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var valueRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXValueAttribute as CFString, &valueRef)
        let val = (valueRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var descRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXDescriptionAttribute as CFString, &descRef)
        let desc = (descRef as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        var subRef: AnyObject?
        AXUIElementCopyAttributeValue(elem, kAXSubroleAttribute as CFString, &subRef)
        let sub = subRef as? String ?? ""

        if role == "AXStaticText" {
            let str = val.isEmpty ? title : val
            if !str.isEmpty && !texts.contains(str) {
                texts.append(str)
            }
        }
        if !desc.isEmpty && !texts.contains(desc) {
            texts.append(desc)
        }
        if role == "AXButton" {
            buttons.append((elem, title.isEmpty ? desc : title, sub))
        }

        var childrenRef: AnyObject?
        if AXUIElementCopyAttributeValue(elem, kAXChildrenAttribute as CFString, &childrenRef) == .success,
           let children = childrenRef as? [AXUIElement] {
            for c in children {
                collectElements(c, texts: &texts, buttons: &buttons)
            }
        }
    }

    // MARK: - User Actions

    func accept() {
        if let transfer = activeNativeTransfer {
            if let actions = transfer.value(forKey: "possibleActions") as? [NSObject] {
                for action in actions {
                    let type = action.value(forKey: "type") as? Int ?? -1
                    let title = (action.value(forKey: "localizedTitle") as? String ?? "").lowercased()
                    if type == 1 || title.contains("accept") || title.contains("save") || title.contains("chấp nhận") || title.contains("lưu") {
                        action.perform(NSSelectorFromString("triggerAction"))
                        break
                    }
                }
            }
        }
        if let btn = axAcceptButton {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        }

        if var curr = currentTransfer {
            curr.status = .transferring
            curr.progress = max(curr.progress, 0.08)
            currentTransfer = curr
            if activeNativeTransfer == nil {
                simulateTransferProgress()
            }
        }
    }

    func decline() {
        if let transfer = activeNativeTransfer {
            if let cancelAction = transfer.value(forKey: "cancelAction") as? NSObject {
                cancelAction.perform(NSSelectorFromString("triggerAction"))
            } else if let actions = transfer.value(forKey: "possibleActions") as? [NSObject] {
                for action in actions {
                    let type = action.value(forKey: "type") as? Int ?? -1
                    let title = (action.value(forKey: "localizedTitle") as? String ?? "").lowercased()
                    if type == 0 || title.contains("decline") || title.contains("cancel") || title.contains("từ chối") {
                        action.perform(NSSelectorFromString("triggerAction"))
                        break
                    }
                }
            }
        }
        if let btn = axDeclineButton {
            AXUIElementPerformAction(btn, kAXPressAction as CFString)
        } else if let win = axNativeWindow {
            dismissAirDropBanner(in: win)
        }

        withAnimation(motion.closeShellAnimation) {
            if var curr = currentTransfer {
                curr.status = .declined
                currentTransfer = curr
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.dismissHUD()
        }
    }

    func testPrompt() {
        dismissTask?.cancel()
        axAcceptButton = nil
        axDeclineButton = nil
        activeNativeTransfer = nil
        let img = findRecentAirDropImage(maxAgeSeconds: 0) ?? fallbackTestImage()
        let mock = AirDropIncomingTransfer(
            id: UUID().uuidString,
            senderName: "iPhone",
            itemsDescription: "3 Photos",
            previewImage: img,
            status: .prompt,
            progress: 0.0
        )
        presentHUD(transfer: mock)
    }

    private func simulateTransferProgress() {
        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            for step in 1...10 {
                try? await Task.sleep(nanoseconds: 180_000_000)
                guard currentTransfer?.status == .transferring else { return }
                currentTransfer?.progress = Double(step) / 10.0
            }
            currentTransfer?.status = .completed
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self.dismissHUD()
        }
    }
}
