import type { TerminalReplayMode } from "../../services/terminal";

export type ResolveReplayModeOnUnmountOptions = {
  preserveSessionOnUnmount: boolean;
  downgradeReplayOnPreserveUnmount?: boolean;
};

/** 终端卸载时的 replay 回收策略。项目切换默认不降级，只在显式启用时才切到 parked。 */
export function resolveReplayModeOnUnmount({
  preserveSessionOnUnmount,
  downgradeReplayOnPreserveUnmount = false,
}: ResolveReplayModeOnUnmountOptions): TerminalReplayMode | null {
  if (!preserveSessionOnUnmount) {
    return null;
  }
  return downgradeReplayOnPreserveUnmount ? "parked" : null;
}
