//
//  FanControlManager.swift
//  anotherNotch
//

import Combine
import Defaults
import Foundation
import IOKit
import SwiftUI

extension Defaults.Keys {
    public static let fanControlEnabled = Key<Bool>("fanControlEnabled", default: false)
    public static let fanControlManualMode = Key<Bool>("fanControlManualMode", default: false)
    public static let fanControlTargetRPMs = Key<[String: Double]>("fanControlTargetRPMs", default: [:])
    public static let fanControlAutoThreshold = Key<Double>("fanControlAutoThreshold", default: 60.0)
    public static let fanControlAutoMaxSpeed = Key<Int>("fanControlAutoMaxSpeed", default: 4500)
    public static let fanControlAutoAggressiveness = Key<Double>("fanControlAutoAggressiveness", default: 1.5)
    public static let fanControlAlertThreshold = Key<Double>("fanControlAlertThreshold", default: 85.0)
    public static let fanControlAlertEnabled = Key<Bool>("fanControlAlertEnabled", default: false)
    public static let fanControlTempUnit = Key<String>("fanControlTempUnit", default: "C")
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

extension FanControlManager {
    /// Color indicator aligned with ramp and alert thresholds.
    nonisolated static func temperatureColor(
        temp: Double,
        rampThreshold: Double = Defaults[.fanControlAutoThreshold],
        alertThreshold: Double = Defaults[.fanControlAlertThreshold]
    ) -> Color {
        let redThreshold = max(alertThreshold, rampThreshold + 10)
        if temp >= redThreshold {
            return .red
        } else if temp >= rampThreshold {
            return .orange
        } else {
            return .secondary
        }
    }

    /// Formats temperature in user's preferred unit (C or F)
    nonisolated static func formatTemperature(_ celsius: Double, unit: String? = nil) -> String {
        let unit = unit ?? Defaults[.fanControlTempUnit]
        if unit == "F" {
            let fahrenheit = celsius * 9/5 + 32
            return String(format: "%.0f°F", fahrenheit)
        }
        return String(format: "%.0f°C", celsius)
    }

    /// Dynamic thermal curve calculation:
    /// Maps 30°C–90°C linearly between minRPM and autoMaxSpeed,
    /// then blends according to autoAggressiveness (0.0 to 3.0, center 1.5).
    // ponytail: Dynamic normalized curve with response blending; upgrade to PID controller if thermal overshoot warrants it.
    nonisolated public static func calculateAutoTarget(
        temp: Double,
        minRPM: Double,
        maxRPM: Double,
        userMaxSpeed: Int,
        aggressiveness: Double = 1.5
    ) -> Double {
        let effectiveMin = max(1000.0, minRPM)
        let effectiveMax = min(max(effectiveMin, maxRPM), max(effectiveMin, Double(userMaxSpeed)))
        let ratio = min(1.0, max(0.0, (temp - 30.0) / 60.0))
        let baseSpeed = effectiveMin + ratio * (effectiveMax - effectiveMin)

        let target: Double
        if aggressiveness > 1.5 {
            let t = min(1.0, max(0.0, (aggressiveness - 1.5) / 1.5))
            target = (1.0 - t) * baseSpeed + t * effectiveMax
        } else {
            let t = min(1.0, max(0.0, aggressiveness / 1.5))
            target = (1.0 - t) * effectiveMin + t * baseSpeed
        }
        return min(effectiveMax, max(effectiveMin, target)).rounded()
    }
}

public protocol SMCProvider: AnyObject {
    var isConnected: Bool { get }
    func fanCount() -> Int
    func readFanTelemetry(index: Int) -> FanTelemetry?
    func readCurrentTemperature() -> Double?
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

    func readCurrentTemperature() -> Double? {
        let keys = [
            "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0E", "Tp0L", "Tp0P",
            "Te00", "Te01", "Te02", "Te03", "Te04", "Te05", "Te06", "Te07",
            "Td00", "Td01", "Td02", "Td03", "Td04", "Td05", "Td06", "Td07", "Td08", "Td09", "Td0A", "Td0C", "Td0D", "Td0E",
            "Tg04", "Tg05", "Tg0C", "Tg0D",
            "TC0P", "TC0E", "TC0F", "TC0D", "TC1C", "TC2C", "TC3C", "TC4C", "TC0H", "TCFP",
            "TG0P", "TG0D"
        ]
        var maxTemp: Double = -1.0
        for key in keys {
            if let (dataType, bytes) = readKey(key), !bytes.isEmpty {
                let temp = decodeRPM(type: dataType, bytes: bytes)
                if temp > 0.0 && temp < 130.0 && temp > maxTemp {
                    maxTemp = temp
                }
            }
        }
        return maxTemp > 0.0 ? maxTemp : nil
    }
}



// SMC Helper Provider - uses setuid root helper binary
final class SMCHelperProvider: SMCProvider, @unchecked Sendable {
    private let helperPath = "/usr/local/bin/smc-helper"
    private var fanCountCache: Int = 0
    private var fanCountCached = false
    private var cachedFans: [FanTelemetry] = []
    private var cachedTemperature: Double?
    private var lastFetchTime: Date = .distantPast

    private var bundledHelperPath: String? {
        if let path = Bundle.main.url(forResource: "smc-helper", withExtension: nil)?.path,
           FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let fallback = Bundle.main.bundlePath + "/Contents/Resources/smc-helper"
        if FileManager.default.isExecutableFile(atPath: fallback) {
            return fallback
        }
        let devPath = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("helpers/smc-helper/smc-helper").path
        if FileManager.default.isExecutableFile(atPath: devPath) {
            return devPath
        }
        return nil
    }

    private var readHelperPath: String {
        bundledHelperPath ?? helperPath
    }

    var isConnected: Bool {
        FileManager.default.isExecutableFile(atPath: helperPath) || bundledHelperPath != nil
    }
    
    func invalidateCache() {
        fanCountCached = false
        fanCountCache = 0
        cachedFans = []
        cachedTemperature = nil
        lastFetchTime = .distantPast
    }

    func readCurrentTemperature() -> Double? {
        let now = Date()
        if now.timeIntervalSince(lastFetchTime) >= 0.8 || cachedFans.isEmpty || cachedTemperature == nil {
            _ = populateTelemetry()
        }
        if cachedTemperature == nil, let bundled = bundledHelperPath {
            let bundledOut = runHelper(path: bundled, args: ["info"])
            if let tempMatch = bundledOut.firstMatch(of: /Current temperature: ([\d.]+) C/) {
                cachedTemperature = Double(tempMatch.output.1)
            }
        }
        return cachedTemperature
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
        var output = runHelper(path: readHelperPath, args: ["info"])
        if output.contains("Error") && readHelperPath != helperPath {
            output = runHelper(path: helperPath, args: ["info"])
        }
        if let match = output.firstMatch(of: /Total fans: (\d+)/) {
            let count = Int(match.output.1) ?? 0
            fanCountCache = count
            fanCountCached = true
        }
        if let tempMatch = output.firstMatch(of: /Current temperature: ([\d.]+) C/) {
            cachedTemperature = Double(tempMatch.output.1)
        } else if let bundled = bundledHelperPath {
            let bundledOut = runHelper(path: bundled, args: ["info"])
            if let tempMatch = bundledOut.firstMatch(of: /Current temperature: ([\d.]+) C/) {
                cachedTemperature = Double(tempMatch.output.1)
            }
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
            // ponytail: retry 3 times with 100ms delay for firmware sync
            for attempt in 0..<3 {
                let output = runHelper(args: ["auto", "\(index)"])
                if !output.contains("Error") && !output.contains("Failed") {
                    return true
                }
                if attempt < 2 {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
            return false
        }
    }

    func writeFanTargetRPM(index: Int, rpm: Double) -> Bool {
        cachedFans = []
        // ponytail: retry 3 times with 120ms delay for firmware unlock transition
        for attempt in 0..<3 {
            let output = runHelper(args: ["set", "\(index)", "\(Int(rpm))"])
            if !output.contains("Error") && !output.contains("Failed") {
                return true
            }
            if attempt < 2 {
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
        return false
    }

    private func runHelper(path: String? = nil, args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path ?? helperPath)
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
    @Published private(set) var currentTemperature: Double?
    @Published private(set) var isHardwareSupported: Bool = false
    @Published private(set) var isManualMode: Bool = false
    @Published private(set) var hasWritePermission: Bool = true
    @Published var permissionNotice: String?

    private let provider: any SMCProvider
    private var timer: Timer?
    private var isAutoRamped: Bool = false
    private var isInitializing: Bool = false
    private var lastRampedRPM: [Int: Double] = [:]

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
            Defaults[.fanControlEnabled] = true
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
            isInitializing = true
            refresh()
            isInitializing = false
            if Defaults[.fanControlEnabled] {
                startMonitoring()
            }
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
        if isHardwareSupported {
            currentTemperature = provider.readCurrentTemperature()
        }
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
        lastRampedRPM.removeAll()
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

        let temp = provider.readCurrentTemperature()
        currentTemperature = temp

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

        // Smooth dynamic auto-ramp curve
        // ponytail: Dynamic 30°C–90°C response curve with 50 RPM deadband; idles smoothly at minRPM below threshold.
        if !isInitializing, !isManualMode, let currentTemp = temp {
            let threshold = Defaults[.fanControlAutoThreshold]
            let maxSpeed = Defaults[.fanControlAutoMaxSpeed]
            let aggressiveness = Defaults[.fanControlAutoAggressiveness]
            let hysteresis = 3.0

            let isAboveThreshold = currentTemp >= threshold || (isAutoRamped && currentTemp >= (threshold - hysteresis))

            for fan in updatedFans {
                let minRPM = fan.minRPM > 0 ? fan.minRPM : 1200
                let maxRPM = fan.maxRPM > minRPM ? fan.maxRPM : 5000

                let target: Double
                if isAboveThreshold {
                    target = FanControlManager.calculateAutoTarget(
                        temp: currentTemp,
                        minRPM: minRPM,
                        maxRPM: maxRPM,
                        userMaxSpeed: maxSpeed,
                        aggressiveness: aggressiveness
                    )
                } else {
                    target = minRPM
                }

                let last = lastRampedRPM[fan.id] ?? 0
                if !isAutoRamped || abs(target - last) >= 50 {
                    _ = provider.writeFanMode(index: fan.id, manual: true)
                    _ = provider.writeFanTargetRPM(index: fan.id, rpm: target)
                    lastRampedRPM[fan.id] = target
                }
            }
            isAutoRamped = isAboveThreshold
        }
    }

    func setMode(manual: Bool) {
        guard isHardwareSupported else { return }

        if fans.isEmpty {
            refresh()
        }

        // Instantly update UI and defaults so animations run smoothly
        isAutoRamped = false
        lastRampedRPM.removeAll()
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

            let opSuccess = success
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                if opSuccess {
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

    func resetToDefaults() {
        Defaults[.fanControlEnabled] = true
        Defaults[.fanControlManualMode] = false
        Defaults[.fanControlTargetRPMs] = [:]
        Defaults[.fanControlAutoThreshold] = 60.0
        Defaults[.fanControlAutoMaxSpeed] = 4500
        Defaults[.fanControlAutoAggressiveness] = 1.5
        Defaults[.fanControlAlertThreshold] = 85.0
        Defaults[.fanControlAlertEnabled] = false
        Defaults[.fanControlTempUnit] = "C"
        restoreAuto()
    }

    func restoreAuto() {
        guard isHardwareSupported else { return }
        isAutoRamped = false
        lastRampedRPM.removeAll()
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
