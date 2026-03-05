import { invokeCommand } from "../platform/commandClient";

import type { MarkdownFileEntry } from "../models/markdown";

/** 读取项目中的 Markdown 文件清单。 */
export async function listProjectMarkdownFiles(path: string) {
  return invokeCommand<MarkdownFileEntry[]>("list_project_markdown_files", { path });
}

/** 读取指定 Markdown 文件内容。 */
export async function readProjectMarkdownFile(path: string, relativePath: string) {
  return invokeCommand<string>("read_project_markdown_file", { path, relativePath });
}
