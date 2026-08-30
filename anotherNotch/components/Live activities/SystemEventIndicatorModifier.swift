//
//  SystemEventIndicatorModifier.swift
//  anotherNotch
//

import Defaults
import SwiftUI

struct SystemEventIndicatorModifier: View {
    private let wingPadding: CGFloat = 10
    @EnvironmentObject var vm: AnotherNotchViewModel
    @Default(.closedHUDRows) private var closedHUDRows
    @Binding var eventType: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    var sendEventBack: (CGFloat) -> Void

    private var compactItemSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var wingWidth: CGFloat {
        compactItemSize * 1.5
    }

    var body: some View {
        Group {
            if closedHUDRows == .two && eventType != .mic {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        eventIcon
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, wingPadding + 2)

                        Rectangle()
                            .fill(.black)
                            .frame(width: max(0, vm.closedNotchSize.width - cornerRadiusInsets.closed.top))

                        if Defaults[.showClosedNotchHUDPercentage] {
                            valueLabel
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, wingPadding + 2)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                    .frame(height: vm.effectiveClosedNotchHeight)

                    DraggableProgressBar(value: $value, onChange: sendEventBack, restingHeight: 4)
                        .padding(.horizontal, 14)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
            } else {
                HStack(spacing: 4) {
                    eventIcon
                        .frame(width: wingWidth, height: compactItemSize + 20, alignment: .center)
                        .padding(.leading, wingPadding)

                    Rectangle()
                        .fill(.black)
                        .frame(width: vm.closedNotchSize.width - cornerRadiusInsets.closed.top)

                    if eventType == .mic {
                        valueLabel
                            .frame(width: wingWidth, height: compactItemSize + 20, alignment: .center)
                            .padding(.trailing, wingPadding)
                    } else if Defaults[.showClosedNotchHUDPercentage] {
                        valueLabel
                            .frame(width: wingWidth, height: compactItemSize + 20, alignment: .center)
                            .padding(.trailing, wingPadding)
                    } else {
                        DraggableProgressBar(value: $value, onChange: sendEventBack, restingHeight: 4)
                            .frame(width: wingWidth, height: compactItemSize + 20)
                            .padding(.trailing, wingPadding)
                    }
                }
            }
        }
        .symbolVariant(.fill)
        .imageScale(.large)
    }

    @ViewBuilder
    private var eventIcon: some View {
        switch eventType {
        case .volume:
            Image(systemName: icon.isEmpty ? speakerSymbol(value) : icon)
                .contentTransition(.interpolate)
                .opacity(value.isZero ? 0.6 : 1)
                .scaleEffect(value.isZero ? 0.85 : 1)
                .frame(width: 20, height: 15, alignment: .leading)
                .foregroundStyle(.white)
        case .brightness:
            Image(systemName: "sun.max.fill")
                .contentTransition(.symbolEffect)
                .frame(width: 20, height: 15)
                .foregroundStyle(.white)
        case .backlight:
            Image(systemName: value > 0.5 ? "light.max" : "light.min")
                .contentTransition(.interpolate)
                .frame(width: 20, height: 15)
                .foregroundStyle(.white)
        case .mic:
            Image(systemName: "mic")
                .symbolVariant(value > 0 ? .none : .slash)
                .contentTransition(.interpolate)
                .frame(width: 20, height: 15)
                .foregroundStyle(.white)
        default:
            EmptyView()
        }
    }

    private var valueLabel: some View {
        Text(eventType == .volume && value.isZero ? "Muted" : (eventType == .mic ? (value > 0 ? "Unmuted" : "Muted") : "\(Int(value * 100))%"))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(eventType == .mic ? .gray : .white)
            .monospacedDigit()
            .lineLimit(1)
            .frame(alignment: .trailing)
    }

    private func speakerSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0: "speaker.slash"
        case 0...0.3: "speaker.wave.1"
        case 0.3...0.8: "speaker.wave.2"
        default: "speaker.wave.3"
        }
    }
}

struct DraggableProgressBar: View {
    @Binding var value: CGFloat
    var onChange: ((CGFloat) -> Void)? = nil
    var restingHeight: CGFloat = 6

    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.tertiary)
                Capsule()
                    .fill(progressStyle)
                    .frame(width: max(0, min(geometry.size.width * value, geometry.size.width)))
                    .shadow(color: shadowColor, radius: 8, x: 3)
                    .opacity(value.isZero ? 0 : 1)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        withAnimation(.smooth(duration: 0.3)) {
                            isDragging = true
                            value = max(0, min(gesture.location.x / geometry.size.width, 1))
                            onChange?(value)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.smooth(duration: 0.3)) {
                            isDragging = false
                        }
                    }
            )
        }
        .frame(height: isDragging ? restingHeight + 3 : restingHeight)
    }

    private var progressStyle: AnyShapeStyle {
        Defaults[.enableGradient]
            ? AnyShapeStyle(LinearGradient(
                colors: Defaults[.systemEventIndicatorUseAccent]
                    ? [Color.effectiveAccent, Color.effectiveAccent.ensureMinimumBrightness(factor: 0.2)]
                    : [Color.white, Color.white.opacity(0.2)],
                startPoint: .trailing,
                endPoint: .leading
            ))
            : AnyShapeStyle(Defaults[.systemEventIndicatorUseAccent] ? Color.effectiveAccent : Color.white)
    }

    private var shadowColor: Color {
        Defaults[.systemEventIndicatorShadow]
            ? (Defaults[.systemEventIndicatorUseAccent]
                ? Color.effectiveAccent.ensureMinimumBrightness(factor: 0.7)
                : .white)
            : .clear
    }
}
