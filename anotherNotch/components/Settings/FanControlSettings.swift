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
    @Default(.fanControlAutoThreshold) private var autoThreshold
    @Default(.fanControlAutoMaxSpeed) private var autoMaxSpeed
    @Default(.fanControlAutoAggressiveness) private var autoAggressiveness
    @Default(.fanControlAlertThreshold) private var alertThreshold
    @Default(.fanControlAlertEnabled) private var alertEnabled
    @State private var showingHelperInstallPrompt = false

    var body: some View {
        let helperInstalled = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/smc-helper")
        
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Enable Fan Control")
                                .font(.headline)
                            Text("Show fan speeds and control cooling modes in the notch.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { fanControlEnabled },
                            set: { enable in
                                if enable {
                                    #if arch(arm64)
                                    if !FanControlManager.isHelperInstalled {
                                        showingHelperInstallPrompt = true
                                        return
                                    }
                                    #endif
                                    fanControlEnabled = true
                                } else {
                                    fanControlEnabled = false
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                    }
                }
            } header: {
                Text("Fan Control")
            } footer: {
                Text("When disabled, fan monitoring and controls are hidden from the notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: manager.isHardwareSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(manager.isHardwareSupported ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        if manager.isHardwareSupported {
                            Text("Hardware Supported")
                                .font(.subheadline.weight(.medium))
                            Text("\(manager.fans.count) fan(s) detected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Hardware Not Supported")
                                .font(.subheadline.weight(.medium))
                            Text("No compatible fans found on this Mac")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if manager.isHardwareSupported {
                    ForEach(manager.fans) { fan in
                        HStack {
                            Image(systemName: "fan.fill")
                                .foregroundStyle(.secondary)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fan.name)
                                    .font(.subheadline)
                                Text("Min: \(Int(fan.minRPM)) RPM  •  Max: \(Int(fan.maxRPM)) RPM")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(fan.currentRPM)) RPM")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Hardware Status")
            } footer: {
                Text("Fan information is read from the System Management Controller (SMC).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Control Mode Section
            Section {
                Picker("Operating Mode", selection: $manualMode) {
                    Text("Auto (macOS Managed)").tag(false)
                    Text("Manual Control").tag(true)
                }
                .pickerStyle(.segmented)
                #if arch(arm64)
                .disabled(!helperInstalled)
                #endif
                .onChange(of: manualMode) { _, isManual in
                    manager.setMode(manual: isManual)
                }

                if #available(macOS 13.0, *) {
                    #if arch(arm64)
                    if helperInstalled {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manual Control Available")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.green)
                                Text("SMC helper installed. Fan speed can be controlled manually.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    } else {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manual Control Unavailable")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                                Text("Install the SMC helper to enable manual fan control on Apple Silicon.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    #else
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Manual Control Available")
                                .font(.caption.weight(.medium))
                            Text("Direct SMC access available on Intel Macs.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    #endif
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: helperInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(helperInstalled ? .green : .red)
                            Text(helperInstalled ? "Manual Control Available" : "Manual Control Unavailable")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(helperInstalled ? .green : .orange)
                        }
                        Text(helperInstalled 
                            ? "SMC helper installed. Fan speed can be controlled manually."
                            : "Install the SMC helper to enable manual fan control on Apple Silicon.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if !manager.hasWritePermission && helperInstalled {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fan Writes Failing")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                            Text("SIP must be disabled for fan control to work on Apple Silicon.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }

                Button("Restore macOS Auto Mode") {
                    manager.restoreAuto()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } header: {
                Text("Control Mode")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Auto: macOS manages fan speeds based on temperature.")
                    Text("Manual: You set target RPM; macOS thermal limits still apply.")
                    #if arch(arm64)
                    if !helperInstalled {
                        Text("On Apple Silicon, manual control requires the SMC helper (one-time admin install).")
                    } else if !manager.hasWritePermission {
                        Text("Note: Fan writes require SIP disabled on Apple Silicon.")
                    }
                    #else
                    Text("On Intel Macs, manual control works without additional setup.")
                    #endif
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Manual Fan Speeds
            if manualMode && manager.isHardwareSupported {
                Section {
                    ForEach(manager.fans) { fan in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "fan.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(fan.name)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                LabeledContent("Target") {
                                    Text("\(Int(fan.targetRPM)) RPM")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Slider(
                                value: Binding(
                                    get: { fan.targetRPM },
                                    set: { manager.setTargetRPM(fanIndex: fan.id, rpm: $0) }
                                ),
                                in: fan.minRPM...fan.maxRPM,
                                step: 50
                            ) {
                                EmptyView()
                            } minimumValueLabel: {
                                Text("\(Int(fan.minRPM))").font(.caption2).foregroundStyle(.secondary)
                            } maximumValueLabel: {
                                Text("\(Int(fan.maxRPM))").font(.caption2).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                Button("Min") { manager.setTargetRPM(fanIndex: fan.id, rpm: fan.minRPM) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                Button("Mid") { manager.setTargetRPM(fanIndex: fan.id, rpm: (fan.minRPM + fan.maxRPM) / 2) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                Button("Max") { manager.setTargetRPM(fanIndex: fan.id, rpm: fan.maxRPM) }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Manual Fan Speeds")
                } footer: {
                    Text("Set target RPM for each fan. macOS thermal limits still apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Auto Mode Settings
            if !manualMode && manager.isHardwareSupported {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        LabeledContent("Temperature Threshold") {
                            Text("\(Int(autoThreshold))°C")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $autoThreshold, in: 40...90, step: 1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("40°C").font(.caption2).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("90°C").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Fans ramp up when temperature exceeds this threshold.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledContent("Max Fan Speed") {
                            Text("\(autoMaxSpeed) RPM")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(autoMaxSpeed) },
                            set: { autoMaxSpeed = Int($0) }
                        ), in: 1000...6000, step: 100) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("1000 RPM").font(.caption2).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("6000 RPM").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("Maximum speed auto mode will request. Hardware limits still apply.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        LabeledContent("Aggressiveness") {
                            Text(String(format: "%.1f", autoAggressiveness))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $autoAggressiveness, in: 0.0...3.0, step: 0.1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("Gentle").font(.caption2).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("Aggressive").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("How quickly fans respond to temperature changes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 8) {
                            Label("0.0 = Quiet", systemImage: "hare.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label("1.5 = Balanced", systemImage: "speedometer")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Label("3.0 = Performance", systemImage: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Auto Mode Settings")
                } footer: {
                    Text("Auto mode adjusts fan speeds based on CPU/GPU temperature. Changes take effect immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Temperature Alerts
            Section {
                Toggle(isOn: $alertEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("High Temperature Alerts")
                            .font(.subheadline.weight(.medium))
                        Text("Show notification when any sensor exceeds threshold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: alertEnabled) { _, enabled in
                    if enabled && !manager.hasWritePermission {
                        // Can still monitor temps without write permission
                    }
                }

                if alertEnabled {
                    LabeledContent("Alert Threshold") {
                        Text("\(Int(alertThreshold))°C")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $alertThreshold, in: 70...100, step: 1) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("70°C").font(.caption2).foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("100°C").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text("Notification triggers when any temperature sensor exceeds this value.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Temperature Alerts")
            } footer: {
                Text("Alerts use system notifications. Works in both Auto and Manual modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // SMC Helper (Apple Silicon only)
            #if arch(arm64)
            Section {
                HStack(spacing: 12) {
                    Image(systemName: helperInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(helperInstalled ? .green : .red)
                    VStack(alignment: .leading, spacing: 4) {
                        if helperInstalled {
                            Text("SMC Helper Installed")
                                .font(.subheadline.weight(.medium))
                            Text("Manual fan control is enabled.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("SMC Helper Not Installed")
                                .font(.subheadline.weight(.medium))
                            Text("Required for manual fan control on Apple Silicon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !helperInstalled {
                        Button("Install Helper") {
                            if manager.installSMCHelper() {
                                fanControlEnabled = true
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .padding(.vertical, 4)

                if helperInstalled && !manager.hasWritePermission {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fan Writes Failing")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.red)
                            Text("SIP (System Integrity Protection) must be disabled for fan control to work.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            } header: {
                Text("SMC Helper")
            } footer: {
                Text("The helper is a small setuid binary installed to /usr/local/bin/smc-helper. It requires administrator password once. On Apple Silicon, SIP must also be disabled for fan writes to succeed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            #endif
        }
        .alert("SMC Helper", isPresented: $showingHelperInstallPrompt) {
            Button("Install Helper") {
                if manager.installSMCHelper() {
                    fanControlEnabled = true
                    FeatureModuleRegistry.shared.install(.fanControl)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Install the SMC helper to enable manual fan control on Apple Silicon.")
        }
    }
}
