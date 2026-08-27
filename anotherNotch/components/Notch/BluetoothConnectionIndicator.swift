import SwiftUI

struct BluetoothConnectionIndicator: View {
    let device: ExpandedItem
    let physicalNotchWidth: CGFloat
    let topRowHeight: CGFloat
    let rowCount: BluetoothDeviceIndicatorRows
    let showsDeviceName: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isIconTilted = false

    private var hasBattery: Bool {
        (0...1).contains(device.value)
    }

    var body: some View {
        Group {
            if rowCount == .two {
                VStack(spacing: 0) {
                    indicatorRow(showsDeviceName: false)
                        .frame(height: topRowHeight)
                    if showsDeviceName {
                        HStack(spacing: 0) {
                            Color.clear.frame(maxWidth: .infinity)
                            Text(device.subtitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: physicalNotchWidth)
                            Color.clear.frame(maxWidth: .infinity)
                        }
                        .frame(height: 22)
                    }
                }
            } else {
                indicatorRow(showsDeviceName: showsDeviceName)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isIconTilted = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isIconTilted = false
                }
            }
        }
    }

    private var icon: some View {
        Image(systemName: device.icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(isIconTilted ? 9 : 0))
    }

    private func indicatorRow(showsDeviceName: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                icon
                if showsDeviceName {
                    Text(device.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)

            Rectangle()
                .fill(.black)
                .frame(width: physicalNotchWidth)

            batteryStatus
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
    }

    @ViewBuilder
    private var batteryStatus: some View {
        if hasBattery {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: device.value)
                    .stroke(.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(device.value * 100))%")
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
            .frame(width: 24, height: 24)
        } else {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.green)
        }
    }
}
