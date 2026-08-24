//
//  SystemEventIndicatorModifier.swift
//  anotherNotch
//

import Defaults
import AppKit
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
                VStack(spacing: 5) {
                    HStack(spacing: 10) {
                        eventIcon
                        Spacer(minLength: 0)
                        if Defaults[.showClosedNotchHUDPercentage] {
                            valueLabel
                        }
                    }
                    DraggableProgressBar(value: $value, onChange: sendEventBack, restingHeight: 4)
                }
                .padding(.horizontal, 12)
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
            OutputDeviceSelectorButton {
                OutputDeviceIcon()
                    .contentTransition(.interpolate)
                    .opacity(value.isZero ? 0.6 : 1)
                    .scaleEffect(value.isZero ? 0.85 : 1)
                    .frame(width: 20, height: 15, alignment: .leading)
                    .foregroundStyle(.white)
            }
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

}

struct OutputDeviceSelectorButton<Label: View>: View {
    @EnvironmentObject private var vm: AnotherNotchViewModel
    @StateObject private var popoverController = OutputDevicePopoverController()
    @State private var anchorView: NSView?
    private let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Button {
            VolumeManager.shared.refreshOutputDevices()
            guard let anchorView else { return }
            popoverController.show(relativeTo: anchorView, viewModel: vm)
        } label: {
            label()
        }
        .buttonStyle(.plain)
        .overlay {
            OutputDevicePopoverAnchor { anchorView = $0 }
                .allowsHitTesting(false)
        }
    }
}

@MainActor
private final class OutputDevicePopoverController: NSObject, ObservableObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var viewModel: AnotherNotchViewModel?
    private var keepsNotchOpen = false
    private var eventMonitors: [Any] = []

    override init() {
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func show(relativeTo anchorView: NSView, viewModel: AnotherNotchViewModel) {
        guard !popover.isShown else { return }
        self.viewModel = viewModel
        keepsNotchOpen = false
        popover.contentViewController = NSHostingController(
            rootView: OutputDevicePicker { [weak self] device in
                self?.select(device)
            }
        )
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        VolumeManager.shared.setOutputDevicePickerPresented(true)
        installOutsideClickMonitors()
    }

    private func select(_ device: VolumeManager.OutputDevice) {
        keepsNotchOpen = true
        VolumeManager.shared.selectOutputDevice(device)
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitors()
        VolumeManager.shared.setOutputDevicePickerPresented(false)
        if !keepsNotchOpen {
            viewModel?.close()
        }
        keepsNotchOpen = false
    }

    private func installOutsideClickMonitors() {
        removeEventMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                self?.closeForOutsideClick(event)
            }
            return event
        }) {
            eventMonitors.append(monitor)
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor in
                self?.closeForOutsideClick(event)
            }
        }) {
            eventMonitors.append(monitor)
        }
    }

    private func closeForOutsideClick(_ event: NSEvent) {
        guard popover.isShown, !eventIsInsidePopover(event) else { return }
        popover.performClose(nil)
    }

    private func eventIsInsidePopover(_ event: NSEvent) -> Bool {
        guard let window = popover.contentViewController?.view.window else { return false }
        let location = event.window.map {
            $0.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        } ?? NSEvent.mouseLocation
        return window.frame.contains(location)
    }

    private func removeEventMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }
}

private struct OutputDevicePopoverAnchor: NSViewRepresentable {
    let didCreateView: (NSView) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        DispatchQueue.main.async {
            didCreateView(view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct OutputDeviceIcon: View {
    @ObservedObject private var volumeManager = VolumeManager.shared
    private let device: VolumeManager.OutputDevice?

    init(_ device: VolumeManager.OutputDevice? = nil) {
        self.device = device
    }

    var body: some View {
        let device = device ?? volumeManager.activeOutputDevice
        Image(systemName: device?.icon ?? volumeManager.activeOutputDeviceIcon)
    }
}

private struct OutputDevicePicker: View {
    @ObservedObject private var volumeManager = VolumeManager.shared
    let didSelectOutputDevice: (VolumeManager.OutputDevice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Output")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)

            if volumeManager.availableOutputDevices.isEmpty {
                Text("No output devices available")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(volumeManager.availableOutputDevices) { device in
                    Button {
                        didSelectOutputDevice(device)
                    } label: {
                        HStack(spacing: 10) {
                            OutputDeviceIcon(device)
                                .frame(width: 18)
                            Text(device.name)
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            if device.id == volumeManager.activeOutputDeviceID {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(.bottom, 6)
        .onAppear { volumeManager.refreshOutputDevices() }
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
