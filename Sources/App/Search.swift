// Deluge-style search (see ../item-search/EVIDENCE.md), generalised to any record.
//   * comma-separated terms, each must match (AND)
//   * a term matches if it is a case-insensitive substring of ANY searchable text
//   * type-ahead: first record whose name starts with the typed text
import Foundation

protocol Searchable {
    var searchName: String { get }
    /// Every string a keyword may match (name, state, trackers, hash, files...).
    var searchableTexts: [String] { get }
}

/// Join with commas, split, lower-case, trim, drop empty terms.
func parseKeywords(_ values: [String]) -> [String] {
    values.joined(separator: ",").lowercased()
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
}

func recordMatches<T: Searchable>(_ record: T, term: String) -> Bool {
    record.searchableTexts.contains { $0.lowercased().contains(term) }
}

func keywordSearch<T: Searchable>(_ records: [T], query: String) -> [T] {
    parseKeywords([query]).reduce(records) { result, term in
        result.filter { recordMatches($0, term: term) }
    }
}

/// First index at/after `start` (wrapping) whose name starts with `typed`, ignoring case.
func typeaheadIndex<T: Searchable>(_ records: [T], typed: String, start: Int = 0) -> Int? {
    guard !typed.isEmpty, !records.isEmpty else { return nil }
    let key = typed.lowercased()
    for offset in 0..<records.count {
        let i = (start + offset) % records.count
        if records[i].searchName.lowercased().hasPrefix(key) { return i }
    }
    return nil
}
