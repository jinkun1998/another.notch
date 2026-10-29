import SwiftUI
import WebKit

final class ChatTabsContainerView: NSView {
    private(set) var subWebViews: [UUID: WKWebView] = [:]
    private var currentActiveId: UUID?
    private let defaultContentSize = CGSize(width: 1024, height: 550)

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
    }

    func update(instances: [ChatInstance], activeId: UUID, manager: ChatManager) {
        let validIds = Set(instances.map { $0.id })
        for (id, wv) in subWebViews where !validIds.contains(id) {
            wv.removeFromSuperview()
            subWebViews.removeValue(forKey: id)
        }

        let targetFrame = (bounds.width > 200 && bounds.height > 200) ? bounds : NSRect(origin: .zero, size: defaultContentSize)

        // Lazy-load ONLY the active instance on demand
        if subWebViews[activeId] == nil, let activeInstance = instances.first(where: { $0.id == activeId }) {
            let wv = manager.getOrCreateWebView(for: activeInstance)
            wv.wantsLayer = true
            wv.layer?.cornerRadius = 12
            wv.layer?.masksToBounds = true
            wv.autoresizingMask = []
            wv.frame = targetFrame
            addSubview(wv)
            subWebViews[activeId] = wv
        }

        let isTabSwitch = (currentActiveId != activeId)
        currentActiveId = activeId

        for (id, wv) in subWebViews {
            let isCurrent = (id == activeId)
            if isCurrent {
                if wv.superview !== self {
                    addSubview(wv)
                }
                if wv.frame != targetFrame {
                    wv.frame = targetFrame
                }
                wv.alphaValue = 1.0
                // ponytail: only promote and focus on tab switch to avoid interrupting active typing. Upgrade path: focus restoration token.
                if isTabSwitch {
                    addSubview(wv, positioned: .above, relativeTo: nil)
                    DispatchQueue.main.async { [weak wv] in
                        guard let wv = wv, let win = wv.window else { return }
                        if let responder = win.firstResponder as? NSView, responder.isDescendant(of: wv) {
                            return
                        }
                        win.makeFirstResponder(wv)
                    }
                }
            } else {
                let offscreen = NSRect(x: -20000, y: -20000, width: targetFrame.width, height: targetFrame.height)
                if wv.frame != offscreen {
                    wv.frame = offscreen
                }
                wv.alphaValue = 0.0
            }
        }
    }

    override func layout() {
        super.layout()
        guard bounds.width > 200 && bounds.height > 200 else { return }
        if let activeId = currentActiveId, let activeWV = subWebViews[activeId], activeWV.frame != bounds {
            activeWV.frame = bounds
        }
    }

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
        if let activeId = currentActiveId, let wv = subWebViews[activeId] {
            if let win = window, !(win.firstResponder is NSView && (win.firstResponder as? NSView)?.isDescendant(of: wv) == true) {
                win.makeFirstResponder(wv)
            }
        }
        super.mouseDown(with: event)
    }
}

struct ChatTabsContainerRepresentable: NSViewRepresentable {
    let instances: [ChatInstance]
    let activeId: UUID
    @ObservedObject var chatManager = ChatManager.shared

    func makeNSView(context: Context) -> ChatTabsContainerView {
        chatManager.containerView.update(instances: instances, activeId: activeId, manager: chatManager)
        return chatManager.containerView
    }

    func updateNSView(_ nsView: ChatTabsContainerView, context: Context) {
        nsView.update(instances: instances, activeId: activeId, manager: chatManager)
    }
}

struct ChatView: View {
    @ObservedObject private var chatManager = ChatManager.shared
    @State private var renamingInstance: ChatInstance?
    @State private var renameText: String = ""
    @State private var isShowingCustomAlert: Bool = false
    @State private var customServiceName: String = ""
    @State private var customServiceURL: String = "https://"
    @State private var draggedId: UUID?

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
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back (⌘[)")

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
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Forward (⌘])")

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
                    .keyboardShortcut("r", modifiers: .command)
                    .help("Reload page (⌘R)")

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
            if !chatManager.instances.isEmpty {
                ChatTabsContainerRepresentable(
                    instances: chatManager.instances,
                    activeId: chatManager.activeInstanceId,
                    chatManager: chatManager
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .clipped()
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
        .onAppear {
            chatManager.preloadActiveService()
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
            chatManager.activeInstanceId = instance.id
        } label: {
            HStack(spacing: 5) {
                ChatServiceIconView(icon: instance.iconName, size: 12)
                    .opacity(isSelected ? 1.0 : 0.6)

                Text(instance.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .white : .secondary)

                if instance.isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }

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
        .opacity(draggedId == instance.id ? 0.45 : 1.0)
        .onDrag {
            draggedId = instance.id
            return NSItemProvider(object: instance.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText], delegate: ChatTabDropDelegate(
            destination: instance.id,
            draggedId: $draggedId,
            onMove: { src, dst in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    chatManager.moveInstance(from: src, to: dst)
                }
            }
        ))
        .contextMenu {
            if let idx = chatManager.instances.firstIndex(where: { $0.id == instance.id }) {
                if idx > 0 {
                    Button("Move Left") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            chatManager.moveInstanceUp(id: instance.id)
                        }
                    }
                }
                if idx < chatManager.instances.count - 1 {
                    Button("Move Right") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                            chatManager.moveInstanceDown(id: instance.id)
                        }
                    }
                }
                Divider()
            }
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
            Button(instance.isMuted ? "Unmute Notifications" : "Mute Notifications") {
                chatManager.toggleMute(id: instance.id)
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


private struct ChatTabDropDelegate: DropDelegate {
    let destination: UUID
    @Binding var draggedId: UUID?
    let onMove: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedId, dragged != destination else { return }
        onMove(dragged, destination)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedId = nil
        return true
    }
}
