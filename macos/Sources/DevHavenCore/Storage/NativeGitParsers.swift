import Foundation

enum NativeGitParsers {
    static let fieldSeparator = "\u{1f}"

    static func parseGraphLog(_ output: String) -> [WorkspaceGitCommitSummary] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseGraphLogLine(String($0)) }
    }

    static func parseCommitDetail(_ output: String, changedFiles: [WorkspaceGitCommitFileChange]) throws -> WorkspaceGitCommitDetail {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw WorkspaceGitCommandError.parseFailure("无法解析提交详情：输出为空")
        }

        let fields = splitFields(trimmed, expectedAtLeast: 9)
        guard fields.count >= 9 else {
            throw WorkspaceGitCommandError.parseFailure("无法解析提交详情：字段数量不足")
        }

        let hash = fields[0]
        return WorkspaceGitCommitDetail(
            hash: hash,
            shortHash: fields[1].isEmpty ? String(hash.prefix(7)) : fields[1],
            parentHashes: splitParents(fields[2]),
            authorName: fields[3],
            authorEmail: fields[4],
            authorTimestamp: TimeInterval(fields[5]) ?? 0,
            subject: fields[7],
            body: fields[8].nilIfEmpty,
            decorations: normalizeDecorations(fields[6]),
            changedFiles: changedFiles
        )
    }

    static func parseNameStatus(_ output: String) -> [WorkspaceGitCommitFileChange] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { parseNameStatusLine(String($0)) }
    }

    static func parseRefs(_ output: String) -> WorkspaceGitRefsSnapshot {
        var localBranches = [WorkspaceGitBranchSnapshot]()
        var remoteBranches = [WorkspaceGitBranchSnapshot]()
        var tags = [WorkspaceGitTagSnapshot]()

        for line in output.split(whereSeparator: \.isNewline) {
            let rawLine = String(line)
            let tabFields = rawLine.components(separatedBy: "\t")
            let fields = tabFields.count >= 5 ? tabFields : splitFields(rawLine, expectedAtLeast: 5)
            guard fields.count >= 5 else {
                continue
            }
            let hash = fields[0]
            let fullRef = fields[1]
            let shortRef = fields[2]
            let upstream = fields[3].nilIfEmpty
            let isCurrent = fields[4] == "*"

            if fullRef.hasPrefix("refs/heads/") {
                localBranches.append(
                    WorkspaceGitBranchSnapshot(
                        name: shortRef,
                        fullName: fullRef,
                        hash: hash,
                        kind: .local,
                        isCurrent: isCurrent,
                        upstream: upstream
                    )
                )
            } else if fullRef.hasPrefix("refs/remotes/") {
                guard !fullRef.hasSuffix("/HEAD") else {
                    continue
                }
                remoteBranches.append(
                    WorkspaceGitBranchSnapshot(
                        name: shortRef,
                        fullName: fullRef,
                        hash: hash,
                        kind: .remote,
                        isCurrent: false,
                        upstream: nil
                    )
                )
            } else if fullRef.hasPrefix("refs/tags/") {
                tags.append(WorkspaceGitTagSnapshot(name: shortRef, hash: hash))
            }
        }

        return WorkspaceGitRefsSnapshot(
            localBranches: localBranches.sorted { branchSort(lhs: $0, rhs: $1) },
            remoteBranches: remoteBranches.sorted { branchSort(lhs: $0, rhs: $1) },
            tags: tags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        )
    }

    static func parseStatusPorcelainV2(_ output: String) -> WorkspaceGitWorkingTreeSnapshot {
        var headOID: String?
        var branchName: String?
        var isDetachedHead = false
        var isEmptyRepository = false
        var upstreamBranch: String?
        var aheadCount = 0
        var behindCount = 0
        var staged = [WorkspaceGitFileStatus]()
        var unstaged = [WorkspaceGitFileStatus]()
        var untracked = [WorkspaceGitFileStatus]()
        var conflicted = [WorkspaceGitFileStatus]()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.hasPrefix("# ") {
                parseBranchHeader(
                    line,
                    headOID: &headOID,
                    branchName: &branchName,
                    isDetachedHead: &isDetachedHead,
                    isEmptyRepository: &isEmptyRepository,
                    upstreamBranch: &upstreamBranch,
                    aheadCount: &aheadCount,
                    behindCount: &behindCount
                )
                continue
            }

            if line.hasPrefix("1 "), let entry = parseOrdinaryEntry(line) {
                appendStatusEntry(entry, staged: &staged, unstaged: &unstaged)
                continue
            }

            if line.hasPrefix("2 "), let entry = parseRenamedEntry(line) {
                appendStatusEntry(entry, staged: &staged, unstaged: &unstaged)
                continue
            }

            if line.hasPrefix("u "), let entry = parseUnmergedEntry(line) {
                conflicted.append(entry)
                continue
            }

            if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                guard !path.isEmpty else { continue }
                untracked.append(
                    WorkspaceGitFileStatus(path: path, kind: .untracked)
                )
                continue
            }
        }

        return WorkspaceGitWorkingTreeSnapshot(
            headOID: headOID,
            branchName: branchName,
            isDetachedHead: isDetachedHead,
            isEmptyRepository: isEmptyRepository,
            upstreamBranch: upstreamBranch,
            aheadCount: aheadCount,
            behindCount: behindCount,
            staged: staged,
            unstaged: unstaged,
            untracked: untracked,
            conflicted: conflicted
        )
    }

    static func parseRemotes(_ output: String) -> [WorkspaceGitRemoteSnapshot] {
        var table = [String: WorkspaceGitRemoteSnapshot]()

        for line in output.split(whereSeparator: \.isNewline) {
            let text = String(line)
            let parts = text.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = parts[1]

            guard !name.isEmpty,
                  let firstSpace = rest.firstIndex(of: " "),
                  let openParen = rest.firstIndex(of: "("),
                  let closeParen = rest.lastIndex(of: ")"),
                  openParen < closeParen
            else {
                continue
            }

            let url = String(rest[..<firstSpace]).trimmingCharacters(in: .whitespaces)
            let role = String(rest[rest.index(after: openParen)..<closeParen]).trimmingCharacters(in: .whitespaces)

            var snapshot = table[name] ?? WorkspaceGitRemoteSnapshot(name: name, fetchURL: nil, pushURL: nil)
            if role == "fetch" {
                snapshot.fetchURL = url
            } else if role == "push" {
                snapshot.pushURL = url
            }
            table[name] = snapshot
        }

        return table.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func parseAheadBehind(_ output: String) -> WorkspaceGitAheadBehindSnapshot {
        let snapshot = parseStatusPorcelainV2(output)
        return WorkspaceGitAheadBehindSnapshot(upstream: snapshot.upstreamBranch, ahead: snapshot.aheadCount, behind: snapshot.behindCount)
    }

    static func parseGitDirFromDotGitFile(_ output: String, repositoryPath: String) throws -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let markerRange = trimmed.range(of: "gitdir:") else {
            throw WorkspaceGitCommandError.parseFailure(".git 文件格式错误：缺少 gitdir 标记")
        }

        let rawValue = trimmed[markerRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            throw WorkspaceGitCommandError.parseFailure(".git 文件格式错误：gitdir 路径为空")
        }

        let valueURL = URL(fileURLWithPath: rawValue)
        if valueURL.path.hasPrefix("/") {
            return valueURL.standardizedFileURL.path
        }

        let baseURL = URL(fileURLWithPath: repositoryPath, isDirectory: true)
        return baseURL.appending(path: rawValue).standardizedFileURL.path
    }

    static func resolveGitDirOutput(_ output: String, repositoryPath: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return URL(fileURLWithPath: repositoryPath, isDirectory: true).appending(path: ".git").standardizedFileURL.path
        }

        let candidate = URL(fileURLWithPath: trimmed)
        if candidate.path.hasPrefix("/") {
            return candidate.standardizedFileURL.path
        }
        return URL(fileURLWithPath: repositoryPath, isDirectory: true)
            .appending(path: trimmed)
            .standardizedFileURL
            .path
    }

    private static func parseGraphLogLine(_ line: String) -> WorkspaceGitCommitSummary? {
        guard let separatorRange = line.range(of: fieldSeparator) else {
            return nil
        }

        let graphPrefix = String(line[..<separatorRange.lowerBound])
        let payload = String(line[separatorRange.upperBound...])
        let fields = splitFields(payload, expectedAtLeast: 8)
        guard fields.count >= 8 else {
            return nil
        }

        let hash = fields[0]
        let shortHash = fields[1].isEmpty ? String(hash.prefix(7)) : fields[1]
        return WorkspaceGitCommitSummary(
            hash: hash,
            shortHash: shortHash,
            graphPrefix: graphPrefix,
            parentHashes: splitParents(fields[2]),
            authorName: fields[3],
            authorEmail: fields[4],
            authorTimestamp: TimeInterval(fields[5]) ?? 0,
            subject: fields[7],
            decorations: normalizeDecorations(fields[6])
        )
    }

    private static func parseNameStatusLine(_ line: String) -> WorkspaceGitCommitFileChange? {
        guard !line.isEmpty else {
            return nil
        }

        let components = line.components(separatedBy: "\t")
        guard let rawStatus = components.first, !rawStatus.isEmpty else {
            return nil
        }

        let status = parseCommitFileStatus(rawStatus)
        switch status {
        case .renamed, .copied:
            guard components.count >= 3 else {
                return nil
            }
            return WorkspaceGitCommitFileChange(
                path: components[2],
                oldPath: components[1],
                status: status
            )
        default:
            guard components.count >= 2 else {
                return nil
            }
            return WorkspaceGitCommitFileChange(path: components[1], status: status)
        }
    }

    private static func parseCommitFileStatus(_ raw: String) -> WorkspaceGitCommitFileStatus {
        guard let mark = raw.first else {
            return .unknown
        }

        switch mark {
        case "A":
            return .added
        case "M":
            return .modified
        case "D":
            return .deleted
        case "R":
            return .renamed
        case "C":
            return .copied
        case "T":
            return .typeChanged
        case "U":
            return .unmerged
        default:
            return .unknown
        }
    }

    private static func parseBranchHeader(
        _ line: String,
        headOID: inout String?,
        branchName: inout String?,
        isDetachedHead: inout Bool,
        isEmptyRepository: inout Bool,
        upstreamBranch: inout String?,
        aheadCount: inout Int,
        behindCount: inout Int
    ) {
        if line.hasPrefix("# branch.oid ") {
            let value = String(line.dropFirst("# branch.oid ".count)).trimmingCharacters(in: .whitespaces)
            if value == "(initial)" {
                isEmptyRepository = true
                headOID = nil
            } else {
                headOID = value
            }
            return
        }

        if line.hasPrefix("# branch.head ") {
            let value = String(line.dropFirst("# branch.head ".count)).trimmingCharacters(in: .whitespaces)
            if value == "(detached)" {
                isDetachedHead = true
                branchName = nil
            } else {
                branchName = value
            }
            return
        }

        if line.hasPrefix("# branch.upstream ") {
            let value = String(line.dropFirst("# branch.upstream ".count)).trimmingCharacters(in: .whitespaces)
            upstreamBranch = value.nilIfEmpty
            return
        }

        if line.hasPrefix("# branch.ab ") {
            let value = String(line.dropFirst("# branch.ab ".count)).trimmingCharacters(in: .whitespaces)
            for token in value.split(separator: " ") {
                if token.hasPrefix("+") {
                    aheadCount = Int(token.dropFirst()) ?? 0
                } else if token.hasPrefix("-") {
                    behindCount = Int(token.dropFirst()) ?? 0
                }
            }
        }
    }

    private static func parseOrdinaryEntry(_ line: String) -> WorkspaceGitFileStatus? {
        let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
        guard parts.count >= 9 else {
            return nil
        }

        let xy = String(parts[1])
        let path = decodeQuotedPath(String(parts[8]))
        guard !path.isEmpty else {
            return nil
        }

        return WorkspaceGitFileStatus(
            path: path,
            indexStatus: statusCharacter(in: xy, at: 0),
            workTreeStatus: statusCharacter(in: xy, at: 1),
            kind: .tracked
        )
    }

    private static func parseRenamedEntry(_ line: String) -> WorkspaceGitFileStatus? {
        let tabParts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
        let leftPart = String(tabParts[0])
        let sourcePath = tabParts.count > 1 ? decodeQuotedPath(String(tabParts[1])) : nil

        let parts = leftPart.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
        guard parts.count >= 10 else {
            return nil
        }

        let xy = String(parts[1])
        let targetPath = decodeQuotedPath(String(parts[9]))
        guard !targetPath.isEmpty else {
            return nil
        }

        return WorkspaceGitFileStatus(
            path: targetPath,
            originalPath: sourcePath,
            indexStatus: statusCharacter(in: xy, at: 0),
            workTreeStatus: statusCharacter(in: xy, at: 1),
            kind: .renamed
        )
    }

    private static func parseUnmergedEntry(_ line: String) -> WorkspaceGitFileStatus? {
        let parts = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
        guard parts.count >= 11 else {
            return nil
        }

        let xy = String(parts[1])
        let path = decodeQuotedPath(String(parts[10]))
        guard !path.isEmpty else {
            return nil
        }

        return WorkspaceGitFileStatus(
            path: path,
            indexStatus: statusCharacter(in: xy, at: 0),
            workTreeStatus: statusCharacter(in: xy, at: 1),
            kind: .unmerged
        )
    }

    private static func appendStatusEntry(
        _ entry: WorkspaceGitFileStatus,
        staged: inout [WorkspaceGitFileStatus],
        unstaged: inout [WorkspaceGitFileStatus]
    ) {
        if let indexStatus = entry.indexStatus, indexStatus != "." {
            staged.append(entry)
        }
        if let workTreeStatus = entry.workTreeStatus, workTreeStatus != "." {
            unstaged.append(entry)
        }
    }

    private static func statusCharacter(in value: String, at index: Int) -> String? {
        guard index >= 0, index < value.count else {
            return nil
        }
        let stringIndex = value.index(value.startIndex, offsetBy: index)
        return String(value[stringIndex])
    }

    private static func decodeQuotedPath(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("\"") && text.hasSuffix("\""), text.count >= 2 else {
            return text
        }

        let inner = String(text.dropFirst().dropLast())
        let characters = Array(inner)
        var result = ""
        var index = 0

        while index < characters.count {
            let current = characters[index]
            if current != "\\" {
                result.append(current)
                index += 1
                continue
            }

            index += 1
            guard index < characters.count else {
                break
            }

            let escaped = characters[index]
            switch escaped {
            case "\\":
                result.append("\\")
                index += 1
            case "\"":
                result.append("\"")
                index += 1
            case "n":
                result.append("\n")
                index += 1
            case "t":
                result.append("\t")
                index += 1
            case "r":
                result.append("\r")
                index += 1
            case "0"..."7":
                var octal = String(escaped)
                index += 1
                while index < characters.count, octal.count < 3, isOctalDigit(characters[index]) {
                    octal.append(characters[index])
                    index += 1
                }
                if let value = UInt8(octal, radix: 8),
                   let scalar = UnicodeScalar(Int(value))
                {
                    result.append(Character(scalar))
                }
            default:
                result.append(escaped)
                index += 1
            }
        }

        return result
    }

    private static func isOctalDigit(_ value: Character) -> Bool {
        ("0"..."7").contains(value)
    }

    private static func splitParents(_ value: String) -> [String] {
        value
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalizeDecorations(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func splitFields(_ line: String, expectedAtLeast: Int) -> [String] {
        let parts = line.split(separator: Character(fieldSeparator), omittingEmptySubsequences: false)
        if parts.count >= expectedAtLeast {
            return parts.map(String.init)
        }
        return line.components(separatedBy: fieldSeparator)
    }

    private static func branchSort(lhs: WorkspaceGitBranchSnapshot, rhs: WorkspaceGitBranchSnapshot) -> Bool {
        if lhs.isCurrent != rhs.isCurrent {
            return lhs.isCurrent
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
