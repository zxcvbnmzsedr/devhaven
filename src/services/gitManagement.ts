import { invokeCommand } from "../platform/commandClient";

import type { GitDiffContents, GitRepoStatus } from "../models/gitManagement";

export async function gitIsRepo(path: string): Promise<boolean> {
  return invokeCommand<boolean>("git_is_repo", { path });
}

export async function gitGetStatus(path: string): Promise<GitRepoStatus> {
  return invokeCommand<GitRepoStatus>("git_get_status", { path });
}

export async function gitGetDiffContents(
  path: string,
  relativePath: string,
  staged: boolean,
  oldRelativePath?: string | null,
): Promise<GitDiffContents> {
  return invokeCommand<GitDiffContents>("git_get_diff_contents", {
    path,
    relativePath,
    staged,
    oldRelativePath: oldRelativePath ?? null,
  });
}

export async function gitStageFiles(path: string, relativePaths: string[]): Promise<void> {
  await invokeCommand<void>("git_stage_files", { path, relativePaths });
}

export async function gitUnstageFiles(path: string, relativePaths: string[]): Promise<void> {
  await invokeCommand<void>("git_unstage_files", { path, relativePaths });
}

export async function gitDiscardFiles(path: string, relativePaths: string[]): Promise<void> {
  await invokeCommand<void>("git_discard_files", { path, relativePaths });
}

export async function gitCommit(path: string, message: string): Promise<void> {
  await invokeCommand<void>("git_commit", { path, message });
}

export async function gitCheckoutBranch(path: string, branch: string): Promise<void> {
  await invokeCommand<void>("git_checkout_branch", { path, branch });
}
