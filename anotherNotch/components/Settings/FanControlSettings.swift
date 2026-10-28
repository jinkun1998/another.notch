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
    @Default(.fanControlTempUnit) private var tempUnit
    @State private var showingHelperInstallPrompt = false

    var body: some View {
        let helperInstalled = FileManager.default.isExecutableFile(atPath: "/usr/local/bin/smc-helper")

        Form {
            // General & Hardware
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable Fan Control")
                            .font(.headline)
                        Text("Show fan telemetry and cooling controls in the notch.")
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
                                manager.startMonitoring()
                            } else {
                                fanControlEnabled = false
                                manager.stopMonitoring()
                                manager.restoreAuto()
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                LabeledContent("Temperature Unit") {
                    Picker("", selection: $tempUnit) {
                        Text("°C").tag("C")
                        Text("°F").tag("F")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                }

                HStack {
                    Image(systemName: manager.isHardwareSupported ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(manager.isHardwareSupported ? .green : .red)
                    Text(manager.isHardwareSupported ? "\(manager.fans.count) fan(s) detected" : "Hardware Not Supported")
                        .font(.subheadline)
                    Spacer()
                    if let temp = manager.currentTemperature {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.caption2)
                            Text(FanControlManager.formatTemperature(temp, unit: tempUnit))
                                .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(FanControlManager.temperatureColor(temp: temp, rampThreshold: autoThreshold, alertThreshold: alertThreshold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    } else if manager.isHardwareSupported {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.caption2)
                            Text("--")
                                .font(.caption.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            } header: {
                Text("Fan Control")
            }

            // Cooling Mode & Controls
            if manager.isHardwareSupported {
                Section {
                    Picker("Mode", selection: $manualMode) {
                        Text("Auto").tag(false)
                        Text("Manual").tag(true)
                    }
                    .pickerStyle(.segmented)
                    #if arch(arm64)
                    .disabled(!helperInstalled)
                    #endif
                    .onChange(of: manualMode) { _, isManual in
                        manager.setMode(manual: isManual)
                    }

                    #if arch(arm64)
                    if !helperInstalled {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Manual control requires the SMC helper.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Install") {
                                if manager.installSMCHelper() {
                                    fanControlEnabled = true
                                    FeatureModuleRegistry.shared.install(.fanControl)
                                }
                            }
                            .controlSize(.small)
                        }
                    } else if !manager.hasWritePermission {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text("SIP must be disabled for fan control writes on Apple Silicon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    #endif

                    if !manualMode {
                        HStack(spacing: 8) {
                            Text("Ramp Threshold")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $autoThreshold, in: 40...90, step: 1)
                                .controlSize(.small)
                            Text(FanControlManager.formatTemperature(autoThreshold, unit: tempUnit))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("Max Speed")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: Binding(
                                get: { Double(autoMaxSpeed) },
                                set: { autoMaxSpeed = Int($0) }
                            ), in: 1000...6000, step: 100)
                            .controlSize(.small)
                            Text("\(autoMaxSpeed) RPM")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("Aggressiveness")
                                .frame(width: 120, alignment: .leading)
                            Slider(value: $autoAggressiveness, in: 0.0...3.0, step: 0.1)
                                .controlSize(.small)
                            Text(String(format: "%.1fx", autoAggressiveness))
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                    } else {
                        ForEach(manager.fans) { fan in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(fan.name)
                                        .frame(width: 120, alignment: .leading)
                                    Slider(
                                        value: Binding(
                                            get: { fan.targetRPM },
                                            set: { manager.setTargetRPM(fanIndex: fan.id, rpm: $0) }
                                        ),
                                        in: fan.minRPM...fan.maxRPM,
                                        step: 50
                                    )
                                    .controlSize(.small)
                                    Text("\(Int(fan.targetRPM)) RPM")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 72, alignment: .trailing)
                                }
                                HStack(spacing: 6) {
                                    Spacer()
                                    Button("Min") { manager.setTargetRPM(fanIndex: fan.id, rpm: fan.minRPM) }
                                        .controlSize(.mini)
                                    Button("Mid") { manager.setTargetRPM(fanIndex: fan.id, rpm: (fan.minRPM + fan.maxRPM) / 2) }
                                        .controlSize(.mini)
                                    Button("Max") { manager.setTargetRPM(fanIndex: fan.id, rpm: fan.maxRPM) }
                                        .controlSize(.mini)
                                }
                            }
                            .padding(.vertical, 2)
                        }

                        Button("Restore System Auto Mode") {
                            manager.restoreAuto()
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Text("Cooling Controls")
                } footer: {
                    Text(manualMode ? "Manual targets operate within hardware safety limits." : "Fans ramp smoothly above threshold using dynamic response curve.")
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
                        Text("Notify when sensor exceeds threshold")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if alertEnabled {
                    HStack(spacing: 8) {
                        Text("Alert Threshold")
                            .frame(width: 120, alignment: .leading)
                        Slider(value: $alertThreshold, in: 70...100, step: 1)
                            .controlSize(.small)
                        Text(FanControlManager.formatTemperature(alertThreshold, unit: tempUnit))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            } header: {
                Text("Temperature Alerts")
            }

            // SMC Helper fallback (Apple Silicon only)
            #if arch(arm64)
            if !helperInstalled {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SMC Helper Not Installed")
                                .font(.subheadline.weight(.medium))
                            Text("Required for fan speed overrides on Apple Silicon.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Install Helper") {
                            if manager.installSMCHelper() {
                                fanControlEnabled = true
                                FeatureModuleRegistry.shared.install(.fanControl)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("Helper Tool")
                }
            }
            #endif

            // Reset to Defaults
            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        manager.resetToDefaults()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            } footer: {
                Text("Restores all fan control preferences and thresholds back to system defaults.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            manager.checkHardware()
            manager.refresh()
            manager.setNotchOpen(true)
        }
        .onDisappear {
            manager.setNotchOpen(false)
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
