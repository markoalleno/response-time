import Foundation

/// Debug logging that writes to both console and file
func debugLog(_ message: String) {
    let logPath = "/tmp/rt-sync-debug.log"
    let timestamp = Date().formatted(date: .omitted, time: .standard)
    let logLine = "[\(timestamp)] \(message)\n"
    
    // Write to file
    if let data = logLine.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: logPath))
        }
    }
    
    // Also print to console (for Xcode debugging)
    print(message)
}
