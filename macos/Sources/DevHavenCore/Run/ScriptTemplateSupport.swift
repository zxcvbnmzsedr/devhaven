import Foundation

public struct ResolvedScriptCommand: Equatable, Sendable {
    public var command: String
    public var missingRequiredKeys: [String]

    public init(command: String, missingRequiredKeys: [String]) {
        self.command = command
        self.missingRequiredKeys = missingRequiredKeys
    }
}

public enum ScriptTemplateSupport {
    private static let templateParamPattern = try! NSRegularExpression(pattern: #"\$\{([A-Za-z_][A-Za-z0-9_]*)\}"#)
    private static let reservedTemplateKeys: Set<String> = ["scriptPath"]

    public static func mergeParamSchema(command: String, schema: [ScriptParamField]) -> [ScriptParamField] {
        let normalizedSchema = normalizeSchema(schema)
        let schemaByKey = Dictionary(uniqueKeysWithValues: normalizedSchema.map { ($0.key, $0) })
        let inferredKeys = collectTemplateParamKeys(in: command)
        guard !inferredKeys.isEmpty else {
            return []
        }

        return inferredKeys.map { key in
            schemaByKey[key]
                ?? ScriptParamField(
                    key: key,
                    label: key,
                    type: .text,
                    required: false,
                    defaultValue: nil,
                    description: nil
                )
        }
    }

    public static func buildTemplateParams(
        schema: [ScriptParamField],
        explicitValues: [String: String]
    ) -> [String: String] {
        var result = [String: String]()
        for field in schema {
            if let current = explicitValues[field.key] {
                result[field.key] = current
            } else if let defaultValue = field.defaultValue {
                result[field.key] = defaultValue
            } else {
                result[field.key] = ""
            }
        }
        return result
    }

    public static func applySharedScriptTemplate(
        commandTemplate: String,
        absolutePath: String
    ) -> String {
        let resolvedTemplate = normalizeShellTemplateText(commandTemplate).trimmingCharacters(in: .whitespacesAndNewlines)
        let template = resolvedTemplate.isEmpty ? #"bash "${scriptPath}""# : resolvedTemplate
        let escapedPath = absolutePath
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return replaceTemplateVariable(in: template, key: "scriptPath", replacement: escapedPath)
    }

    public static func resolveCommand(
        template: String,
        paramSchema: [ScriptParamField],
        explicitValues: [String: String],
        predefinedVariables: [(String, String)] = []
    ) -> ResolvedScriptCommand {
        let trimmedTemplate = normalizeShellTemplateText(template).trimmingCharacters(in: .whitespacesAndNewlines)
        var assignments = [(String, String)]()
        var resolvedKeys = Set<String>()
        var missingRequiredKeys = [String]()

        for (key, value) in predefinedVariables {
            assignments.append((key, value))
            resolvedKeys.insert(key)
        }

        for field in normalizeSchema(paramSchema) {
            let explicit = explicitValues[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = field.defaultValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (explicit?.isEmpty == false ? explicit : nil)
                ?? (fallback?.isEmpty == false ? fallback : nil)
                ?? ""
            if field.required && value.isEmpty {
                let displayKey = field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? field.key : field.label
                missingRequiredKeys.append(displayKey)
            }
            assignments.append((field.key, value))
            resolvedKeys.insert(field.key)
        }

        for key in explicitValues.keys.sorted() where !resolvedKeys.contains(key) {
            let value = explicitValues[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            assignments.append((key, value))
        }

        let assignmentPrefix = assignments
            .map { "\($0.0)=\(shellQuoted($0.1))" }
            .joined(separator: "\n")
        let command: String
        if assignmentPrefix.isEmpty {
            command = trimmedTemplate
        } else if trimmedTemplate.isEmpty {
            command = assignmentPrefix
        } else {
            command = "\(assignmentPrefix)\n\(trimmedTemplate)"
        }

        return ResolvedScriptCommand(command: command, missingRequiredKeys: missingRequiredKeys)
    }

    public static func normalizeShellTemplateText(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{201A}", with: "'")
            .replacingOccurrences(of: "\u{201B}", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{201E}", with: "\"")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func normalizeSchema(_ schema: [ScriptParamField]) -> [ScriptParamField] {
        schema.compactMap { field in
            let key = field.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else {
                return nil
            }
            let label = field.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? key : field.label
            return ScriptParamField(
                key: key,
                label: label,
                type: field.type,
                required: field.required,
                defaultValue: field.defaultValue,
                description: field.description
            )
        }
    }

    private static func collectTemplateParamKeys(in command: String) -> [String] {
        let source = normalizeShellTemplateText(command)
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var keys = [String]()
        var seen = Set<String>()
        for match in templateParamPattern.matches(in: source, range: fullRange) {
            guard match.numberOfRanges > 1,
                  let keyRange = Range(match.range(at: 1), in: source)
            else {
                continue
            }
            let key = String(source[keyRange])
            guard !reservedTemplateKeys.contains(key),
                  !key.isEmpty,
                  !seen.contains(key),
                  key.range(of: #"^[A-Z0-9_]+$"#, options: .regularExpression) == nil
            else {
                continue
            }
            seen.insert(key)
            keys.append(key)
        }
        return keys
    }

    private static func replaceTemplateVariable(
        in source: String,
        key: String,
        replacement: String
    ) -> String {
        let escapedKey = NSRegularExpression.escapedPattern(for: key)
        return source.replacingOccurrences(
            of: "\\$\\{\(escapedKey)\\}",
            with: replacement,
            options: .regularExpression
        )
    }

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
