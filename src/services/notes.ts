import { invokeCommand } from "../platform/commandClient";

export type ProjectNotesPreview = {
  path: string;
  notesPreview: string | null;
};

/** 读取项目备注内容，未设置时返回 null。 */
export async function readProjectNotes(path: string): Promise<string | null> {
  return invokeCommand<string | null>("read_project_notes", { path });
}

/** 写入项目备注内容，传 null 则删除备注文件。 */
export async function writeProjectNotes(path: string, notes: string | null) {
  await invokeCommand("write_project_notes", { path, notes });
}

/** 读取项目 Todo 内容，未设置时返回 null。 */
export async function readProjectTodo(path: string): Promise<string | null> {
  return invokeCommand<string | null>("read_project_todo", { path });
}

/** 写入项目 Todo 内容，传 null 则删除 Todo 文件。 */
export async function writeProjectTodo(path: string, todo: string | null) {
  await invokeCommand("write_project_todo", { path, todo });
}

/** 批量读取项目备注预览（首行文本）。 */
export async function readProjectNotesPreviews(paths: string[]): Promise<ProjectNotesPreview[]> {
  if (paths.length === 0) {
    return [];
  }
  return invokeCommand<ProjectNotesPreview[]>("read_project_notes_previews", { paths });
}
