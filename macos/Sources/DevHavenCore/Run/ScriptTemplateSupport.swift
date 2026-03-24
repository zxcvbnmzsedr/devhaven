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

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
