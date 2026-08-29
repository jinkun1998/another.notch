import AppKit
import Combine
import Defaults
import Fuse
import Foundation
import SwiftUI
import Vision

enum ClipboardEntryKind: String, Codable {
    case text
    case url
    case image
}

struct ClipboardEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let timestamp: Date
    let kind: ClipboardEntryKind
    fileprivate let value: String?
    fileprivate let imageFileName: String?
    fileprivate var ocrText: String?

    init(kind: ClipboardEntryKind, value: String? = nil, imageFileName: String? = nil, ocrText: String? = nil) {
        id = UUID()
        timestamp = Date()
        self.kind = kind
        self.value = value
        self.imageFileName = imageFileName
        self.ocrText = ocrText
    }

    var preview: String {
        switch kind {
        case .text, .url:
            value ?? ""
        case .image:
            "Image"
        }
    }

    var searchableText: String {
        [value, ocrText]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    var extractedText: String? {
        ocrText
    }
}

enum ClipboardEntrySearch {
    private static let fuzzy = Fuse(threshold: 0.7)
    private static let fuzzySearchLimit = 5_000

    static func results(for query: String, in entries: [ClipboardEntry], mode: ClipboardSearchMode) -> [ClipboardEntry] {
        guard !query.isEmpty else { return entries }

        switch mode {
        case .exact:
            return exact(query, in: entries)
        case .regex:
            return regex(query, in: entries)
        case .fuzzy:
            return fuzzy(query, in: entries)
        case .mixed:
            let exactResults = exact(query, in: entries)
            guard exactResults.isEmpty else { return exactResults }

            let regexResults = regex(query, in: entries)
            guard regexResults.isEmpty else { return regexResults }

            return fuzzy(query, in: entries)
        }
    }

    private static func exact(_ query: String, in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        entries.filter { $0.searchableText.range(of: query, options: .caseInsensitive) != nil }
    }

    private static func regex(_ query: String, in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        guard let expression = try? NSRegularExpression(pattern: query, options: .caseInsensitive) else { return [] }

        return entries.filter {
            let searchableText = $0.searchableText
            let range = NSRange(searchableText.startIndex..., in: searchableText)
            return expression.firstMatch(in: searchableText, range: range) != nil
        }
    }

    private static func fuzzy(_ query: String, in entries: [ClipboardEntry]) -> [ClipboardEntry] {
        let pattern = fuzzy.createPattern(from: query)
        return entries.enumerated()
            .compactMap { index, entry -> (entry: ClipboardEntry, score: Double, index: Int)? in
                let searchableText = String(entry.searchableText.prefix(fuzzySearchLimit))
                guard let result = fuzzy.search(pattern, in: searchableText) else { return nil }
                return (entry, result.score, index)
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.index < rhs.index : lhs.score < rhs.score
            }
            .map { $0.entry }
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()

    @Published private(set) var entries: [ClipboardEntry] = []
    @Published private(set) var hudEntry: ClipboardEntry?

    private let pasteboard = NSPasteboard.general
    private let fileManager = FileManager.default
    private let storageIdentifier = Bundle.main.bundleIdentifier ?? "anotherNotch"
    private let copySound = Bundle.main.url(forResource: "Knock", withExtension: "caf")
        .flatMap { NSSound(contentsOf: $0, byReference: true) }
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var hudTask: Task<Void, Never>?
    private var selfWriteSuppressionDeadline = Date.distantPast

    private var directory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent(storageIdentifier, isDirectory: true)
            .appendingPathComponent("ClipboardHistory", isDirectory: true)
    }

    private var metadataURL: URL {
        directory.appendingPathComponent("history.json")
    }

    private init() {
        createDirectory()
        load()
    }

    func startMonitoring() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.captureIfNeeded() }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        hudTask?.cancel()
    }

    func copy(_ entry: ClipboardEntry) {
        hudTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            hudEntry = nil
        }
        selfWriteSuppressionDeadline = Date().addingTimeInterval(0.75)

        switch entry.kind {
        case .text:
            pasteboard.clearContents()
            pasteboard.setString(entry.value ?? "", forType: .string)
        case .url:
            guard let value = entry.value, let url = URL(string: value) else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        case .image:
            guard let data = imageData(for: entry) else { return }
            pasteboard.clearContents()
            pasteboard.setData(data, forType: .png)
        }

        lastChangeCount = pasteboard.changeCount
        copySound?.play()
    }

    func delete(_ entry: ClipboardEntry) {
        entries.removeAll { $0.id == entry.id }
        removeImageFile(for: entry)
        persist()
    }

    func clear() {
        entries.forEach { removeImageFile(for: $0) }
        entries = []
        hudEntry = nil
        persist()
    }

    func enforceRetention() {
        trim()
    }

    func imageData(for entry: ClipboardEntry) -> Data? {
        guard let fileName = entry.imageFileName else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    private func captureIfNeeded() {
        guard Defaults[.clipboardHistoryEnabled], pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard Date() >= selfWriteSuppressionDeadline else { return }

        if let urlValue = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")), isURL(urlValue) {
            append(kind: .url, value: urlValue)
        } else if let imageData = pngData(), imageData.count <= imageLimitBytes {
            let fileName = "\(UUID().uuidString).png"
            do {
                try imageData.write(to: directory.appendingPathComponent(fileName), options: .atomic)
                append(kind: .image, imageFileName: fileName)
            } catch {
                return
            }
        } else if let text = pasteboard.string(forType: .string), !text.isEmpty {
            append(kind: isURL(text) ? .url : .text, value: text)
        }
    }

    private var imageLimitBytes: Int {
        Defaults[.clipboardImageLimitMB] * 1_024 * 1_024
    }

    private func append(kind: ClipboardEntryKind, value: String? = nil, imageFileName: String? = nil) {
        let entry = ClipboardEntry(kind: kind, value: value, imageFileName: imageFileName)
        guard fingerprint(for: entry) != entries.first.map({ fingerprint(for: $0) }) else {
            removeImageFile(for: entry)
            return
        }

        entries.insert(entry, at: 0)
        while entries.count > Defaults[.clipboardHistoryLimit] {
            removeImageFile(for: entries.removeLast())
        }
        persist()
        recognizeText(in: entry)
        showHUD(for: entry)
    }

    private func showHUD(for entry: ClipboardEntry) {
        hudTask?.cancel()
        withAnimation(.easeOut(duration: 0.16)) {
            hudEntry = entry
        }
        hudTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.24)) {
                self?.hudEntry = nil
            }
        }
    }

    private func fingerprint(for entry: ClipboardEntry) -> String {
        if entry.kind == .image, let data = imageData(for: entry) {
            return "image:\(data.hashValue)"
        }
        return "\(entry.kind.rawValue):\(entry.value ?? "")"
    }

    private func isURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return ["http", "https", "ftp", "mailto"].contains(scheme)
    }

    private func pngData() -> Data? {
        if let data = pasteboard.data(forType: .png) {
            return data
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }

    private func recognizeText(in entry: ClipboardEntry) {
        guard Defaults[.clipboardOCREnabled], entry.kind == .image, let data = imageData(for: entry) else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let text = Self.recognizedText(in: data) else {
                print("🔍 OCR: no text found in image \(entry.id)")
                return
            }
            print("✅ OCR: recognized \(text.count) chars in image \(entry.id)")
            await self?.storeOCRText(text, for: entry.id)
        }
    }

    private func storeOCRText(_ text: String, for entryID: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), entries[index].ocrText != text else { return }
        var entry = entries[index]
        entry.ocrText = text
        entries[index] = entry
        persist()
    }

    nonisolated private static func recognizedText(in data: Data) -> String? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            print("⚠️ OCR: failed to create CGImage from clipboard data")
            return nil
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true

        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            print("❌ OCR: recognition failed – \(error.localizedDescription)")
            return nil
        }

        let text = request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    private func load() {
        guard let data = try? Data(contentsOf: metadataURL),
              let decoded = try? JSONDecoder().decode([ClipboardEntry].self, from: data)
        else { return }
        entries = decoded.filter { $0.kind != .image || imageData(for: $0) != nil }
        trim()
        entries.filter { $0.kind == .image && $0.ocrText == nil }.forEach(recognizeText)
    }

    private func trim() {
        while entries.count > Defaults[.clipboardHistoryLimit] {
            removeImageFile(for: entries.removeLast())
        }
        persist()
    }

    private func persist() {
        createDirectory()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: metadataURL, options: .atomic)
    }

    private func createDirectory() {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func removeImageFile(for entry: ClipboardEntry) {
        guard let fileName = entry.imageFileName else { return }
        try? fileManager.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
