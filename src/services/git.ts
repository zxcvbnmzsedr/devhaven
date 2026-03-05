import { invokeCommand } from "../platform/commandClient";

import type { BranchListItem } from "../models/branch";

/** 获取指定 Git 仓库根目录的分支列表。 */
export async function listBranches(basePath: string): Promise<BranchListItem[]> {
  return invokeCommand<BranchListItem[]>("list_branches", { basePath });
}
