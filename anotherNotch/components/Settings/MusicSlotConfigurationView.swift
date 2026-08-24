//
//  MusicSlotConfigurationView.swift
//  anotherNotch
//
//  Created by Alexander on 2025-11-17.
//

import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct MusicSlotConfigurationView: View {
    @Default(.musicControlSlots) private var musicControlSlots

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            layoutPreview
            controlPalette

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    musicControlSlots = MusicControlButton.defaultLayout
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear(perform: normalizeSlots)
        .onChange(of: musicControlSlots) { _, _ in normalizeSlots() }
    }

    private var layoutPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Layout Preview")
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(MusicControlButton.defaultLayout.indices, id: \.self) { index in
                    let control = normalizedSlots[index]
                    if isLocked(index) {
                        controlPreview(control, locked: true)
                    } else {
                        controlPreview(control, locked: false)
                            .onDrag {
                                NSItemProvider(object: NSString(string: "slot:\(index)"))
                            }
                            .onDrop(of: [UTType.plainText.identifier], isTargeted: nil) {
                                handleDrop($0, to: index)
                            }
                    }
                }
            }
        }
    }

    private var controlPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drag a control onto an unlocked button")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(MusicControlButton.customizableOptions) { control in
                    Image(systemName: control.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 32, height: 32)
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .help(control.label)
                        .onDrag {
                            NSItemProvider(object: NSString(string: "control:\(control.rawValue)"))
                        }
                }
            }
        }
    }

    private func controlPreview(_ control: MusicControlButton, locked: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: control.iconName)
                .font(.system(size: control.prefersLargeScale ? 18 : 15, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(locked ? "\(control.label) • Locked" : control.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 82)
    }

    private var normalizedSlots: [MusicControlButton] {
        MusicControlButton.normalizedLayout(musicControlSlots)
    }

    private func isLocked(_ index: Int) -> Bool {
        !MusicControlButton.customizableSlotIndexes.contains(index)
    }

    private func handleDrop(_ providers: [NSItemProvider], to index: Int) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let payload = item as? NSString else { return }
            DispatchQueue.main.async {
                self.applyDrop(String(payload), to: index)
            }
        }
        return true
    }

    private func applyDrop(_ payload: String, to destination: Int) {
        guard MusicControlButton.customizableSlotIndexes.contains(destination) else { return }
        var slots = normalizedSlots

        if payload.hasPrefix("slot:"),
           let source = Int(payload.dropFirst("slot:".count)),
           MusicControlButton.customizableSlotIndexes.contains(source)
        {
            slots.swapAt(source, destination)
        } else if payload.hasPrefix("control:"),
                  let control = MusicControlButton(rawValue: String(payload.dropFirst("control:".count))),
                  MusicControlButton.customizableOptions.contains(control)
        {
            if let source = MusicControlButton.customizableSlotIndexes.first(where: {
                $0 != destination && slots[$0] == control
            }) {
                slots.swapAt(source, destination)
            } else {
                slots[destination] = control
            }
        } else {
            return
        }

        musicControlSlots = MusicControlButton.normalizedLayout(slots)
    }

    private func normalizeSlots() {
        let normalized = MusicControlButton.normalizedLayout(musicControlSlots)
        if musicControlSlots != normalized {
            musicControlSlots = normalized
        }
    }
}
