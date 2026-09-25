//
//  FanControlManager.swift
//  anotherNotch
//

import Combine
import Defaults
import Foundation
import IOKit

extension Defaults.Keys {
    public static let fanControlEnabled = Key<Bool>("fanControlEnabled", default: true)
    public static let fanControlManualMode = Key<Bool>("fanControlManualMode", default: false)
    public static let fanControlTargetRPMs = Key<[String: Double]>("fanControlTargetRPMs", default: [:])
}

public struct FanTelemetry: Identifiable, Equatable, Codable {
    public let id: Int
    public var name: String
    public var currentRPM: Double
    public var minRPM: Double
    public var maxRPM: Double
    public var targetRPM: Double
    public var isManual: Bool

    public init(
        id: Int,
        name: String,
        currentRPM: Double,
        minRPM: Double,
        maxRPM: Double,
        targetRPM: Double,
        isManual: Bool
    ) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.isManual = isManual
    }
}

public protocol SMCProvider: AnyObject {
    var isConnected: Bool { get }
    func fanCount() -> Int
    func readFanTelemetry(index: Int) -> FanTelemetry?
    func writeFanMode(index: Int, manual: Bool) -> Bool
    func writeFanTargetRPM(index: Int, rpm: Double) -> Bool
}

final class AppleSMCProvider: SMCProvider {
    private struct SMCVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct SMCPLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct SMCKeyInfoData {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct SMCParamStruct {
        var key: UInt32 = 0
        var vers = SMCVersion()
        var pLimitData = SMCPLimitData()
        var keyInfo = SMCKeyInfoData()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = (
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
            UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
        )
    }

    private var connection: io_connect_t = 0

    var isConnected: Bool {
        connection != 0
    }

    init() {
        openConnection()
    }

    deinit {
        closeConnection()
    }

    private func openConnection() {
        guard connection == 0 else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        if kr == kIOReturnSuccess {
            connection = conn
        }
    }

    private func closeConnection() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    private func callSMC(input: inout SMCParamStruct, output: inout SMCParamStruct) -> kern_return_t {
        guard connection != 0 else { return kIOReturnNotOpen }
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        return IOConnectCallStructMethod(
            connection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outputSize
        )
    }

    private func fourCharCode(_ str: String) -> UInt32 {
        str.utf8.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func readKey(_ keyStr: String) -> (dataType: UInt32, bytes: [UInt8])? {
        var inInfo = SMCParamStruct()
        var outInfo = SMCParamStruct()
        inInfo.key = fourCharCode(keyStr)
        inInfo.data8 = 9 // SMC_CMD_READ_KEYINFO
        guard callSMC(input: &inInfo, output: &outInfo) == kIOReturnSuccess, outInfo.result == 0 else {
            return nil
        }

        var inVal = SMCParamStruct()
        var outVal = SMCParamStruct()
        inVal.key = inInfo.key
        inVal.keyInfo.dataSize = outInfo.keyInfo.dataSize
        inVal.data8 = 5 // SMC_CMD_READ_BYTES
        guard callSMC(input: &inVal, output: &outVal) == kIOReturnSuccess, outVal.result == 0 else {
            return nil
        }

        let b = outVal.bytes
        let arr: [UInt8] = [
            b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
            b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15,
            b.16, b.17, b.18, b.19, b.20, b.21, b.22, b.23,
            b.24, b.25, b.26, b.27, b.28, b.29, b.30, b.31
        ]
        return (outInfo.keyInfo.dataType, Array(arr.prefix(Int(outInfo.keyInfo.dataSize))))
    }

    private func writeKey(_ keyStr: String, bytes: [UInt8]) -> Bool {
        var inInfo = SMCParamStruct()
        var outInfo = SMCParamStruct()
        inInfo.key = fourCharCode(keyStr)
        inInfo.data8 = 9
        guard callSMC(input: &inInfo, output: &outInfo) == kIOReturnSuccess, outInfo.result == 0 else {
            return false
        }

        var inVal = SMCParamStruct()
        var outVal = SMCParamStruct()
        inVal.key = inInfo.key
        inVal.keyInfo.dataSize = outInfo.keyInfo.dataSize
        inVal.data8 = 6 // SMC_CMD_WRITE_BYTES

        var tuple = inVal.bytes
        withUnsafeMutableBytes(of: &tuple) { ptr in
            for (idx, byte) in bytes.prefix(Int(outInfo.keyInfo.dataSize)).enumerated() {
                ptr[idx] = byte
            }
        }
        inVal.bytes = tuple

        let kr = callSMC(input: &inVal, output: &outVal)
        return kr == kIOReturnSuccess && outVal.result == 0
    }

    private func decodeRPM(type: UInt32, bytes: [UInt8]) -> Double {
        if type == 0x666c7420 && bytes.count >= 4 { // "flt "
            return Double(bytes.withUnsafeBytes { $0.load(as: Float32.self) })
        }
        if type == 0x66706532 && bytes.count >= 2 { // "fpe2"
            let intPart = (UInt16(bytes[0]) << 6) | (UInt16(bytes[1]) >> 2)
            let fracPart = Double(bytes[1] & 0x03) / 4.0
            return Double(intPart) + fracPart
        }
        if type == 0x75693136 && bytes.count >= 2 { // "ui16"
            return Double((UInt16(bytes[0]) << 8) | UInt16(bytes[1]))
        }
        return 0
    }

    private func encodeRPM(type: UInt32, rpm: Double) -> [UInt8] {
        if type == 0x666c7420 { // "flt "
            var f = Float32(rpm)
            return withUnsafeBytes(of: &f) { Array($0) }
        }
        if type == 0x66706532 { // "fpe2"
            let fixed = UInt16(rpm * 4.0)
            return [UInt8((fixed >> 8) & 0xff), UInt8(fixed & 0xff)]
        }
        let v = UInt16(rpm)
        return [UInt8((v >> 8) & 0xff), UInt8(v & 0xff)]
    }

    func fanCount() -> Int {
        guard let (_, bytes) = readKey("FNum"), !bytes.isEmpty else { return 0 }
        return Int(bytes[0])
    }

    func readFanTelemetry(index: Int) -> FanTelemetry? {
        guard let (curType, curBytes) = readKey("F\(index)Ac") else { return nil }
        let currentRPM = decodeRPM(type: curType, bytes: curBytes)

        var minRPM: Double = 1200
        if let (minType, minBytes) = readKey("F\(index)Mn") {
            minRPM = decodeRPM(type: minType, bytes: minBytes)
        }

        var maxRPM: Double = 5000
        if let (maxType, maxBytes) = readKey("F\(index)Mx") {
            maxRPM = decodeRPM(type: maxType, bytes: maxBytes)
        }

        var targetRPM: Double = currentRPM
        if let (targetType, targetBytes) = readKey("F\(index)Tg") {
            let tg = decodeRPM(type: targetType, bytes: targetBytes)
            if tg >= minRPM && tg <= maxRPM {
                targetRPM = tg
            }
        }

        var isManual = false
        if let (_, mdBytes) = readKey("F\(index)Md"), !mdBytes.isEmpty {
            isManual = mdBytes[0] != 0
        }

        let name: String
        let totalFans = fanCount()
        if totalFans == 2 {
            name = index == 0 ? "Left Fan" : "Right Fan"
        } else if totalFans == 1 {
            name = "Fan"
        } else {
            name = "Fan \(index + 1)"
        }

        return FanTelemetry(
            id: index,
            name: name,
            currentRPM: currentRPM,
            minRPM: minRPM,
            maxRPM: maxRPM,
            targetRPM: targetRPM,
            isManual: isManual
        )
    }

    func writeFanMode(index: Int, manual: Bool) -> Bool {
        writeKey("F\(index)Md", bytes: [manual ? 1 : 0])
    }

    func writeFanTargetRPM(index: Int, rpm: Double) -> Bool {
        var keyInfo = SMCParamStruct()
        var outInfo = SMCParamStruct()
        keyInfo.key = fourCharCode("F\(index)Tg")
        keyInfo.data8 = 9
        guard callSMC(input: &keyInfo, output: &outInfo) == kIOReturnSuccess, outInfo.result == 0 else {
            return false
        }
        let bytes = encodeRPM(type: outInfo.keyInfo.dataType, rpm: rpm)
        return writeKey("F\(index)Tg", bytes: bytes)
    }
}

@MainActor
final class FanControlManager: ObservableObject {
    static let shared = FanControlManager()

    @Published private(set) var fans: [FanTelemetry] = []
    @Published private(set) var isHardwareSupported: Bool = false
    @Published private(set) var isManualMode: Bool = false
    @Published private(set) var hasWritePermission: Bool = true
    @Published private(set) var permissionNotice: String?

    private let provider: SMCProvider
    private var timer: Timer?

    init(provider: SMCProvider = AppleSMCProvider()) {
        self.provider = provider
        checkHardware()
        if isHardwareSupported {
            isManualMode = Defaults[.fanControlManualMode]
            refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func checkHardware() {
        guard provider.isConnected else {
            isHardwareSupported = false
            return
        }
        let count = provider.fanCount()
        isHardwareSupported = count > 0
    }

    func startMonitoring() {
        guard isHardwareSupported else { return }
        refresh()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard isHardwareSupported else { return }
        let count = provider.fanCount()
        guard count > 0 else {
            fans = []
            return
        }

        var updatedFans: [FanTelemetry] = []
        let savedTargets = Defaults[.fanControlTargetRPMs]

        for i in 0..<count {
            if var fan = provider.readFanTelemetry(index: i) {
                if let saved = savedTargets[String(i)] {
                    fan.targetRPM = min(max(saved, fan.minRPM), fan.maxRPM)
                }
                updatedFans.append(fan)
            }
        }

        fans = updatedFans
    }

    func setMode(manual: Bool) {
        guard isHardwareSupported else { return }

        if manual {
            var success = true
            for fan in fans {
                let clampedTarget = min(max(fan.targetRPM, fan.minRPM), fan.maxRPM)
                let modeSet = provider.writeFanMode(index: fan.id, manual: true)
                let targetSet = provider.writeFanTargetRPM(index: fan.id, rpm: clampedTarget)
                if !modeSet || !targetSet {
                    success = false
                }
            }

            if success {
                isManualMode = true
                hasWritePermission = true
                permissionNotice = nil
                Defaults[.fanControlManualMode] = true
            } else {
                restoreAuto()
                hasWritePermission = false
                permissionNotice = "Elevated privileges required for manual fan control. Running in safe Auto mode."
                isManualMode = false
                Defaults[.fanControlManualMode] = false
            }
        } else {
            restoreAuto()
            isManualMode = false
            hasWritePermission = true
            permissionNotice = nil
            Defaults[.fanControlManualMode] = false
        }
        refresh()
    }

    func setTargetRPM(fanIndex: Int, rpm: Double) {
        guard isHardwareSupported, let index = fans.firstIndex(where: { $0.id == fanIndex }) else { return }
        let clamped = min(max(rpm, fans[index].minRPM), fans[index].maxRPM)
        fans[index].targetRPM = clamped

        var saved = Defaults[.fanControlTargetRPMs]
        saved[String(fanIndex)] = clamped
        Defaults[.fanControlTargetRPMs] = saved

        if isManualMode {
            let ok = provider.writeFanTargetRPM(index: fanIndex, rpm: clamped)
            if !ok {
                hasWritePermission = false
                permissionNotice = "Elevated privileges required for manual fan control. Running in safe Auto mode."
                restoreAuto()
            }
        }
    }

    func restoreAuto() {
        guard isHardwareSupported else { return }
        for fan in fans {
            _ = provider.writeFanMode(index: fan.id, manual: false)
        }
        isManualMode = false
        Defaults[.fanControlManualMode] = false
    }
}
