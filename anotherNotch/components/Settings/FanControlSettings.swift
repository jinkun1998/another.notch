//
//  FanControlSettings.swift
//  anotherNotch
//

import Defaults
import SwiftUI

struct FanControlSettings: View {
    @ObservedObject private var manager = FanControlManager.shared
    @Default(.fanControlEnabled) private var fanControlEnabled
    @Default(.fanControlManualMode) private var manualMode

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Fan Control")
                            .font(.headline)
                        Text("Show fan telemetry and cooling controls in the notch.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle(key: .fanControlEnabled) {
                        EmptyView()
                    }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                }
            }

            Section("Hardware Status") {
                HStack {
                    Text("Hardware Support")
                    Spacer()
                    Text(manager.isHardwareSupported ? LocalizedStringKey("Supported") : LocalizedStringKey("No Fans Detected"))
                        .foregroundStyle(manager.isHardwareSupported ? .green : .secondary)
                }

                if manager.isHardwareSupported {
                    HStack {
                        Text("Detected Fans")
                        Spacer()
                        Text("\(manager.fans.count)")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(manager.fans) { fan in
                        HStack {
                            Text(fan.name)
                            Spacer()
                            Text("\(Int(fan.currentRPM)) RPM (\(Int(fan.minRPM)) - \(Int(fan.maxRPM)) RPM)")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Control Mode") {
                Picker("Operating Mode", selection: $manualMode) {
                    Text("Auto (macOS Managed)").tag(false)
                    Text("Manual Control").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: manualMode) { _, isManual in
                    manager.setMode(manual: isManual)
                }

                Text("Auto mode allows macOS thermal algorithms to manage fan speeds normally. Manual mode applies target RPMs within hardware-safe bounds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !manager.hasWritePermission {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Direct SMC speed writes require administrative privileges. System remains safely in Auto mode.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Restore macOS Auto Mode") {
                    manager.restoreAuto()
                }
            }
        }
    }
}
