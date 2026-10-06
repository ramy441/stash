import Foundation

struct HistoryEntry: Identifiable {
    let id: Int
    let date: Date
    let source: String
    let text: String
}

enum HistoryStore {
    static let url = Paths.support.appendingPathComponent("history.log")
    static let displayLimit = 200
    /// Records are capped at `ClipboardMonitor.maxLength`, so a handful of huge clips can fill
    /// any fixed tail. Start small and widen until the tail holds a full page or reaches the top.
    private static let firstTailBytes: UInt64 = 256_000

    static func load() -> [HistoryEntry] {
        var tail = firstTailBytes
        while true {
            let (entries, reachedStart) = load(tailBytes: tail)
            if entries.count >= displayLimit || reachedStart { return entries }
            tail *= 4
        }
    }

    private static func load(tailBytes: UInt64) -> (entries: [HistoryEntry], reachedStart: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return ([], true) }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd(), size > 0 else { return ([], true) }

        let start = size > tailBytes ? size - tailBytes : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              var bytes = try? handle.readToEnd() else { return ([], true) }

        var offset = Int(start)
        if start > 0 {
            // chunk may start mid-record — drop up to the first newline so only whole records parse
            guard let newlineIndex = bytes.firstIndex(of: 0x0A) else { return ([], false) }
            let dropCount = newlineIndex - bytes.startIndex + 1
            bytes.removeFirst(dropCount)
            offset += dropCount
        }

        let contents = String(decoding: bytes, as: UTF8.self)
        let formatter = ISO8601DateFormatter()

        var entries: [HistoryEntry] = []
        var lineStart = offset
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let lineByteLength = line.utf8.count + 1
            defer { lineStart += lineByteLength }
            guard !line.isEmpty else { continue }
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3, let date = formatter.date(from: String(fields[0])) else { continue }
            // id = byte offset of the record's line start — stable regardless of where tail-reading began
            entries.append(HistoryEntry(id: lineStart, date: date,
                                        source: unescape(String(fields[1])),
                                        text: unescape(String(fields[2]))))
        }
        return (Array(entries.reversed().prefix(displayLimit)), start == 0)
    }

    @discardableResult
    static func append(_ text: String, source: String) -> Bool {
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(escape(source))\t\(escape(text))\n"
        let data = Data(line.utf8)
        if attemptWrite(data) { return true }
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        return attemptWrite(data)
    }

    static func clear() {
        do {
            try Data().write(to: url)
            restrictPermissions()
        } catch {
            Diagnostics.log("HistoryStore.clear: \(error)")
        }
    }

    /// Drops one record. `id` is its byte offset, which is what `load` hands the UI.
    static func remove(id: Int) {
        rewrite { offset, _ in offset != id }
    }

    /// Keeping every clip forever means one stray password sits in cleartext indefinitely.
    static func prune(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let formatter = ISO8601DateFormatter()
        rewrite { _, line in
            guard let tab = line.firstIndex(of: "\t"),
                  let date = formatter.date(from: String(line[line.startIndex..<tab])) else { return true }
            return date >= cutoff
        }
    }

    /// Rewrites the whole log. Only ever called from menu actions and launch, both on the
    /// main actor, so it cannot interleave with the monitor's append.
    private static func rewrite(keeping shouldKeep: (Int, Substring) -> Bool) {
        guard let data = try? Data(contentsOf: url) else { return }
        // lossy decode on purpose: load() already renders a corrupt file this way, and a
        // strict decode here would silently disable Delete on exactly the file that needs it
        let contents = String(decoding: data, as: UTF8.self)
        var kept = ""
        var offset = 0
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let byteLength = line.utf8.count + 1
            defer { offset += byteLength }
            guard !line.isEmpty, shouldKeep(offset, line) else { continue }
            kept += line + "\n"
        }
        guard kept.count != contents.count else { return }
        do {
            // atomic — this is the only copy of the data, and a partial write loses all of it.
            // The temp file lands in the same 0700 directory, so nothing is exposed.
            try Data(kept.utf8).write(to: url, options: .atomic)
            restrictPermissions()
            Diagnostics.log("history rewritten — \(contents.count - kept.count) chars dropped")
        } catch {
            Diagnostics.log("HistoryStore.rewrite failed — \(error)")
        }
    }

    /// Every clip you ever copied sits in this one file, so it is owner-only.
    static func restrictPermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func attemptWrite(_ data: Data) -> Bool {
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return true
            } catch {
                Diagnostics.log("HistoryStore.append: write threw — \(error)")
                return false
            }
        }
        if FileManager.default.fileExists(atPath: url.path) {
            Diagnostics.log("HistoryStore.append: open-for-writing failed on existing history.log")
            return false
        }
        do {
            try data.write(to: url)
            restrictPermissions()
            return true
        } catch {
            Diagnostics.log("HistoryStore.append: fallback write failed — \(error)")
            return false
        }
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var chars = text.makeIterator()
        while let char = chars.next() {
            guard char == "\\" else { result.append(char); continue }
            switch chars.next() {
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "\\": result.append("\\")
            case .some(let other): result.append("\\"); result.append(other)
            case nil: result.append("\\")
            }
        }
        return result
    }
}
