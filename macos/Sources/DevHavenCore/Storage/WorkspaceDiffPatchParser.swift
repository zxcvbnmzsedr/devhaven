import Foundation

public enum WorkspaceDiffPatchParser {
    public static func parse(_ diff: String) -> WorkspaceDiffParsedDocument {
        let normalized = diff.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return WorkspaceDiffParsedDocument(
                kind: .empty,
                oldPath: nil,
                newPath: nil,
                headerLines: [],
                hunks: [],
                message: "暂无 Diff"
            )
        }

        if normalized.contains("Binary files ") || normalized.contains("GIT binary patch") {
            return WorkspaceDiffParsedDocument(
                kind: .binary,
                oldPath: extractPath(prefix: "--- ", from: normalized),
                newPath: extractPath(prefix: "+++ ", from: normalized),
                headerLines: normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                hunks: [],
                message: "二进制文件 Diff 暂不支持预览"
            )
        }

        let rawLines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let oldPath = extractPath(prefix: "--- ", from: normalized)
        let newPath = extractPath(prefix: "+++ ", from: normalized)

        var headerLines = [String]()
        var hunks = [WorkspaceDiffHunk]()
        var lineIndex = 0

        while lineIndex < rawLines.count {
            let line = rawLines[lineIndex]
            guard line.hasPrefix("@@ ") else {
                headerLines.append(line)
                lineIndex += 1
                continue
            }

            guard let parsedHeader = parseHunkHeader(line) else {
                return WorkspaceDiffParsedDocument(
                    kind: .unsupported,
                    oldPath: oldPath,
                    newPath: newPath,
                    headerLines: headerLines,
                    hunks: [],
                    message: "无法解析 Diff"
                )
            }

            lineIndex += 1
            var oldLineNumber = parsedHeader.oldStart
            var newLineNumber = parsedHeader.newStart
            var hunkLines = [WorkspaceDiffLine]()

            while lineIndex < rawLines.count, !rawLines[lineIndex].hasPrefix("@@ ") {
                let hunkLine = rawLines[lineIndex]
                if let first = hunkLine.first {
                    switch first {
                    case " ":
                        hunkLines.append(
                            WorkspaceDiffLine(
                                kind: .context,
                                oldLineNumber: oldLineNumber,
                                newLineNumber: newLineNumber,
                                text: String(hunkLine.dropFirst())
                            )
                        )
                        oldLineNumber += 1
                        newLineNumber += 1
                    case "-":
                        hunkLines.append(
                            WorkspaceDiffLine(
                                kind: .removed,
                                oldLineNumber: oldLineNumber,
                                newLineNumber: nil,
                                text: String(hunkLine.dropFirst())
                            )
                        )
                        oldLineNumber += 1
                    case "+":
                        hunkLines.append(
                            WorkspaceDiffLine(
                                kind: .added,
                                oldLineNumber: nil,
                                newLineNumber: newLineNumber,
                                text: String(hunkLine.dropFirst())
                            )
                        )
                        newLineNumber += 1
                    case "\\":
                        hunkLines.append(
                            WorkspaceDiffLine(
                                kind: .meta,
                                oldLineNumber: nil,
                                newLineNumber: nil,
                                text: hunkLine
                            )
                        )
                    default:
                        return WorkspaceDiffParsedDocument(
                            kind: .unsupported,
                            oldPath: oldPath,
                            newPath: newPath,
                            headerLines: headerLines,
                            hunks: [],
                            message: "无法解析 Diff"
                        )
                    }
                } else {
                    hunkLines.append(
                        WorkspaceDiffLine(
                            kind: .context,
                            oldLineNumber: oldLineNumber,
                            newLineNumber: newLineNumber,
                            text: ""
                        )
                    )
                    oldLineNumber += 1
                    newLineNumber += 1
                }
                lineIndex += 1
            }

            hunks.append(
                WorkspaceDiffHunk(
                    header: line,
                    lines: hunkLines,
                    sideBySideRows: buildSideBySideRows(from: hunkLines)
                )
            )
        }

        guard !hunks.isEmpty else {
            return WorkspaceDiffParsedDocument(
                kind: .unsupported,
                oldPath: oldPath,
                newPath: newPath,
                headerLines: headerLines,
                hunks: [],
                message: "无法解析 Diff"
            )
        }

        return WorkspaceDiffParsedDocument(
            kind: .text,
            oldPath: oldPath,
            newPath: newPath,
            headerLines: headerLines,
            hunks: hunks
        )
    }

    private static func extractPath(prefix: String, from diff: String) -> String? {
        guard let line = diff.split(separator: "\n", omittingEmptySubsequences: false).map(String.init).first(where: { $0.hasPrefix(prefix) }) else {
            return nil
        }
        let value = String(line.dropFirst(prefix.count))
        switch value {
        case "/dev/null":
            return nil
        case let path where path.hasPrefix("a/"), let path where path.hasPrefix("b/"):
            return String(path.dropFirst(2))
        default:
            return value
        }
    }

    private static func parseHunkHeader(_ line: String) -> (oldStart: Int, newStart: Int)? {
        let pattern = #"^@@ -([0-9]+)(?:,[0-9]+)? \+([0-9]+)(?:,[0-9]+)? @@"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let oldRange = Range(match.range(at: 1), in: line),
              let newRange = Range(match.range(at: 2), in: line),
              let oldStart = Int(line[oldRange]),
              let newStart = Int(line[newRange])
        else {
            return nil
        }
        return (oldStart, newStart)
    }

    private static func buildSideBySideRows(from lines: [WorkspaceDiffLine]) -> [WorkspaceDiffSideBySideRow] {
        var rows = [WorkspaceDiffSideBySideRow]()
        var index = 0

        while index < lines.count {
            let line = lines[index]

            switch line.kind {
            case .context:
                rows.append(WorkspaceDiffSideBySideRow(leftLine: line, rightLine: line))
                index += 1
            case .meta:
                rows.append(WorkspaceDiffSideBySideRow(leftLine: line, rightLine: line))
                index += 1
            case .added:
                rows.append(WorkspaceDiffSideBySideRow(leftLine: nil, rightLine: line))
                index += 1
            case .removed:
                let removedStart = index
                while index < lines.count, lines[index].kind == .removed {
                    index += 1
                }
                let addedStart = index
                while index < lines.count, lines[index].kind == .added {
                    index += 1
                }

                let removedBlock = Array(lines[removedStart..<addedStart])
                let addedBlock = Array(lines[addedStart..<index])
                let rowCount = max(removedBlock.count, addedBlock.count)

                for rowIndex in 0..<rowCount {
                    let leftLine = removedBlock.indices.contains(rowIndex) ? removedBlock[rowIndex] : nil
                    let rightLine = addedBlock.indices.contains(rowIndex) ? addedBlock[rowIndex] : nil
                    rows.append(WorkspaceDiffSideBySideRow(leftLine: leftLine, rightLine: rightLine))
                }
            }
        }

        return rows
    }
}
