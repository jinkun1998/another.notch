//
//  FanControlManager.swift
//  anotherNotch
//

import Combine
import Defaults
import Foundation
import IOKit

extension Defaults.Keys {
    public static let fanControlEnabled = Key<Bool>("fanControlEnabled", default: false)
    public static let fanControlManualMode = Key<Bool>("fanControlManualMode", default: false)
    public static let fanControlTargetRPMs = Key<[String: Double]>("fanControlTargetRPMs", default: [:])
    public static let fanControlAutoThreshold = Key<Double>("fanControlAutoThreshold", default: 60.0)
    public static let fanControlAutoMaxSpeed = Key<Int>("fanControlAutoMaxSpeed", default: 4500)
    public static let fanControlAutoAggressiveness = Key<Double>("fanControlAutoAggressiveness", default: 1.5)
    public static let fanControlAlertThreshold = Key<Double>("fanControlAlertThreshold", default: 85.0)
    public static let fanControlAlertEnabled = Key<Bool>("fanControlAlertEnabled", default: false)
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

final class AppleSMCProvider: SMCProvider, @unchecked Sendable {
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



// SMC Helper Provider - uses setuid root helper binary
final class SMCHelperProvider: SMCProvider, @unchecked Sendable {
    private let helperPath = "/usr/local/bin/smc-helper"
    private var fanCountCache: Int = 0
    private var fanCountCached = false
    private var cachedFans: [FanTelemetry] = []
    private var lastFetchTime: Date = .distantPast

    var isConnected: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath)
    }
    
    func invalidateCache() {
        fanCountCached = false
        fanCountCache = 0
        cachedFans = []
        lastFetchTime = .distantPast
    }

    func fanCount() -> Int {
        if fanCountCached { return fanCountCache }
        _ = populateTelemetry()
        return fanCountCache
    }

    func readFanTelemetry(index: Int) -> FanTelemetry? {
        let now = Date()
        if now.timeIntervalSince(lastFetchTime) >= 0.8 || cachedFans.isEmpty {
            _ = populateTelemetry()
        }
        return cachedFans.first { $0.id == index }
    }

    private func populateTelemetry() -> [FanTelemetry] {
        let output = runHelper(args: ["info"])
        if let match = output.firstMatch(of: /Total fans: (\d+)/) {
            let count = Int(match.output.1) ?? 0
            fanCountCache = count
            fanCountCached = true
        }

        let pattern = #"Fan #(\d+):\s+Current speed: ([\d.]+) RPM\s+Min speed: ([\d.]+) RPM\s*\([^)]*\)\s+Max speed: ([\d.]+) RPM\s+Target speed: ([\d.]+) RPM"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: output.utf16.count)
        
        var fans: [FanTelemetry] = []
        regex?.enumerateMatches(in: output, options: [], range: range) { match, _, _ in
            guard let match = match,
                  match.numberOfRanges == 6,
                  let idxRange = Range(match.range(at: 1), in: output),
                  let currRange = Range(match.range(at: 2), in: output),
                  let minRange = Range(match.range(at: 3), in: output),
                  let maxRange = Range(match.range(at: 4), in: output),
                  let targetRange = Range(match.range(at: 5), in: output),
                  let id = Int(output[idxRange]),
                  let currentRPM = Double(output[currRange]),
                  let minRPM = Double(output[minRange]),
                  let maxRPM = Double(output[maxRange]),
                  let targetRPM = Double(output[targetRange]) else { return }
            
            fans.append(FanTelemetry(
                id: id,
                name: "Fan \(id)",
                currentRPM: currentRPM,
                minRPM: minRPM,
                maxRPM: maxRPM,
                targetRPM: targetRPM,
                isManual: targetRPM > 0 && targetRPM != maxRPM
            ))
        }
        
        if !fans.isEmpty {
            cachedFans = fans
            lastFetchTime = Date()
            fanCountCache = fans.count
            fanCountCached = true
        }
        return fans
    }

    func writeFanMode(index: Int, manual: Bool) -> Bool {
        cachedFans = []
        if manual {
            return true
        } else {
            let output = runHelper(args: ["auto", "\(index)"])
            return !output.contains("Error") && !output.contains("Failed")
        }
    }

    func writeFanTargetRPM(index: Int, rpm: Double) -> Bool {
        cachedFans = []
        let output = runHelper(args: ["set", "\(index)", "\(Int(rpm))"])
        return !output.contains("Error") && !output.contains("Failed")
    }

    private func runHelper(args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)
        process.arguments = args
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return "Error: \(error)"
        }
    }
}

@MainActor
final class FanControlManager: ObservableObject {
    static let shared = FanControlManager()

    @Published private(set) var fans: [FanTelemetry] = []
    @Published private(set) var isHardwareSupported: Bool = false
    @Published private(set) var isManualMode: Bool = false
    @Published private(set) var hasWritePermission: Bool = true
    @Published var permissionNotice: String?

    private let provider: any SMCProvider
    private var timer: Timer?

    static var isHelperInstalled: Bool {
        #if arch(arm64)
        return FileManager.default.isExecutableFile(atPath: "/usr/local/bin/smc-helper")
        #else
        return true
        #endif
    }

    init(provider: SMCProvider? = nil) {
        if !UserDefaults.standard.bool(forKey: "hasInitializedFanControlDefaults") {
            UserDefaults.standard.set(true, forKey: "hasInitializedFanControlDefaults")
            Defaults[.fanControlEnabled] = Self.isHelperInstalled
        }
        let useHelper = {
            #if arch(arm64)
            return true
            #else
            return false
            #endif
        }()
        let selectedProvider: any SMCProvider = provider ?? (useHelper ? SMCHelperProvider() : AppleSMCProvider())
        self.provider = selectedProvider
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
        // Invalidate cache to detect newly installed helper
        if let helperProvider = provider as? SMCHelperProvider {
            helperProvider.invalidateCache()
        }
        let count = provider.fanCount()
        isHardwareSupported = count > 0
    }

    @discardableResult
    func installSMCHelper() -> Bool {
        let helperPath = Bundle.main.bundlePath + "/Contents/Resources/smc-helper"
        let installPath = "/usr/local/bin/smc-helper"
        
        let script = """
        do shell script "cp '\(helperPath)' '\(installPath)' && chown root:wheel '\(installPath)' && chmod 4755 '\(installPath)'" with administrator privileges
        """
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                checkHardware()
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                print("Helper install failed: \(String(data: data, encoding: .utf8) ?? "unknown")")
                return false
            }
        } catch {
            print("Helper install failed: \(error)")
            return false
        }
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
                } else if fan.targetRPM < fan.minRPM {
                    fan.targetRPM = fan.minRPM
                } else if fan.targetRPM > fan.maxRPM {
                    fan.targetRPM = fan.maxRPM
                }
                fan.isManual = isManualMode
                updatedFans.append(fan)
            }
        }

        fans = updatedFans
    }

    func setMode(manual: Bool) {
        guard isHardwareSupported else { return }

        // Instantly update UI and defaults so animations run smoothly
        isManualMode = manual
        Defaults[.fanControlManualMode] = manual
        for i in 0..<fans.count {
            fans[i].isManual = manual
        }

        let provider = self.provider
        let currentFans = self.fans

        Task.detached(priority: .userInitiated) {
            var success = true
            if manual {
                for fan in currentFans {
                    let target = fan.targetRPM > 0 ? fan.targetRPM : (fan.currentRPM > 0 ? fan.currentRPM : fan.minRPM)
                    let clampedTarget = min(max(target, fan.minRPM), fan.maxRPM)
                    let modeSet = provider.writeFanMode(index: fan.id, manual: true)
                    let targetSet = provider.writeFanTargetRPM(index: fan.id, rpm: clampedTarget)
                    if !modeSet || !targetSet {
                        success = false
                    }
                }
            } else {
                for fan in currentFans {
                    let modeSet = provider.writeFanMode(index: fan.id, manual: false)
                    if !modeSet {
                        success = false
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if success {
                    self.hasWritePermission = true
                    self.permissionNotice = nil
                } else {
                    self.restoreAuto()
                    self.hasWritePermission = false
                    self.permissionNotice = "Elevated privileges required for manual fan control. Running in safe Auto mode."
                    self.isManualMode = false
                    Defaults[.fanControlManualMode] = false
                }
                self.refresh()
            }
        }
    }

    func setTargetRPM(fanIndex: Int, rpm: Double) {
        guard isHardwareSupported, let index = fans.firstIndex(where: { $0.id == fanIndex }) else { return }
        let clamped = min(max(rpm, fans[index].minRPM), fans[index].maxRPM)
        fans[index].targetRPM = clamped

        var saved = Defaults[.fanControlTargetRPMs]
        saved[String(fanIndex)] = clamped
        Defaults[.fanControlTargetRPMs] = saved

        if isManualMode {
            let provider = self.provider
            Task.detached(priority: .userInitiated) {
                let ok = provider.writeFanTargetRPM(index: fanIndex, rpm: clamped)
                if !ok {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        self.hasWritePermission = false
                        self.permissionNotice = "Elevated privileges required for manual fan control. Running in safe Auto mode."
                        self.restoreAuto()
                    }
                }
            }
        }
    }

    func restoreAuto() {
        guard isHardwareSupported else { return }
        isManualMode = false
        Defaults[.fanControlManualMode] = false
        for i in 0..<fans.count {
            fans[i].isManual = false
        }
        let provider = self.provider
        let currentFans = self.fans
        Task.detached(priority: .userInitiated) {
            for fan in currentFans {
                _ = provider.writeFanMode(index: fan.id, manual: false)
            }
        }
    }
}
