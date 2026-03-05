import { invokeCommand } from "../platform/commandClient";

import type { FsListResponse, FsReadResponse, FsWriteResponse } from "../models/filesystem";

/** 列出项目内指定目录的直接子项。 */
export async function listProjectDirEntries(path: string, relativePath: string, showHidden: boolean) {
  return invokeCommand<FsListResponse>("list_project_dir_entries", { path, relativePath, showHidden });
}

/** 读取项目内指定文件内容（只读预览）。 */
export async function readProjectFile(path: string, relativePath: string) {
  return invokeCommand<FsReadResponse>("read_project_file", { path, relativePath });
}

/** 写入项目内指定文件内容（文本编辑保存）。 */
export async function writeProjectFile(path: string, relativePath: string, content: string) {
  return invokeCommand<FsWriteResponse>("write_project_file", { path, relativePath, content });
}
