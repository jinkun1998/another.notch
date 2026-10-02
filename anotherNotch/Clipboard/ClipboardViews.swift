import Defaults
import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared
    @EnvironmentObject var vm: AnotherNotchViewModel
    @Default(.clipboardSearchMode) private var searchMode
    @Default(.clipboardPasteOnClick) private var pasteOnClick
    @State private var searchQuery = ""
    @State private var selectedEntryID: ClipboardEntry.ID?
    @State private var isClearHovered = false
    @State private var isConfirmingClear = false
    @FocusState private var isClearFocused: Bool

    private var filteredEntries: [ClipboardEntry] {
        ClipboardEntrySearch.results(for: searchQuery, in: store.entries, mode: searchMode)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if store.entries.isEmpty {
                ContentUnavailableView("Clipboard is empty", systemImage: "clipboard")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No clipboard matches",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search.")
                )
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredEntries) { entry in
                            ClipboardEntryRow(entry: entry, isSelected: selectedEntryID == entry.id) {
                                resetClearConfirmation()
                                guard selectedEntryID == nil else { return }
                                withAnimation(.easeOut(duration: 0.12)) {
                                    selectedEntryID = entry.id
                                }
                                let shouldPaste = pasteOnClick
                                let pasteTarget = shouldPaste ? store.pasteTarget() : nil
                                store.copy(entry)
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(160))
                                    guard selectedEntryID == entry.id else { return }
                                    vm.close()

                                    while vm.isClosingTransition {
                                        try? await Task.sleep(for: .milliseconds(16))
                                        guard !Task.isCancelled else { return }
                                    }
                                    guard vm.notchState == .closed else { return }
                                    store.promote(entry)

                                    guard shouldPaste else { return }
                                    await store.paste(entry, into: pasteTarget)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                }
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollIndicators(.automatic)
                .coordinateSpace(name: "clipboardScroll")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            resetClearConfirmation()
        })
        .onChange(of: searchQuery) { _, _ in resetClearConfirmation() }
        .onDisappear { resetClearConfirmation() }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            searchField
            clearButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 0)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search clipboard", text: $searchQuery)
                .textFieldStyle(.plain)

            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear clipboard search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var clearButton: some View {
        Button(action: confirmClear) {
            HStack(spacing: 5) {
                Image(systemName: isConfirmingClear ? "trash.fill" : "trash")
                (isConfirmingClear ? Text("Are you sure?") : Text("Clear"))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(isConfirmingClear ? .white : (store.entries.isEmpty ? Color.secondary.opacity(0.4) : .red))
            .padding(.horizontal, isConfirmingClear ? 12 : 10)
            .frame(height: 32)
            .background(
                isConfirmingClear
                    ? Color.red
                    : isClearHovered && !store.entries.isEmpty ? Color.red.opacity(0.16) : Color.red.opacity(0.08),
                in: Capsule()
            )
            .overlay(Capsule().stroke(Color.red.opacity(isConfirmingClear || store.entries.isEmpty ? 0 : 0.25)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.entries.isEmpty)
        .focused($isClearFocused)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isClearHovered = hovering
            }
            if !hovering {
                resetClearConfirmation()
            }
        }
        .onChange(of: isClearFocused) { _, focused in
            if !focused {
                resetClearConfirmation()
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.74), value: isConfirmingClear)
        .help(Text("Clear unpinned history"))
        .accessibilityLabel(isConfirmingClear ? Text("Confirm clear history") : Text("Clear unpinned history"))
    }

    private func confirmClear() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
            guard isConfirmingClear else {
                isConfirmingClear = true
                isClearFocused = true
                return
            }
            store.clear()
            isConfirmingClear = false
        }
    }

    private func resetClearConfirmation() {
        guard isConfirmingClear else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.74)) {
            isConfirmingClear = false
        }
    }
}

private struct ClipboardEntryRow: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared
    let entry: ClipboardEntry
    let isSelected: Bool
    let onSelect: () -> Void
    @State private var isHovering = false
    @State private var isDetailExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    onSelect()
                } label: {
                    HStack(spacing: 10) {
                        entryPreview
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if entry.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.orange)
                                }
                                Text(entry.kind == .url ? "URL" : entry.kind == .image ? "Image" : "Text")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(entry.isPinned ? .orange : .secondary)
                                Text(entry.timestamp, style: .time)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary.opacity(0.8))
                            }
                            if !isDetailExpanded {
                                Text(detail)
                                    .lineLimit(2)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isDetailExpanded {
                    actionButtons(isSticky: false)
                } else {
                    Color.clear
                        .frame(width: 116, height: 28)
                }
            }

            if isDetailExpanded {
                Button {
                    onSelect()
                } label: {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? Color.white.opacity(0.18)
                        : entry.isPinned
                            ? (isHovering ? Color.orange.opacity(0.16) : Color.orange.opacity(0.09))
                            : isHovering
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.05)
                )
        )
        .overlay(alignment: .topTrailing) {
            if isDetailExpanded {
                GeometryReader { geo in
                    let frame = geo.frame(in: .named("clipboardScroll"))
                    let cardMinY = frame.minY
                    let cardHeight = geo.size.height
                    let buttonHeight: CGFloat = 28
                    let topPadding: CGFloat = 8
                    let bottomPadding: CGFloat = 8

                    let targetY: CGFloat = 4
                    let rawOffset = targetY - cardMinY
                    let maxOffset = max(0, cardHeight - buttonHeight - topPadding - bottomPadding)
                    let offset = min(max(0, rawOffset), maxOffset)
                    let isSticky = offset > 0

                    actionButtons(isSticky: isSticky)
                        .padding(.top, topPadding)
                        .padding(.trailing, 10)
                        .offset(y: offset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                HapticFeedback.perform(.alignment)
            }
        }
        .contextMenu {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    store.togglePin(entry)
                }
            } label: {
                Label(entry.isPinned ? "Unpin" : "Pin to Top", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }
            Button {
                store.copy(entry)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive) {
                store.delete(entry)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func actionButtons(isSticky: Bool) -> some View {
        HStack(spacing: 4) {
            if canExpandDetail {
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isDetailExpanded.toggle()
                    }
                } label: {
                    Label(isDetailExpanded ? "Less" : "More", systemImage: isDetailExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 54, minHeight: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .linkColor))
                .accessibilityLabel(isDetailExpanded ? "Collapse clipboard preview" : "Expand clipboard preview")
            }

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    store.togglePin(entry)
                }
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .rotationEffect(.degrees(entry.isPinned ? 0 : 45))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(entry.isPinned ? Color.orange : (isHovering || isSticky ? Color.secondary : Color.clear))
            .accessibilityLabel(entry.isPinned ? "Unpin clipboard entry" : "Pin clipboard entry")

            Button {
                store.delete(entry)
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(isHovering || isSticky ? .red.opacity(0.8) : .secondary)
            .accessibilityLabel("Delete clipboard entry")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background {
            if isSticky {
                Capsule()
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSticky)
    }

    private var detail: String {
        if entry.kind == .image, let text = entry.extractedText, !text.isEmpty {
            return text
        }
        guard entry.kind == .image,
              let data = store.imageData(for: entry),
              let image = NSImage(data: data)
        else { return entry.preview }
        return "\(Int(image.size.width)) × \(Int(image.size.height)) · \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
    }

    private var canExpandDetail: Bool {
        detail.count > 80 || detail.contains(where: \.isNewline)
    }

    @ViewBuilder
    private var entryPreview: some View {
        if entry.kind == .image, let data = store.imageData(for: entry), let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            Image(systemName: entry.kind == .url ? "link" : "doc.on.clipboard")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
}

struct ClipboardHUD: View {
    @ObservedObject private var store = ClipboardHistoryStore.shared
    let entry: ClipboardEntry
    let physicalNotchMaskSize: CGSize

    var body: some View {
        if entry.kind == .image {
            ZStack {
                HStack(spacing: 10) {
                    Image(systemName: "clipboard.fill")
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if let data = store.imageData(for: entry), let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 46, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.black)
                        .frame(
                            width: physicalNotchMaskSize.width,
                            height: physicalNotchMaskSize.height
                        )
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: "clipboard.fill")
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                }
                GeometryReader { geometry in
                    MarqueeText(
                        .constant(entry.preview),
                        font: .system(size: 12),
                        nsFont: .caption1,
                        textColor: .secondary,
                        minDuration: 0.15,
                        frameWidth: geometry.size.width,
                        centerWhenFits: true
                    )
                }
                .frame(height: 16)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}
