// Live smoke test of the libtorrent bridge: add, download, pause, resume, remove + delete.
// Usage: bridge-smoke <file.torrent> <empty-temp-dir>   (needs network; downloads a few MB)
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: bridge-smoke <file.torrent> <temp-dir>"); exit(2) }
let torrentPath = args[1], tmp = args[2]
let saveDir = tmp + "/downloads", stateDir = tmp + "/state"
try? FileManager.default.createDirectory(atPath: saveDir, withIntermediateDirectories: true)

var failures = 0
func check(_ cond: Bool, _ label: String) {
    print(cond ? "ok    \(label)" : "FAIL  \(label)")
    if !cond { failures += 1 }
}

let s = RTSession(stateDirectory: stateDir, listenPort: 6995)
func status(_ h: String) -> RTTorrentStatus? { s.processAlerts(); return s.statuses().first { $0.infoHash == h } }
func wait(_ seconds: Double, until cond: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if cond() { return true }; Thread.sleep(forTimeInterval: 0.5) }
    return cond()
}

let hash = try s.addTorrentFile(torrentPath, savePath: saveDir)
check(hash.count == 40, "added torrent, info-hash \(hash)")
check((try? s.addTorrentFile(torrentPath, savePath: saveDir)) == nil, "adding the same torrent again is rejected")

check(wait(60) { (status(hash)?.totalWantedDone ?? 0) > 2_000_000 }, "downloads at least 2 MB within 60 s")
if let st = status(hash) { print("      state=\(st.state) progress=\(String(format: "%.1f", st.progress * 100))% peers=\(st.numPeers) tracker=\(st.trackerStatus)") }
check(!s.files(for: hash).isEmpty, "file list available")

s.pause(hash)
check(wait(10) { status(hash)?.state == "Paused" }, "pause → state Paused")
check(status(hash)?.downloadRate == 0, "paused torrent reports 0 B/s")
Thread.sleep(forTimeInterval: 3)  // let in-flight requests from the graceful pause finish
let doneAtPause = status(hash)?.totalWantedDone ?? 0
Thread.sleep(forTimeInterval: 4)
check((status(hash)?.totalWantedDone ?? -1) == doneAtPause, "no bytes downloaded while paused")

s.resume(hash)
check(wait(30) { (status(hash)?.totalWantedDone ?? 0) > doneAtPause }, "resume → downloading continues")

let filePath = saveDir + "/" + (status(hash)?.filePaths.first ?? "")
check(FileManager.default.fileExists(atPath: filePath), "data file exists on disk")
s.remove(hash, deleteFiles: true)
check(wait(15) { !FileManager.default.fileExists(atPath: filePath) }, "remove + delete data → file deleted")
check(s.statuses().isEmpty, "torrent gone from list")
check(!FileManager.default.fileExists(atPath: stateDir + "/\(hash).resume"), "resume file deleted")

s.shutdown()
check(FileManager.default.fileExists(atPath: stateDir + "/session.state"), "session state saved on shutdown")
print(failures == 0 ? "All bridge tests passed" : "\(failures) bridge test(s) failed")
exit(failures == 0 ? 0 : 1)
