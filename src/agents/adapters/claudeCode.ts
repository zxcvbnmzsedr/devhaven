import { wrapAgentBaseCommand, quoteShellArg } from "../shellWrapper.ts";
import type { PaneAgentAdapter } from "./types.ts";

function normalizeOptionalText(value: string | null | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const normalized = value.trim();
  return normalized.length > 0 ? normalized : null;
}

export const claudeCodePaneAgentAdapter: PaneAgentAdapter = {
  id: "claude-code",
  label: "Claude Code",
  supportsModelSelection: true,
  buildBaseCommand(input) {
    const parts = ["claude"];
    const model = normalizeOptionalText(input?.model);
    const prompt = normalizeOptionalText(input?.prompt);

    if (input?.fullAccess !== false) {
      parts.push("--dangerously-skip-permissions");
    }

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
      claudeCodePaneAgentAdapter.buildBaseCommand(input),
      input?.shellFamily ?? "posix",
    );
  },
};
