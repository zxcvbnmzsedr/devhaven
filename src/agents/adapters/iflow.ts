import { wrapAgentBaseCommand } from "../shellWrapper.ts";
import type { PaneAgentAdapter } from "./types.ts";

export const iflowPaneAgentAdapter: PaneAgentAdapter = {
  id: "iflow",
  label: "iFlow",
  supportsModelSelection: false,
  buildBaseCommand() {
    return "iflow";
  },
  buildLaunchCommand(input) {
    return wrapAgentBaseCommand(
      iflowPaneAgentAdapter.buildBaseCommand(input),
      input?.shellFamily ?? "posix",
    );
  },
};
