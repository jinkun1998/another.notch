//
//  FanControlView.swift
//  anotherNotch
//

import SwiftUI

struct FanControlView: View {
    @ObservedObject private var manager = FanControlManager.shared

    var body: some View {
        VStack(spacing: 10) {
            header
            if manager.fans.isEmpty {
                emptyView
            } else {
                fanCards
                if let notice = manager.permissionNotice {
                    noticeBanner(notice)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .onAppear {
            manager.startMonitoring()
        }
        .onDisappear {
            manager.stopMonitoring()
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "fan.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Fan Control")
                    .font(.headline)
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 2) {
                modeButton(title: "Auto", isSelected: !manager.isManualMode) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        manager.setMode(manual: false)
                    }
                }
                modeButton(title: "Manual", isSelected: manager.isManualMode) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        manager.setMode(manual: true)
                    }
                }
            }
            .padding(2)
            .background(Color.white.opacity(0.1), in: Capsule())
        }
        .frame(height: 24)
    }

    private func modeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(
                    isSelected ? Color.accentColor : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private var fanCards: some View {
        HStack(spacing: 10) {
            ForEach(manager.fans) { fan in
                fanCard(fan)
            }
        }
    }

    private func fanCard(_ fan: FanTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 5) {
                    AnimatedFanIcon(rpm: fan.currentRPM)
                    Text(fan.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                Spacer()
                Text(fan.isManual ? "Manual" : "Auto")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(fan.isManual ? Color.orange : Color.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (fan.isManual ? Color.orange : Color.green).opacity(0.18),
                        in: Capsule()
                    )
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(Int(fan.currentRPM))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("RPM")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            gaugeBar(fan)

            HStack {
                Text("\(Int(fan.minRPM))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(fan.maxRPM))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if manager.isManualMode {
                manualControls(fan)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
    }

    private func gaugeBar(_ fan: FanTelemetry) -> some View {
        let range = max(1.0, fan.maxRPM - fan.minRPM)
        let ratio = max(0.0, min(1.0, (fan.currentRPM - fan.minRPM) / range))

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 5)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, ratio > 0.6 ? (ratio > 0.85 ? Color.red : Color.orange) : Color.teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(5, geo.size.width * CGFloat(ratio)), height: 5)
            }
        }
        .frame(height: 5)
    }

    private func manualControls(_ fan: FanTelemetry) -> some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { fan.targetRPM },
                    set: { manager.setTargetRPM(fanIndex: fan.id, rpm: $0) }
                ),
                in: fan.minRPM...fan.maxRPM,
                step: 50
            )
            .controlSize(.mini)

            HStack(spacing: 4) {
                presetButton(title: "Min", fan: fan, value: fan.minRPM)
                presetButton(title: "Mid", fan: fan, value: (fan.minRPM + fan.maxRPM) / 2)
                presetButton(title: "Max", fan: fan, value: fan.maxRPM)
                Spacer()
                Text("Target: \(Int(fan.targetRPM))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }

    private func presetButton(title: String, fan: FanTelemetry, value: Double) -> some View {
        Button(title) {
            manager.setTargetRPM(fanIndex: fan.id, rpm: value)
        }
        .font(.system(size: 9, weight: .medium))
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(notice)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Fans Detected",
            systemImage: "fan.slash",
            description: Text("This Mac has no detected fans or hardware telemetry is unavailable.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AnimatedFanIcon: View {
    let rpm: Double
    @State private var isSpinning = false

    var body: some View {
        Image(systemName: "fanblades.fill")
            .font(.caption)
            .foregroundStyle(rpm > 0 ? Color.teal : Color.secondary)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(
                rpm > 0
                    ? .linear(duration: max(0.4, 2500.0 / max(400, rpm))).repeatForever(autoreverses: false)
                    : .default,
                value: isSpinning
            )
            .onAppear {
                if rpm > 0 {
                    isSpinning = true
                }
            }
            .onChange(of: rpm) { _, newRPM in
                isSpinning = newRPM > 0
            }
    }
}
