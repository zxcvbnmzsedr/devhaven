import { invokeCommand } from "../platform/commandClient";

import type { GitIdentity } from "../models/types";

export type GitDailyResult = {
  path: string;
  gitDaily?: string | null;
  error?: string | null;
};

/** 批量读取项目的每日提交统计（git log 汇总）。 */
export async function collectGitDaily(
  paths: string[],
  identities: GitIdentity[] = [],
): Promise<GitDailyResult[]> {
  if (paths.length === 0) {
    return [];
  }
  return invokeCommand<GitDailyResult[]>("collect_git_daily", { paths, identities });
}
