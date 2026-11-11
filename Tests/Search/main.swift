// Self-test for Search.swift. Built and run by build.sh.
import Foundation

struct Row: Searchable {
    let id, name, state: String
    let trackers, files: [String]
    var searchName: String { name }
    var searchableTexts: [String] { [name, state] + trackers + [id] + files }
}

let rows = [
    Row(id: "a1f3c9", name: "Ubuntu 24.04 Desktop", state: "Seeding",
        trackers: ["https://torrent.ubuntu.com/announce"], files: ["ubuntu-24.04-desktop-amd64.iso"]),
    Row(id: "b27d10", name: "Debian 13 netinst", state: "Downloading",
        trackers: ["http://bttracker.debian.org:6969/announce"], files: ["debian-13.0.0-amd64-netinst.iso"]),
    Row(id: "c90e44", name: "Big Buck Bunny", state: "Paused",
        trackers: ["udp://tracker.example.org:1337", "https://BACKUP.Example.org/announce"],
        files: ["BBB/bbb_1080p.mp4", "BBB/subs/en.srt"]),
]

var failures = 0
func check(_ cond: Bool, _ label: String) {
    print(cond ? "ok    \(label)" : "FAIL  \(label)")
    if !cond { failures += 1 }
}
func ids(_ r: [Row]) -> [String] { r.map(\.id) }

check(parseKeywords(["Ubuntu, ,SEED", "x"]) == ["ubuntu", "seed", "x"], "parse trims, lower-cases, drops empties")
check(keywordSearch(rows, query: "").count == 3, "empty query returns all")
check(ids(keywordSearch(rows, query: "UBUNTU")) == ["a1f3c9"], "case-insensitive name")
check(ids(keywordSearch(rows, query: "amd64")) == ["a1f3c9", "b27d10"], "file path match")
check(ids(keywordSearch(rows, query: "amd64, downloading")) == ["b27d10"], "terms are ANDed")
check(ids(keywordSearch(rows, query: "c90e")) == ["c90e44"], "hash match")
check(ids(keywordSearch(rows, query: "backup.example")) == ["c90e44"], "second tracker, any case")
check(ids(keywordSearch(rows, query: "nothing-here")) == [], "no match")
check(typeaheadIndex(rows, typed: "deb") == 1, "type-ahead prefix")
check(typeaheadIndex(rows, typed: "buck") == nil, "type-ahead is prefix, not substring")
check(typeaheadIndex(rows, typed: "u", start: 2) == 0, "type-ahead wraps")

print(failures == 0 ? "All search tests passed" : "\(failures) test(s) failed")
exit(failures == 0 ? 0 : 1)
