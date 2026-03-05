import { invokeCommand } from "../platform/commandClient";

export type GitWorktreeAddPayload = {
  path: string;
  targetPath?: string;
  branch: string;
  createBranch: boolean;
};

export type GitWorktreeAddResult = {
  path: string;
  branch: string;
};

export type GitWorktreeListItem = {
  path: string;
  branch: string;
};

export type GitWorktreeRemovePayload = {
  path: string;
  worktreePath: string;
  force?: boolean;
};

export type GitDeleteBranchPayload = {
  path: string;
  branch: string;
  force?: boolean;
};

export async function gitWorktreeAdd(payload: GitWorktreeAddPayload): Promise<GitWorktreeAddResult> {
  const params: Record<string, unknown> = {
    path: payload.path,
    branch: payload.branch,
    createBranch: payload.createBranch,
  };
  const targetPath = payload.targetPath?.trim();
  if (targetPath) {
    params.targetPath = targetPath;
  }
  return invokeCommand<GitWorktreeAddResult>("git_worktree_add", params);
}

export async function gitWorktreeList(path: string): Promise<GitWorktreeListItem[]> {
  return invokeCommand<GitWorktreeListItem[]>("git_worktree_list", { path });
}

export async function gitWorktreeRemove(payload: GitWorktreeRemovePayload): Promise<void> {
  await invokeCommand("git_worktree_remove", {
    path: payload.path,
    worktreePath: payload.worktreePath,
    force: payload.force ?? false,
  });
}

export async function gitDeleteBranch(payload: GitDeleteBranchPayload): Promise<void> {
  await invokeCommand("git_delete_branch", {
    path: payload.path,
    branch: payload.branch,
    force: payload.force ?? false,
  });
}
