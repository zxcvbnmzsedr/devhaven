import { wrapAgentBaseCommand, quoteShellArg } from "../shellWrapper.ts";
import type { PaneAgentAdapter } from "./types.ts";

function normalizeOptionalText(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

export const codexPaneAgentAdapter: PaneAgentAdapter = {
  id: "codex",
  label: "Codex",
  supportsModelSelection: true,
  buildBaseCommand(input) {
    const parts = ["codex"];
    const model = normalizeOptionalText(input?.model);
    const prompt = normalizeOptionalText(input?.prompt);

    parts.push(input?.fullAccess === false ? "--full-auto" : "--dangerously-bypass-approvals-and-sandbox");

    if (model) {
      parts.push("--model", quoteShellArg(model));
    }

    if (prompt) {
      if (prompt.startsWith("-")) {
        parts.push("--");
      }
      parts.push(quoteShellArg(prompt));
    }

    return parts.join(" ");
  },
  buildLaunchCommand(input) {
    return wrapAgentBaseCommand(
      codexPaneAgentAdapter.buildBaseCommand(input),
      input?.shellFamily ?? "posix",
    );
  },
};
