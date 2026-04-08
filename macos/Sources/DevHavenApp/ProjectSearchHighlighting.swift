import Foundation
import SwiftUI

func projectSearchHighlightRanges(
    in value: String,
    query: String
) -> [Range<String.Index>] {
    let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedQuery.isEmpty else {
        return []
    }

    var ranges: [Range<String.Index>] = []
    var searchStart = value.startIndex
    while searchStart < value.endIndex,
          let range = value.range(
            of: normalizedQuery,
            options: [.caseInsensitive],
            range: searchStart..<value.endIndex
          ) {
        ranges.append(range)
        searchStart = range.upperBound
    }

    return ranges
}

func projectSearchHighlightedText(
    _ value: String,
    query: String
) -> AttributedString {
    var attributed = AttributedString(value)
    for range in projectSearchHighlightRanges(in: value, query: query) {
        guard let lowerBound = AttributedString.Index(range.lowerBound, within: attributed),
              let upperBound = AttributedString.Index(range.upperBound, within: attributed)
        else {
            continue
        }
        attributed[lowerBound..<upperBound].foregroundColor = .primary
        attributed[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.35)
    }
    return attributed
}
