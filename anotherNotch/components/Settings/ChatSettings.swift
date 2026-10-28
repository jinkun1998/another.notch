import Defaults
import SwiftUI
import WebKit

struct ChatSettings: View {
    @Default(.chatEnabled) private var chatEnabled
    @Default(.chatShowNotificationsInNotch) private var showNotifications
    @Default(.chatPlaySound) private var playSound
    @Default(.chatHibernateInactiveTabs) private var hibernateInactiveTabs
    @Default(.chatPageZoom) private var pageZoom
    @ObservedObject private var chatManager = ChatManager.shared

    @State private var showingClearConfirmation = false
    @State private var clearedDataNotice = false
    @State private var editingInstance: ChatInstance?
    @State private var editName: String = ""
    @State private var editURL: String = ""
    @State private var showingCustomAlert = false
    @State private var customName: String = ""
    @State private var customURL: String = "https://"
    @State private var draggedSettingsId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                generalSection
                servicesSection
                displaySection
                dataSection
            }
            .formStyle(.grouped)
        }
        .alert("Edit Service", isPresented: Binding(
            get: { editingInstance != nil },
            set: { if !$0 { editingInstance = nil } }
        )) {
            TextField("Display Name", text: $editName)
            TextField("Custom URL", text: $editURL)
            Button("Save") {
                if var inst = editingInstance {
                    inst.name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let trimmed = editURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    inst.customURLString = trimmed.isEmpty ? nil : trimmed
                    chatManager.updateInstance(inst)
                }
                editingInstance = nil
            }
            Button("Cancel", role: .cancel) {
                editingInstance = nil
            }
        }
        .alert("Add Custom Chat Service", isPresented: $showingCustomAlert) {
            TextField("Display Name", text: $customName)
            TextField("URL", text: $customURL)
            Button("Add") {
                chatManager.addInstance(
                    serviceType: .custom,
                    name: customName,
                    customURL: customURL
                )
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Clear all chat website data?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All Data & Sign Out", role: .destructive) {
                chatManager.clearData {
                    clearedDataNotice = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove cookies, stored logins, and offline cache for all configured accounts.")
        }
    }

    @ViewBuilder
    private var generalSection: some View {
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

            Button("Test Message Sneak Peek") {
                chatManager.testNotification()
            }
            .disabled(!chatEnabled)
        }
    }

    @ViewBuilder
    private var servicesSection: some View {
        Section("Configured Services") {
            ForEach(chatManager.instances) { instance in
                ChatServiceRowView(
                    instance: instance,
                    draggedId: $draggedSettingsId,
                    onEdit: { startEditing(instance) }
                )
            }

            Menu {
                ForEach(ChatServiceType.allCases) { type in
                    Button {
                        if type == .custom {
                            customName = "Custom"
                            customURL = "https://"
                            showingCustomAlert = true
                        } else {
                            chatManager.addInstance(serviceType: type)
                        }
                    } label: {
                        Label("Add \(type.rawValue)", systemImage: type.iconName)
                    }
                }
            } label: {
                Label("Add Service...", systemImage: "plus")
            }
        }
    }

    @ViewBuilder
    private var displaySection: some View {
        Section("Display & Hibernation") {
            Defaults.Toggle("Auto-hibernate inactive tabs (saves RAM)", key: .chatHibernateInactiveTabs)
                .disabled(!chatEnabled)

            HStack {
                Text("Page Zoom")
                Spacer()
                Picker("", selection: $pageZoom) {
                    Text("80%").tag(0.80)
                    Text("85%").tag(0.85)
                    Text("90% (Compact)").tag(0.90)
                    Text("100%").tag(1.00)
                }
                .labelsHidden()
                .frame(width: 140)
            }
            .disabled(!chatEnabled)
        }
    }

    @ViewBuilder
    private var dataSection: some View {
        Section("Session & Data") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Inactive Tabs RAM")
                        .font(.body)
                    Text("Unloads background web views from memory until next selected.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Free RAM") {
                    chatManager.unloadInactiveWebViews()
                }
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clear All Chat Sessions")
                        .font(.body)
                    Text("Logs out of all messaging accounts and deletes cached data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear All Data", role: .destructive) {
                    showingClearConfirmation = true
                }
            }
        }
    }

    private func startEditing(_ instance: ChatInstance) {
        editName = instance.displayName
        if let custom = instance.customURLString {
            editURL = custom
        } else if instance.serviceType == .custom {
            editURL = ""
        } else {
            editURL = instance.serviceType.defaultURL.absoluteString
        }
        editingInstance = instance
    }
}

private struct ChatServiceRowView: View {
    let instance: ChatInstance
    @Binding var draggedId: UUID?
    let onEdit: () -> Void

    @ObservedObject private var chatManager = ChatManager.shared

    private var isFirst: Bool {
        chatManager.instances.first?.id == instance.id
    }

    private var isLast: Bool {
        chatManager.instances.last?.id == instance.id
    }

    private var canRemove: Bool {
        chatManager.instances.count > 1
    }

    var body: some View {
        HStack(spacing: 12) {
            ChatServiceIconView(icon: instance.iconName, size: 14)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(instance.displayName)
                    .font(.body)
                Text(instance.url.absoluteString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 3) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        chatManager.moveInstanceUp(id: instance.id)
                    }
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isFirst ? Color.gray.opacity(0.3) : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isFirst)
                .help("Move up")

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        chatManager.moveInstanceDown(id: instance.id)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isLast ? Color.gray.opacity(0.3) : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isLast)
                .help("Move down")
            }

            Button {
                chatManager.toggleMute(id: instance.id)
            } label: {
                Image(systemName: instance.isMuted ? "bell.slash.fill" : "bell")
                    .foregroundStyle(instance.isMuted ? .red.opacity(0.85) : .secondary)
            }
            .buttonStyle(.plain)
            .help(instance.isMuted ? "Unmute notifications" : "Mute notifications")

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Edit name or URL")

            Button {
                chatManager.duplicateInstance(id: instance.id)
            } label: {
                Image(systemName: "plus.square.on.square")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Duplicate account (isolated session)")

            Button {
                chatManager.clearData(for: instance.id) {}
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear session for this account")

            if canRemove {
                Button(role: .destructive) {
                    chatManager.removeInstance(id: instance.id)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Remove service")
            }
        }
        .padding(.vertical, 3)
        .opacity(draggedId == instance.id ? 0.45 : 1.0)
        .onDrag {
            draggedId = instance.id
            return NSItemProvider(object: instance.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText], delegate: SettingsServiceDropDelegate(
            destination: instance.id,
            draggedId: $draggedId,
            onMove: { src, dst in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    chatManager.moveInstance(from: src, to: dst)
                }
            }
        ))
    }
}

private struct SettingsServiceDropDelegate: DropDelegate {
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
