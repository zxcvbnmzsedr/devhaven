export type GitDailyRefreshReason = "missing" | "identity";

export type GitDailyRefreshRequest = {
  reason: GitDailyRefreshReason;
  signature: string;
  paths: string[];
};

type GitDailyProjectLike = {
  path: string;
  git_commits: number;
  git_daily?: string | null;
};

/** 为自动 Git Daily 补齐构建“路径 + 身份”维度的尝试键。 */
export function buildGitDailyAutoRefreshAttemptKey(path: string, identitySignature: string): string {
  return `${identitySignature}::${path}`;
}

/** 计算当前仍允许自动触发 Git Daily 统计的项目路径。 */
export function pickGitDailyAutoRefreshPaths(
  projects: GitDailyProjectLike[],
  identitySignature: string,
  attemptedKeys: ReadonlySet<string>,
): string[] {
  return projects
    .filter((project) => project.git_commits > 0 && !project.git_daily)
    .map((project) => project.path)
    .filter((path) => !attemptedKeys.has(buildGitDailyAutoRefreshAttemptKey(path, identitySignature)))
    .sort();
}

/** 判断当前在途任务是否应继续保留，不被下一次调度覆盖。 */
export function shouldKeepActiveGitDailyRefreshJob(
  current: GitDailyRefreshRequest | null,
  next: GitDailyRefreshRequest | null,
): boolean {
  if (!current) {
    return false;
  }

  if (current.reason === "identity" && (!next || next.reason === "missing")) {
    return true;
  }

  return shouldReuseGitDailyRefreshJob(current, next);
}

/** 判断新的 Git Daily 刷新请求是否可以直接复用当前在途任务。 */
export function shouldReuseGitDailyRefreshJob(
  current: GitDailyRefreshRequest | null,
  next: GitDailyRefreshRequest | null,
): boolean {
  if (!current || !next) {
    return false;
  }

  if (current.signature === next.signature) {
    return true;
  }

  if (current.reason !== "missing" || next.reason !== "missing") {
    return false;
  }

  if (current.paths.length === 0 || next.paths.length === 0) {
    return false;
  }

  const currentPathSet = new Set(current.paths);
  return next.paths.every((path) => currentPathSet.has(path));
}
