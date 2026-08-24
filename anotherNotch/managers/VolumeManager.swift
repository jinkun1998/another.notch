//
//  VolumeManager.swift
//  anotherNotch
//
//  Created by JeanLouis on 22/08/2025.
//

import AppKit
import Combine
import CoreAudio
import Defaults
import Foundation
import ObjectiveC

final class VolumeManager: NSObject, ObservableObject {
    static let shared = VolumeManager()

    struct OutputDevice: Identifiable, Equatable {
        let id: AudioObjectID
        let name: String
        let transportType: UInt32
        let uid: String
        let modelUID: String
        let iconURL: URL?
        let bluetoothBatteryPercentage: Int?

        var isBluetooth: Bool {
            transportType == kAudioDeviceTransportTypeBluetooth
                || transportType == kAudioDeviceTransportTypeBluetoothLE
        }

        var icon: String {
            if isBluetooth && bluetoothBatteryPercentage != nil {
                return "airpodspro"
            }

            switch transportType {
            case kAudioDeviceTransportTypeBuiltIn:
                return "airplayaudio"
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
                return "headphones"
            case kAudioDeviceTransportTypeAirPlay:
                return "airplayaudio"
            case kAudioDeviceTransportTypeUSB,
                 kAudioDeviceTransportTypeHDMI,
                 kAudioDeviceTransportTypeDisplayPort,
                 kAudioDeviceTransportTypeThunderbolt,
                 kAudioDeviceTransportTypeAggregate:
                return "hifispeaker.2"
            default:
                return "speaker.wave.2"
            }
        }
    }

    @Published private(set) var rawVolume: Float = 0
    @Published private(set) var isMuted: Bool = false
    @Published private(set) var lastChangeAt: Date = .distantPast
    @Published private(set) var activeOutputDevice: OutputDevice?
    @Published private(set) var availableOutputDevices: [OutputDevice] = []
    @Published private(set) var isOutputDevicePickerPresented = false
    private var knownBluetoothDeviceIDs: Set<AudioObjectID> = []
    private var isFirstDeviceDiscovery: Bool = true

    let visibleDuration: TimeInterval = 1.2

    private var didInitialFetch = false
    private let step: Float32 = 1.0 / 16.0
    // Fallback software if hardware mute is not supported
    private var previousVolumeBeforeMute: Float32 = 0.2
    private var softwareMuted: Bool = false
    private var deviceVolumeListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private override init() {
        super.init()
        setupSystemListeners()
        refreshOutputDevices()
        setupAudioListener()
        fetchCurrentVolume()
    }

    var shouldShowOverlay: Bool { Date().timeIntervalSince(lastChangeAt) < visibleDuration }
    var activeOutputDeviceID: AudioObjectID { activeOutputDevice?.id ?? kAudioObjectUnknown }
    var activeOutputDeviceName: String { activeOutputDevice?.name ?? "Output" }
    var activeOutputDeviceTransportType: UInt32 { activeOutputDevice?.transportType ?? 0 }
    var activeOutputDeviceIcon: String { activeOutputDevice?.icon ?? "speaker.wave.2" }

    // MARK: - Public Control API
    @MainActor func increase(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current + delta))
        setAbsolute(target)
        AnotherNotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func decrease(stepDivisor: Float = 1.0) {
        let divisor = max(stepDivisor, 0.25)
        let delta = step / Float32(divisor)
        let current = readVolumeInternal() ?? rawVolume
        let target = max(0, min(1, current - delta))
        setAbsolute(target)
        AnotherNotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(target))
    }

    @MainActor func toggleMuteAction() {
        // Determine expected resulting state immediately and show HUD with that value
        let deviceID = systemOutputDeviceID()
        var willBeMuted = false
        var resultingVolume: Float32 = rawVolume

        if deviceID == kAudioObjectUnknown {
            willBeMuted = !softwareMuted
            resultingVolume = willBeMuted ? 0 : previousVolumeBeforeMute
        } else {
            let currentMuted = isMutedInternal()
            willBeMuted = !currentMuted
            resultingVolume = willBeMuted ? 0 : (readVolumeInternal() ?? rawVolume)
        }

        toggleMuteInternal()
        AnotherNotchViewCoordinator.shared.toggleSneakPeek(status: true, type: .volume, value: CGFloat(willBeMuted ? 0 : resultingVolume))
    }
    
    func refresh() { fetchCurrentVolume() }

    @MainActor func setOutputDevicePickerPresented(_ isPresented: Bool) {
        isOutputDevicePickerPresented = isPresented
    }

    @MainActor func selectOutputDevice(_ device: OutputDevice) {
        guard availableOutputDevices.contains(device) else { return }

        var deviceID = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            UInt32(MemoryLayout<AudioObjectID>.size),
            &deviceID
        ) == noErr else { return }

        refreshOutputDevices()
        setupAudioListener()
        fetchCurrentVolume()
    }

    func adjustRelative(delta: Float32) {
        if isMutedInternal() { toggleMuteInternal() }
        guard let current = readVolumeInternal() else {
            fetchCurrentVolume()
            return
        }
        let target = max(0, min(1, current + delta))
        writeVolumeInternal(target)  
        publish(volume: target, muted: isMutedInternal(), touchDate: true)
    }

    @MainActor func setAbsolute(_ value: Float32) {
        let clamped = max(0, min(1, value))
        let currentlyMuted = isMutedInternal()
        if currentlyMuted && clamped > 0 {
            toggleMuteInternal()
        }

        writeVolumeInternal(clamped)

        if clamped == 0 && !currentlyMuted {
            toggleMuteInternal()
        }

        publish(volume: clamped, muted: isMutedInternal(), touchDate: true)
    }

    // MARK: - CoreAudio Helpers
    private func systemOutputDeviceID() -> AudioObjectID {
        var defaultDeviceID = kAudioObjectUnknown
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &defaultDeviceID
        )
        if status != noErr { return kAudioObjectUnknown }
        return defaultDeviceID
    }

    func refreshOutputDevices() {
        let devices = outputDevices()
        let activeDeviceID = systemOutputDeviceID()
        let previousKnown = knownBluetoothDeviceIDs
        var currentKnown: Set<AudioObjectID> = []
        var newlyConnected: OutputDevice?

        for d in devices {
            if d.transportType == kAudioDeviceTransportTypeBluetooth || d.transportType == kAudioDeviceTransportTypeBluetoothLE {
                currentKnown.insert(d.id)
                if !isFirstDeviceDiscovery && !previousKnown.contains(d.id) {
                    newlyConnected = d
                }
            }
        }
        knownBluetoothDeviceIDs = currentKnown
        isFirstDeviceDiscovery = false

        DispatchQueue.main.async {
            self.availableOutputDevices = devices
            self.activeOutputDevice = devices.first { $0.id == activeDeviceID }
            if let device = newlyConnected, Defaults[.showBluetoothDeviceConnectionIndicator] {
                AnotherNotchViewCoordinator.shared.toggleExpandingView(
                    status: true,
                    type: .bluetoothDevice,
                    value: device.bluetoothBatteryPercentage.map { CGFloat($0) / 100 } ?? -1,
                    title: "Connected",
                    subtitle: device.name,
                    icon: device.icon
                )
            }
        }
    }

    private func outputDevices() -> [OutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize
        ) == noErr else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var deviceIDs = [AudioObjectID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard isAliveOutputDevice(deviceID) else { return nil }
            let name = deviceName(deviceID) ?? "Output Device"
            let transportType = deviceTransportType(deviceID)
            let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) ?? ""
            return OutputDevice(
                id: deviceID,
                name: name,
                transportType: transportType,
                uid: uid,
                modelUID: stringProperty(deviceID, selector: kAudioDevicePropertyModelUID) ?? "",
                iconURL: deviceIconURL(deviceID),
                bluetoothBatteryPercentage: BluetoothDeviceBridge.batteryPercentage(
                    outputUID: uid,
                    isBluetooth: transportType == kAudioDeviceTransportTypeBluetooth
                        || transportType == kAudioDeviceTransportTypeBluetoothLE
                )
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func isAliveOutputDevice(_ deviceID: AudioObjectID) -> Bool {
        var aliveAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &aliveAddress) else { return false }
        var alive: UInt32 = 0
        var aliveSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &aliveAddress, 0, nil, &aliveSize, &alive) == noErr,
              alive != 0
        else { return false }

        var streamsAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamsSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &streamsAddress, 0, nil, &streamsSize) == noErr,
              streamsSize >= MemoryLayout<AudioBufferList>.size
        else { return false }

        let buffers = UnsafeMutableRawPointer.allocate(
            byteCount: Int(streamsSize), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffers.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &streamsAddress, 0, nil, &streamsSize, buffers) == noErr
        else { return false }
        return buffers.assumingMemoryBound(to: AudioBufferList.self).pointee.mNumberBuffers > 0
    }

    private func deviceName(_ deviceID: AudioObjectID) -> String? {
        stringProperty(deviceID, selector: kAudioObjectPropertyName)
    }

    private func stringProperty(_ deviceID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var name: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &name) == noErr
        else { return nil }
        return name?.takeUnretainedValue() as String?
    }

    private func deviceIconURL(_ deviceID: AudioObjectID) -> URL? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIcon,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }
        var iconURL: Unmanaged<CFURL>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFURL>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &iconURL) == noErr
        else { return nil }
        return iconURL?.takeRetainedValue() as URL?
    }

    private func deviceTransportType(_ deviceID: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &transportType) == noErr
        else { return 0 }
        return transportType
    }

    private func setupSystemListeners() {
        addSystemListener(kAudioHardwarePropertyDefaultOutputDevice)
        addSystemListener(kAudioHardwarePropertyDevices)
    }

    private func addSystemListener(_ selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.refreshOutputDevices()
                self?.setupAudioListener()
                self?.fetchCurrentVolume()
            }
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, nil, listener
        ) == noErr else { return }
        systemListeners.append((address, listener))
    }

    private func fetchCurrentVolume() {
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }
        var volumes: [Float32] = []
        let candidateElements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2, 3, 4]
        for element in candidateElements {
            if let v = readValidatedScalar(deviceID: deviceID, element: element) {
                volumes.append(v)
            }
        }
        if !volumes.isEmpty {
            let avg = max(0, min(1, volumes.reduce(0, +) / Float32(volumes.count)))
            DispatchQueue.main.async {
                if self.rawVolume != avg {  
                    if self.didInitialFetch {
                        self.lastChangeAt = Date()
                    }
                }
                self.rawVolume = avg
                self.didInitialFetch = true

            }
        }

        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            var sizeNeeded: UInt32 = 0
            if AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
                sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
            {
                var muted: UInt32 = 0
                var mSize = sizeNeeded
                if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &mSize, &muted) == noErr
                {
                    let newMuted = muted != 0
                    DispatchQueue.main.async {
                        if self.isMuted != newMuted { self.lastChangeAt = Date() }
                        self.isMuted = newMuted
                    }
                }
            }
        }
    }

    private func setupAudioListener() {
        removeDeviceVolumeListeners()
        let deviceID = systemOutputDeviceID()
        guard deviceID != kAudioObjectUnknown else { return }

        var masterAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &masterAddr) {
            addDeviceVolumeListener(deviceID, address: masterAddr)
        } else {
            for ch in [UInt32(1), UInt32(2)] {
                var chAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioDevicePropertyScopeOutput,
                    mElement: ch
                )
                if AudioObjectHasProperty(deviceID, &chAddr) {
                    addDeviceVolumeListener(deviceID, address: chAddr)
                }
            }
        }

        // Mute
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(deviceID, &muteAddr) {
            addDeviceVolumeListener(deviceID, address: muteAddr)
        }
    }

    private func addDeviceVolumeListener(_ deviceID: AudioObjectID, address: AudioObjectPropertyAddress) {
        var address = address
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.fetchCurrentVolume()
        }
        guard AudioObjectAddPropertyListenerBlock(deviceID, &address, nil, listener) == noErr else { return }
        deviceVolumeListeners.append((deviceID, address, listener))
    }

    private func removeDeviceVolumeListeners() {
        for (deviceID, storedAddress, listener) in deviceVolumeListeners {
            var address = storedAddress
            AudioObjectRemovePropertyListenerBlock(deviceID, &address, nil, listener)
        }
        deviceVolumeListeners.removeAll()
    }

    private func readVolumeInternal() -> Float32? {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return nil }
        var collected: [Float32] = []
        for el in [kAudioObjectPropertyElementMain, 1, 2, 3, 4] {
            if let v = readValidatedScalar(deviceID: deviceID, element: el) { collected.append(v) }
        }
        guard !collected.isEmpty else { return nil }
        return collected.reduce(0, +) / Float32(collected.count)
    }

    private func writeVolumeInternal(_ value: Float32) {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return }
        let newVal = max(0, min(1, value))

        var written = false
        if writeValidatedScalar(
            deviceID: deviceID, element: kAudioObjectPropertyElementMain, value: newVal)
        {
            written = true
        } else {
            var any = false
            for el in [UInt32](1...4) {
                if writeValidatedScalar(deviceID: deviceID, element: el, value: newVal) {
                    any = true
                }
            }
            written = any
        }
        if !written {
            // silent fail
        }
    }

    private func isMutedInternal() -> Bool {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown { return softwareMuted }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(deviceID, &muteAddr) else { return softwareMuted }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else { return softwareMuted }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return softwareMuted
    }

    private func toggleMuteInternal() {
        let deviceID = systemOutputDeviceID()
        if deviceID == kAudioObjectUnknown {
            performSoftwareMuteToggle(currentVolume: rawVolume)
            return
        }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if !AudioObjectHasProperty(deviceID, &muteAddr) {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &muteAddr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<UInt32>.size)
        else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
            return
        }
        var muted: UInt32 = 0
        var size = sizeNeeded
        if AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            var newVal: UInt32 = muted == 0 ? 1 : 0
            AudioObjectSetPropertyData(deviceID, &muteAddr, 0, nil, size, &newVal)
            let vol = readVolumeInternal() ?? rawVolume
            publish(volume: vol, muted: newVal != 0, touchDate: true)
        } else {
            let currentVol = readVolumeInternal() ?? rawVolume
            performSoftwareMuteToggle(currentVolume: currentVol)
        }
    }

    private func performSoftwareMuteToggle(currentVolume: Float32) {
        if softwareMuted {
            let restore = max(0, min(1, previousVolumeBeforeMute))
            writeVolumeInternal(restore)
            softwareMuted = false
            publish(volume: restore, muted: false, touchDate: true)
        } else {
            if currentVolume > 0.001 { previousVolumeBeforeMute = currentVolume }
            writeVolumeInternal(0)
            softwareMuted = true
            publish(volume: 0, muted: true, touchDate: true)
        }
    }

    private func readValidatedScalar(deviceID: AudioObjectID, element: UInt32) -> Float32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return nil }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return nil }
        var vol = Float32(0)
        var size = sizeNeeded
        let status = AudioObjectGetPropertyData(deviceID, &addr, 0, nil, &size, &vol)
        return status == noErr ? vol : nil
    }

    private func writeValidatedScalar(deviceID: AudioObjectID, element: UInt32, value: Float32)
        -> Bool
    {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
        guard AudioObjectHasProperty(deviceID, &addr) else { return false }
        var sizeNeeded: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &addr, 0, nil, &sizeNeeded) == noErr,
            sizeNeeded == UInt32(MemoryLayout<Float32>.size)
        else { return false }
        var val = value
        return AudioObjectSetPropertyData(deviceID, &addr, 0, nil, sizeNeeded, &val) == noErr
    }

    private func publish(volume: Float32, muted: Bool, touchDate: Bool) {
        DispatchQueue.main.async {
            if touchDate { self.lastChangeAt = Date() }
            self.rawVolume = volume
            self.isMuted = muted
        }
    }

}

extension Array where Element == Float32 {
    fileprivate var average: Float32? { isEmpty ? nil : reduce(0, +) / Float32(count) }
}

private enum BluetoothDeviceBridge {
    private static let frameworkLoaded = Bundle(
        path: "/System/Library/Frameworks/IOBluetooth.framework"
    )?.load() ?? false

    static func batteryPercentage(outputUID: String, isBluetooth: Bool) -> Int? {
        guard isBluetooth, !outputUID.isEmpty else { return nil }
        _ = frameworkLoaded
        guard
              let deviceClass = NSClassFromString("IOBluetoothDevice") as? NSObject.Type,
              let devices = deviceClass.perform(NSSelectorFromString("connectedDevices"))?
                .takeUnretainedValue() as? [NSObject]
        else { return nil }

        for device in devices where outputUIDMatchesDeviceAddress(outputUID, device: device) {
            let battery = BatteryLevels(
                single: batteryValue(device, selector: "batteryPercentSingle"),
                left: batteryValue(device, selector: "batteryPercentLeft"),
                right: batteryValue(device, selector: "batteryPercentRight"),
                caseBattery: batteryValue(device, selector: "batteryPercentCase")
            )
            if let single = battery.single {
                return single
            }

            let earbuds = [battery.left, battery.right].compactMap { $0 }
            if let lowest = earbuds.min() {
                return lowest
            }
        }
        return nil
    }

    private static func outputUIDMatchesDeviceAddress(_ outputUID: String, device: NSObject) -> Bool {
        let selector = NSSelectorFromString("addressString")
        guard device.responds(to: selector),
              let address = device.perform(selector)?.takeUnretainedValue() as? String
        else { return false }

        let normalizedAddress = address.filter(\.isHexDigit).lowercased()
        guard normalizedAddress.count == 12 else { return false }
        return outputUID.filter(\.isHexDigit).lowercased().contains(normalizedAddress)
    }

    private static func batteryValue(_ device: NSObject, selector name: String) -> Int? {
        let selector = NSSelectorFromString(name)
        guard device.responds(to: selector), let implementation = device.method(for: selector) else { return nil }
        typealias BatterySelector = @convention(c) (AnyObject, Selector) -> Int32
        let send = unsafeBitCast(implementation, to: BatterySelector.self)
        let percentage = send(device, selector)
        return (0...100).contains(percentage) ? Int(percentage) : nil
    }

    private struct BatteryLevels {
        let single: Int?
        let left: Int?
        let right: Int?
        let caseBattery: Int?
    }
}
