import Foundation

/// Append-only trace of the things that are invisible from outside the app —
/// whether the monitor is running, what it refused to record, why a write failed.
enum Diagnostics {
    private static let queue = DispatchQueue(label: "stash.diagnostics")
    private static let url = Paths.support.appendingPathComponent("events.log")

    /// When you copied, and how often, is metadata worth the same protection as the clips.
    /// Called at launch so a log written by an earlier build gets tightened too.
    static func restrictPermissions() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        queue.async {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
                restrictPermissions()
            }
        }
    }
}
