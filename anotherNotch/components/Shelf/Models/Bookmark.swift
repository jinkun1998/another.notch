//
//  Bookmark.swift
//  anotherNotch
//
//  Created by Alexander on 2025-10-08.
//

import Foundation
import AppKit

struct Bookmark: Sendable, Equatable, Codable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "Bookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a valid file URL or file does not exist at \(url.path)"])
        }
        do {
            self.data = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            self.data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            NSLog("⚠️ Created a standard bookmark for \(url.path)")
        }
    }

    func resolve() -> (url: URL?, refreshedData: Data?) {
        guard !data.isEmpty else { return (nil, nil) }
        if let resolved = resolve(options: [.withSecurityScope], refreshOptions: [.withSecurityScope]) {
            return resolved
        }
        if let resolved = resolve(options: [], refreshOptions: []) {
            return resolved
        }
        NSLog("❌ Failed to resolve bookmark")
        return (nil, nil)
    }

    func resolveURL() -> URL? {
        return resolve().url
    }

    var refreshedData: Data? {
        return resolve().refreshedData
    }

    private func resolve(
        options: URL.BookmarkResolutionOptions,
        refreshOptions: URL.BookmarkCreationOptions
    ) -> (url: URL?, refreshedData: Data?)? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: options,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        let refreshedData = isStale ? try? url.bookmarkData(options: refreshOptions) : nil
        return (url, refreshedData)
    }
    
    static func update(in items: inout [ShelfItem], for item: ShelfItem, newBookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        guard case .file = items[idx].kind else { return }
        items[idx].kind = ShelfItemKind.file(bookmark: newBookmark)
    }

    func validate() async -> Bool {
        let (url, _) = resolve()
        guard let url = url else { return false }
        return url.accessSecurityScopedResource { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    func withAccess<T: Sendable>(_ block: @Sendable (URL) async throws -> T) async rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try await url.accessSecurityScopedResource { url in
            try await block(url)
        }
    }

    func withAccess<T>(_ block: (URL) throws -> T) rethrows -> T? {
        let url = resolveURL()
        guard let url = url else { return nil }
        return try url.accessSecurityScopedResource { url in
            try block(url)
        }
    }
}
