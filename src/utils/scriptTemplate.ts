import type { ProjectScript, ScriptParamField, ScriptParamFieldType } from "../models/types";

const TEMPLATE_PARAM_REGEX = /\$\{([A-Za-z_][A-Za-z0-9_]*)\}/g;
const RESERVED_TEMPLATE_KEYS = new Set(["scriptPath"]);
const ENV_STYLE_KEY_REGEX = /^[A-Z0-9_]+$/;

export function mergeScriptParamSchema(
  command: string,
  schema: ScriptParamField[] | null | undefined,
  _templateParams?: Record<string, string> | null,
): ScriptParamField[] {
  const normalizedSchema = normalizeScriptParamSchema(schema);
  const schemaByKey = new Map(normalizedSchema.map((field) => [field.key, field] as const));
  const inferredKeys = collectTemplateParamKeys(command);
  if (inferredKeys.length === 0) {
    return [];
  }

  const result: ScriptParamField[] = [];
  for (const key of inferredKeys) {
    const existing = schemaByKey.get(key);
    result.push(existing ?? { key, label: key, type: "text", required: false });
  }

  return result;
}

export function buildTemplateParams(
  schema: ScriptParamField[],
  templateParams?: Record<string, string> | null,
): Record<string, string> {
  const result: Record<string, string> = {};
  for (const field of schema) {
    const current = templateParams?.[field.key];
    if (typeof current === "string") {
      result[field.key] = current;
      continue;
    }
    if (typeof field.defaultValue === "string") {
      result[field.key] = field.defaultValue;
      continue;
    }
    result[field.key] = "";
  }
  return result;
}

export function renderScriptTemplateCommand(script: ProjectScript):
  | { ok: true; command: string; templateParams: Record<string, string>; schema: ScriptParamField[] }
  | { ok: false; error: string } {
  const commandSource = normalizeShellTemplateText(script.start ?? "");
  const schema = mergeScriptParamSchema(commandSource, script.paramSchema, script.templateParams);
  const templateParams = buildTemplateParams(schema, script.templateParams);

  for (const field of schema) {
    const value = templateParams[field.key] ?? "";
    if (field.required && !value.trim()) {
      return {
        ok: false,
        error: `${field.label || field.key} 不能为空`,
      };
    }
  }

  let command = commandSource;
  for (const field of schema) {
    command = replaceTemplateVariable(command, field.key, shellQuote(templateParams[field.key] ?? ""));
  }

  return {
    ok: true,
    command,
    templateParams,
    schema,
  };
}

export function applySharedScriptCommandTemplate(
  commandTemplate: string | null | undefined,
  absolutePath: string,
): string {
  const resolvedTemplate = commandTemplate?.trim()
    ? normalizeShellTemplateText(commandTemplate.trim())
    : 'bash "${scriptPath}"';
  const escapedPath = absolutePath.replace(/\\/g, "/").replace(/"/g, '\\"');
  return replaceTemplateVariable(resolvedTemplate, "scriptPath", escapedPath);
}

function normalizeShellTemplateText(source: string): string {
  return source
    .replace(/[\u2018\u2019\u201A\u201B]/g, "'")
    .replace(/[\u201C\u201D\u201E]/g, '"')
    .replace(/\u00A0/g, " ");
}

function collectTemplateParamKeys(command: string): string[] {
  const keys: string[] = [];
  const seen = new Set<string>();
  const source = command ?? "";
  for (const match of source.matchAll(TEMPLATE_PARAM_REGEX)) {
    const key = match[1];
    if (!key || seen.has(key)) {
      continue;
    }
    if (RESERVED_TEMPLATE_KEYS.has(key) || ENV_STYLE_KEY_REGEX.test(key)) {
      continue;
    }
    seen.add(key);
    keys.push(key);
  }
  return keys;
}

function normalizeScriptParamSchema(schema: ScriptParamField[] | null | undefined): ScriptParamField[] {
  if (!schema || schema.length === 0) {
    return [];
  }

  const normalized: ScriptParamField[] = [];
  for (const field of schema) {
    const key = field.key?.trim();
    if (!key) {
      continue;
    }
    const label = field.label?.trim() || key;
    normalized.push({
      key,
      label,
      type: normalizeFieldType(field.type),
      required: Boolean(field.required),
      defaultValue: field.defaultValue,
      description: field.description,
    });
  }
  return normalized;
}

function normalizeFieldType(type: ScriptParamFieldType | undefined): ScriptParamFieldType {
  if (type === "number" || type === "secret") {
    return type;
  }
  return "text";
}

function replaceTemplateVariable(source: string, key: string, replacement: string): string {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp(`\\$\\{${escaped}\\}`, "g");
  return source.replace(pattern, replacement);
}

function shellQuote(value: string): string {
  return `'${value.replace(/'/g, `'"'"'`)}'`;
}
