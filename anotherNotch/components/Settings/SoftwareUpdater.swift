//
//  SoftwareUpdater.swift
//  anotherNotch
//
//  Created by Richard Kunkli on 09/08/2024.
//

import Defaults
import SwiftUI
import Sparkle

final class SoftwareUpdateDelegate: NSObject, SPUUpdaterDelegate {
    static let shared = SoftwareUpdateDelegate()

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Defaults[.softwareUpdateChannel] == .beta ? ["beta"] : []
    }
}

final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        
        // Create our view model for our CheckForUpdatesView
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

struct UpdaterSettingsView: View {
    private let updater: SPUUpdater
    
    @State private var automaticallyChecksForUpdates: Bool
    @State private var automaticallyDownloadsUpdates: Bool
    
    init(updater: SPUUpdater) {
        self.updater = updater
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
    }
    
    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    updater.automaticallyChecksForUpdates = newValue
                }
            
            Toggle("Automatically download updates", isOn: $automaticallyDownloadsUpdates)
                .disabled(!automaticallyChecksForUpdates)
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    updater.automaticallyDownloadsUpdates = newValue
                }
        } header: {
            HStack {
                Text("Software updates")
            }
        }
    }
}

private struct LiquidGlassChannelSegmentedPicker: View {
    @Binding var selection: SoftwareUpdateChannel

    @Namespace private var selectionNamespace
    @State private var hoveredItem: SoftwareUpdateChannel?

    private let selectionAnimation = Animation.spring(response: 0.32, dampingFraction: 0.82)

    var body: some View {
        HStack(spacing: 12) {
            Text("Release channel")
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                ForEach(SoftwareUpdateChannel.allCases) { channel in
                    segment(for: channel)
                }
            }
            .padding(2)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            }
            .animation(selectionAnimation, value: selection)
        }
    }

    private func segment(for channel: SoftwareUpdateChannel) -> some View {
        let isSelected = selection == channel

        return Button {
            guard selection != channel else { return }
            withAnimation(selectionAnimation) {
                selection = channel
            }
        } label: {
            Text(channel.rawValue)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    if isSelected {
                        selectedSegmentBackground
                            .matchedGeometryEffect(id: "selectedChannelSegment", in: selectionNamespace)
                    } else if hoveredItem == channel {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            withAnimation(.easeOut(duration: 0.12)) {
                hoveredItem = isHovering ? channel : nil
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var selectedSegmentBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.effectiveAccent)
    }
}

struct SoftwareUpdateChannelPicker: View {
    @Default(.softwareUpdateChannel) private var updateChannel

    var body: some View {
        LiquidGlassChannelSegmentedPicker(selection: $updateChannel)
    }
}
