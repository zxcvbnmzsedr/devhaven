import { listenEvent, type ListenEventOptions } from "../platform/eventClient";
import type {
  TerminalWindowLayoutChangedPayload,
  TerminalWorkspaceRestoredPayload,
} from "../models/terminal";
import type { QuickCommandStateChangedPayload } from "../models/quickCommands";

export const TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT = "terminal-window-layout-changed";
export const TERMINAL_WORKSPACE_RESTORED_EVENT = "terminal-workspace-restored";
export const TERMINAL_PANE_OUTPUT_EVENT_PREFIX = "terminal-pane-output:";
export const TERMINAL_PANE_EXIT_EVENT_PREFIX = "terminal-pane-exit:";
export const TERMINAL_PANE_FOCUS_EVENT_PREFIX = "terminal-pane-focus:";
export const QUICK_COMMAND_STATE_CHANGED_EVENT = "quick-command-state-changed";

function normalizeScopeId(value: string) {
  return value.trim();
}

export function terminalPaneOutputEventName(sessionId: string) {
  return `${TERMINAL_PANE_OUTPUT_EVENT_PREFIX}${normalizeScopeId(sessionId)}`;
}

export function terminalPaneExitEventName(sessionId: string) {
  return `${TERMINAL_PANE_EXIT_EVENT_PREFIX}${normalizeScopeId(sessionId)}`;
}

export function terminalPaneFocusEventName(paneId: string) {
  return `${TERMINAL_PANE_FOCUS_EVENT_PREFIX}${normalizeScopeId(paneId)}`;
}

export async function listenTerminalWindowLayoutChanged(
  handler: (event: { payload: TerminalWindowLayoutChangedPayload }) => void,
  options?: ListenEventOptions,
) {
  return listenEvent<TerminalWindowLayoutChangedPayload>(
    TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT,
    handler,
    options,
  );
}

export async function listenTerminalWorkspaceRestored(
  handler: (event: { payload: TerminalWorkspaceRestoredPayload }) => void,
  options?: ListenEventOptions,
) {
  return listenEvent<TerminalWorkspaceRestoredPayload>(TERMINAL_WORKSPACE_RESTORED_EVENT, handler, options);
}

export async function listenQuickCommandStateChanged(
  handler: (event: { payload: QuickCommandStateChangedPayload }) => void,
  options?: ListenEventOptions,
) {
  return listenEvent<QuickCommandStateChangedPayload>(QUICK_COMMAND_STATE_CHANGED_EVENT, handler, options);
}
