export type ResolveCodexMonitorEnabledOptions = {
  manualEnabled: boolean;
  terminalWorkspaceVisible: boolean;
};

/** Codex 监控默认按需启用：用户手动开启，或进入终端工作区时自动开启。 */
export function resolveCodexMonitorEnabled({
  manualEnabled,
  terminalWorkspaceVisible,
}: ResolveCodexMonitorEnabledOptions): boolean {
  return manualEnabled || terminalWorkspaceVisible;
}

/** 侧栏会话区块在未启用监控时显示轻量占位，避免应用启动即拉起监控线程。 */
export function resolveCodexMonitorEmptyText(enabled: boolean): string {
  return enabled ? "未发现 Codex 会话" : "监控未启用";
}
