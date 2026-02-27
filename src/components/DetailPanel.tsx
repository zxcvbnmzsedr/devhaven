import { useEffect, useMemo, useRef, useState } from "react";
import { marked } from "marked";

import type { Project, ProjectScript, ScriptParamField, SharedScriptEntry, TagData } from "../models/types";
import type { BranchListItem } from "../models/branch";
import { swiftDateToJsDate } from "../models/types";
import { readProjectMarkdownFile } from "../services/markdown";
import { readProjectNotes, readProjectTodo, writeProjectNotes, writeProjectTodo } from "../services/notes";
import { listSharedScripts } from "../services/sharedScripts";
import { listBranches } from "../services/git";
import {
  applySharedScriptCommandTemplate,
  buildTemplateParams,
  mergeScriptParamSchema,
  renderScriptTemplateCommand,
} from "../utils/scriptTemplate";
import { formatPathWithTilde } from "../utils/pathDisplay";
import { IconX } from "./Icons";
import ProjectMarkdownSection from "./ProjectMarkdownSection";

export type DetailPanelProps = {
  project: Project | null;
  tags: TagData[];
  onClose: () => void;
  onAddTagToProject: (projectId: string, tag: string) => Promise<void>;
  onRemoveTagFromProject: (projectId: string, tag: string) => Promise<void>;
  onRunProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  onStopProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  onAddProjectScript: (
    projectId: string,
    script: {
      name: string;
      start: string;
      paramSchema?: ProjectScript["paramSchema"];
      templateParams?: ProjectScript["templateParams"];
    },
  ) => Promise<void>;
  onUpdateProjectScript: (projectId: string, script: ProjectScript) => Promise<void>;
  onRemoveProjectScript: (projectId: string, scriptId: string) => Promise<void>;
  sharedScriptsRoot: string;
  getTagColor: (tag: string) => string;
};

type DetailTab = "overview" | "branches";
type TodoItem = {
  id: string;
  text: string;
  done: boolean;
};

type ScriptDialogState = {
  mode: "new" | "edit";
  scriptId: string | null;
  name: string;
  start: string;
  error: string;
  selectedSharedScriptId: string;
  paramSchema: ScriptParamField[];
  templateParams: Record<string, string>;
};

/** 格式化 Swift 时间戳为中文时间。 */
const formatDate = (swiftDate: number) => {
  if (!swiftDate) {
    return "--";
  }
  const date = swiftDateToJsDate(swiftDate);
  return date.toLocaleString("zh-CN");
};

/** 右侧详情面板，负责项目详情、备注与分支管理。 */
export default function DetailPanel({
  project,
  tags,
  onClose,
  onAddTagToProject,
  onRemoveTagFromProject,
  onRunProjectScript,
  onStopProjectScript,
  onAddProjectScript,
  onUpdateProjectScript,
  onRemoveProjectScript,
  sharedScriptsRoot,
  getTagColor,
}: DetailPanelProps) {
  const [activeTab, setActiveTab] = useState<DetailTab>("overview");
  const [notes, setNotes] = useState("");
  const [notesSnapshot, setNotesSnapshot] = useState("");
  const [todoItems, setTodoItems] = useState<TodoItem[]>([]);
  const [todoSnapshot, setTodoSnapshot] = useState("");
  const [todoDraft, setTodoDraft] = useState("");
  const [todoLoaded, setTodoLoaded] = useState(false);
  const [hasProjectNotes, setHasProjectNotes] = useState(false);
  const [notesLoaded, setNotesLoaded] = useState(false);
  const [fallbackReadme, setFallbackReadme] = useState<{
    path: string;
    content: string;
  } | null>(null);
  const [fallbackReadmeLoading, setFallbackReadmeLoading] = useState(false);
  const [branches, setBranches] = useState<BranchListItem[]>([]);
  const [worktreeError, setWorktreeError] = useState<string | null>(null);
  const [scriptDialog, setScriptDialog] = useState<ScriptDialogState | null>(null);
  const [sharedScripts, setSharedScripts] = useState<SharedScriptEntry[]>([]);
  const [sharedScriptsLoading, setSharedScriptsLoading] = useState(false);
  const [sharedScriptsError, setSharedScriptsError] = useState<string | null>(null);

  const saveTimer = useRef<number | null>(null);
  const todoSaveTimer = useRef<number | null>(null);
  const isScriptDialogOpen = Boolean(scriptDialog);

  const projectTags = useMemo(() => project?.tags ?? [], [project]);
  const availableTags = useMemo(
    () => tags.filter((tag) => !projectTags.includes(tag.name)),
    [tags, projectTags],
  );

  useEffect(() => {
    if (!project) {
      setNotesLoaded(false);
      setTodoLoaded(false);
      setHasProjectNotes(false);
      setFallbackReadme(null);
      setFallbackReadmeLoading(false);
      setTodoItems([]);
      setTodoSnapshot("");
      setTodoDraft("");
      return;
    }

    if (saveTimer.current) {
      window.clearTimeout(saveTimer.current);
      saveTimer.current = null;
    }
    if (todoSaveTimer.current) {
      window.clearTimeout(todoSaveTimer.current);
      todoSaveTimer.current = null;
    }

    let cancelled = false;
    setNotesLoaded(false);
    setTodoLoaded(false);
    setHasProjectNotes(false);
    setFallbackReadme(null);
    setFallbackReadmeLoading(false);
    setNotes("");
    setNotesSnapshot("");
    setTodoItems([]);
    setTodoSnapshot("");
    setTodoDraft("");

    readProjectNotes(project.path)
      .then((value) => {
        if (cancelled) {
          return;
        }
        const resolved = value ?? "";
        setNotes(resolved);
        setNotesSnapshot(resolved);
        setHasProjectNotes(Boolean(value?.trim()));
        setNotesLoaded(true);
      })
      .catch(() => {
        if (cancelled) {
          return;
        }
        setNotes("");
        setNotesSnapshot("");
        setHasProjectNotes(false);
        setNotesLoaded(true);
      });

    readProjectTodo(project.path)
      .then((value) => {
        if (cancelled) {
          return;
        }
        const parsedItems = parseTodoMarkdown(value ?? "");
        setTodoItems(parsedItems);
        setTodoSnapshot(serializeTodoMarkdown(parsedItems));
        setTodoLoaded(true);
      })
      .catch(() => {
        if (cancelled) {
          return;
        }
        setTodoItems([]);
        setTodoSnapshot("");
        setTodoLoaded(true);
      });

    return () => {
      cancelled = true;
      if (saveTimer.current) {
        window.clearTimeout(saveTimer.current);
        saveTimer.current = null;
      }
      if (todoSaveTimer.current) {
        window.clearTimeout(todoSaveTimer.current);
        todoSaveTimer.current = null;
      }
    };
  }, [project?.id]);

  useEffect(() => {
    setScriptDialog(null);
  }, [project?.id]);

  useEffect(() => {
    if (!isScriptDialogOpen) {
      return;
    }
    let cancelled = false;
    setSharedScriptsLoading(true);
    setSharedScriptsError(null);
    void listSharedScripts(sharedScriptsRoot)
      .then((entries) => {
        if (cancelled) {
          return;
        }
        setSharedScripts(entries);
      })
      .catch((error) => {
        if (cancelled) {
          return;
        }
        setSharedScriptsError(error instanceof Error ? error.message : "加载通用脚本失败");
        setSharedScripts([]);
      })
      .finally(() => {
        if (cancelled) {
          return;
        }
        setSharedScriptsLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [isScriptDialogOpen, sharedScriptsRoot]);

  useEffect(() => {
    if (!project) {
      return;
    }
    if (notes === notesSnapshot) {
      return;
    }
    if (saveTimer.current) {
      window.clearTimeout(saveTimer.current);
    }

    const projectPath = project.path;
    const nextNotes = notes;

    saveTimer.current = window.setTimeout(() => {
      const trimmed = nextNotes.trim();
      void writeProjectNotes(projectPath, trimmed ? trimmed : null)
        .then(() => {
          setNotesSnapshot(nextNotes);
          setHasProjectNotes(Boolean(trimmed));
        })
        .catch(() => {
          // 忽略保存失败，继续保留本地输入，等待用户后续编辑触发重试。
        });
    }, 800);

    return () => {
      if (saveTimer.current) {
        window.clearTimeout(saveTimer.current);
        saveTimer.current = null;
      }
    };
  }, [notes, notesSnapshot, project?.id, project?.path]);

  useEffect(() => {
    if (!project || !todoLoaded) {
      return;
    }
    const serialized = serializeTodoMarkdown(todoItems);
    if (serialized === todoSnapshot) {
      return;
    }
    if (todoSaveTimer.current) {
      window.clearTimeout(todoSaveTimer.current);
    }

    const projectPath = project.path;
    todoSaveTimer.current = window.setTimeout(() => {
      void writeProjectTodo(projectPath, serialized ? serialized : null)
        .then(() => {
          setTodoSnapshot(serialized);
        })
        .catch(() => {
          // 忽略保存失败，保留当前输入，等待后续编辑重试。
        });
    }, 400);

    return () => {
      if (todoSaveTimer.current) {
        window.clearTimeout(todoSaveTimer.current);
        todoSaveTimer.current = null;
      }
    };
  }, [project, todoItems, todoLoaded, todoSnapshot]);

  useEffect(() => {
    if (!project || !notesLoaded || hasProjectNotes) {
      setFallbackReadme(null);
      setFallbackReadmeLoading(false);
      return;
    }

    let cancelled = false;
    setFallbackReadmeLoading(true);
    setFallbackReadme(null);

    const readmeCandidates = ["README.md", "README.MD", "readme.md", "Readme.md"];

    void (async () => {
      for (const candidate of readmeCandidates) {
        try {
          const content = await readProjectMarkdownFile(project.path, candidate);
          if (cancelled) {
            return;
          }
          setFallbackReadme({ path: candidate, content });
          setFallbackReadmeLoading(false);
          return;
        } catch {
          continue;
        }
      }

      if (!cancelled) {
        setFallbackReadme(null);
        setFallbackReadmeLoading(false);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, [hasProjectNotes, notesLoaded, project?.id, project?.path]);

  useEffect(() => {
    if (!project || activeTab !== "branches") {
      return;
    }
    void refreshWorktrees(project.path);
  }, [project?.id, activeTab]);

  /** 读取当前项目的分支列表。 */
  const refreshWorktrees = async (path: string) => {
    try {
      const list = await listBranches(path);
      setBranches(list);
      setWorktreeError(null);
    } catch (error) {
      setWorktreeError(error instanceof Error ? error.message : String(error));
    }
  };

  /** 为项目添加标签。 */
  const handleAddTag = async (tagName: string) => {
    if (!project) {
      return;
    }
    await onAddTagToProject(project.id, tagName);
  };

  /** 从项目移除标签。 */
  const handleRemoveTag = async (tagName: string) => {
    if (!project) {
      return;
    }
    await onRemoveTagFromProject(project.id, tagName);
  };

  const handleAddTodo = () => {
    const text = todoDraft.trim();
    if (!text) {
      return;
    }
    setTodoItems((prev) => [...prev, { id: createTodoItemId(), text, done: false }]);
    setTodoDraft("");
  };

  const handleToggleTodo = (todoId: string, done: boolean) => {
    setTodoItems((prev) =>
      prev.map((item) => (item.id === todoId ? { ...item, done } : item)),
    );
  };

  const handleRemoveTodo = (todoId: string) => {
    setTodoItems((prev) => prev.filter((item) => item.id !== todoId));
  };

  const scripts = useMemo(() => project?.scripts ?? [], [project]);
  const displayPath = useMemo(() => formatPathWithTilde(project?.path ?? ""), [project?.path]);
  const shouldShowReadmeFallback = !hasProjectNotes && notes.trim().length === 0;
  const fallbackReadmePreview = useMemo(() => {
    if (!fallbackReadme?.content) {
      return "";
    }
    const rendered = marked.parse(fallbackReadme.content);
    return typeof rendered === "string" ? rendered : "";
  }, [fallbackReadme?.content]);

  if (!project) {
    return (
      <aside className="flex min-w-detail max-w-detail flex-col border-l border-divider bg-background pb-4 overflow-hidden">
        <div className="p-4 text-secondary-text">请选择一个项目查看详情</div>
      </aside>
    );
  }

  return (
    <aside className="flex min-w-detail max-w-detail flex-col border-l border-divider bg-background pb-4 overflow-hidden">
      <div className="flex items-center justify-between border-b border-divider bg-secondary-background p-4">
        <div>
          <div className="text-[16px] font-semibold">{project.name}</div>
          <div className="max-w-[320px] truncate text-fs-caption text-secondary-text" title={project.path}>
            {displayPath}
          </div>
        </div>
        <button className="icon-btn" onClick={onClose} aria-label="关闭">
          <IconX size={14} />
        </button>
      </div>
      <div className="flex gap-2 border-b border-divider px-4 py-2">
        <button
          className={`rounded-lg px-3 py-1.5 ${
            activeTab === "overview" ? "bg-[rgba(69,59,231,0.2)] text-text" : "text-secondary-text"
          }`}
          onClick={() => setActiveTab("overview")}
        >
          概览
        </button>
        <button
          className={`rounded-lg px-3 py-1.5 ${
            activeTab === "branches" ? "bg-[rgba(69,59,231,0.2)] text-text" : "text-secondary-text"
          }`}
          onClick={() => setActiveTab("branches")}
        >
          分支
        </button>
      </div>
      {activeTab === "overview" ? (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
          <section className="flex flex-col gap-2.5">
            <div className="text-[14px] font-semibold">基础信息</div>
            <div className="grid grid-cols-[90px_1fr] gap-x-3 gap-y-1.5 text-fs-caption text-secondary-text">
              <div>最近修改</div>
              <div>{formatDate(project.mtime)}</div>
              <div>Git 提交</div>
              <div>{project.git_commits > 0 ? `${project.git_commits} 次` : "非 Git"}</div>
              <div>最后检查</div>
              <div>{formatDate(project.checked)}</div>
            </div>
          </section>

          <section className="flex flex-col gap-2.5">
            <div className="text-[14px] font-semibold">标签</div>
            <div className="flex flex-wrap gap-1.5">
              {projectTags.map((tag) => (
                <span
                  key={tag}
                  className="tag-pill"
                  style={{ background: `${getTagColor(tag)}33`, color: getTagColor(tag) }}
                >
                  {tag}
                  <button
                    className="ml-1.5 inline-flex items-center justify-center text-[12px] opacity-60 hover:opacity-100"
                    onClick={() => void handleRemoveTag(tag)}
                    aria-label={`移除标签 ${tag}`}
                  >
                    <IconX size={12} />
                  </button>
                </span>
              ))}
            </div>
            {availableTags.length > 0 ? (
              <select
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                onChange={(event) => {
                  const value = event.target.value;
                  if (value) {
                    void handleAddTag(value);
                  }
                }}
                defaultValue=""
              >
                <option value="">添加标签...</option>
                {availableTags.map((tag) => (
                  <option key={tag.name} value={tag.name}>
                    {tag.name}
                  </option>
                ))}
              </select>
            ) : (
              <div className="text-fs-caption text-secondary-text">暂无可添加标签</div>
            )}
          </section>

          <section className="flex flex-col gap-2.5">
            <div className="text-[14px] font-semibold">Todo</div>
            <div className="flex items-center gap-2">
              <input
                className="flex-1 rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                value={todoDraft}
                onChange={(event) => setTodoDraft(event.target.value)}
                onKeyDown={(event) => {
                  if (event.key === "Enter") {
                    event.preventDefault();
                    handleAddTodo();
                  }
                }}
                placeholder="输入待办并按回车添加"
              />
              <button className="btn" onClick={handleAddTodo}>
                添加
              </button>
            </div>
            {todoItems.length === 0 ? (
              <div className="text-fs-caption text-secondary-text">暂无待办</div>
            ) : (
              <div className="flex flex-col gap-2">
                {todoItems.map((item) => (
                  <label
                    key={item.id}
                    className="flex items-center gap-2 rounded-md border border-border bg-card-bg px-2.5 py-2"
                  >
                    <input
                      type="checkbox"
                      checked={item.done}
                      onChange={(event) => handleToggleTodo(item.id, event.target.checked)}
                    />
                    <span className={`flex-1 text-[13px] ${item.done ? "text-secondary-text line-through" : "text-text"}`}>
                      {item.text}
                    </span>
                    <button
                      type="button"
                      className="icon-btn"
                      aria-label="删除待办"
                      onClick={(event) => {
                        event.preventDefault();
                        event.stopPropagation();
                        handleRemoveTodo(item.id);
                      }}
                    >
                      <IconX size={12} />
                    </button>
                  </label>
                ))}
              </div>
            )}
          </section>

          <section className="flex flex-col gap-2.5">
            <div className="flex items-center justify-between gap-2">
              <div className="text-[14px] font-semibold">备注</div>
              {shouldShowReadmeFallback && fallbackReadme ? (
                <button
                  type="button"
                  className="btn"
                  onClick={() => {
                    setNotes(fallbackReadme.content);
                    setHasProjectNotes(true);
                  }}
                >
                  用 README 初始化
                </button>
              ) : null}
            </div>
            <textarea
              className="min-h-[120px] resize-y rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
              value={notes}
              onChange={(event) => setNotes(event.target.value)}
              placeholder="记录项目备注（保存到 PROJECT_NOTES.md）"
            />
            {shouldShowReadmeFallback ? (
              <div className="flex flex-col gap-2 rounded-md border border-border bg-secondary-background p-2.5">
                <div className="text-fs-caption text-secondary-text">
                  {fallbackReadmeLoading
                    ? "未发现备注，正在读取 README.md..."
                    : fallbackReadme
                      ? `未发现备注，当前展示 ${fallbackReadme.path} 作为只读参考`
                      : "未发现备注，也未找到 README.md"}
                </div>
                {fallbackReadme ? (
                  fallbackReadmePreview ? (
                    <div className="max-h-[220px] overflow-y-auto rounded-md border border-border bg-card-bg px-3 py-2.5 text-fs-caption leading-relaxed text-text">
                      <div
                        className="markdown-content"
                        dangerouslySetInnerHTML={{
                          __html: fallbackReadmePreview,
                        }}
                      />
                    </div>
                  ) : (
                    <div className="text-fs-caption text-secondary-text">README 内容为空</div>
                  )
                ) : null}
              </div>
            ) : null}
          </section>

          <section className="flex flex-col gap-2.5">
            <div className="flex items-center justify-between gap-2">
              <div className="text-[14px] font-semibold">快捷命令</div>
              <button
                className="btn"
                onClick={() =>
                  setScriptDialog(
                    createScriptDialogState({
                      mode: "new",
                      scriptId: null,
                      name: "",
                      start: "",
                      paramSchema: [],
                      templateParams: {},
                    }),
                  )
                }
              >
                新增
              </button>
            </div>
            {scripts.length === 0 ? (
              <div className="text-fs-caption text-secondary-text">暂无快捷命令</div>
            ) : (
              <div className="flex flex-col gap-2">
                {scripts.map((script) => {
                  return (
                    <div
                      key={script.id}
                      className="flex items-center justify-between gap-3 rounded-lg border border-border bg-card-bg p-3"
                      title={script.start}
                    >
                      <div className="min-w-0 flex-1">
                        <div className="truncate text-[13px] font-semibold text-text">{script.name}</div>
                        <div className="truncate text-fs-caption text-secondary-text">{script.start}</div>
                      </div>
                      <div className="flex shrink-0 flex-wrap items-center justify-end gap-2">
                        <button
                          className="btn btn-primary"
                          onClick={() => void onRunProjectScript(project.id, script.id)}
                        >
                          运行
                        </button>
                        <button className="btn btn-outline" onClick={() => void onStopProjectScript(project.id, script.id)}>
                          停止
                        </button>
                        <button
                          className="btn"
                          onClick={() =>
                            setScriptDialog(
                              createScriptDialogState({
                                mode: "edit",
                                scriptId: script.id,
                                name: script.name,
                                start: script.start,
                                paramSchema: script.paramSchema,
                                templateParams: script.templateParams,
                              }),
                            )
                          }
                        >
                          编辑
                        </button>
                        <button className="btn" onClick={() => void onRemoveProjectScript(project.id, script.id)}>
                          删除
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>

          <section className="flex flex-col gap-2.5">
            <div className="text-[14px] font-semibold">Markdown</div>
            <ProjectMarkdownSection project={project} />
          </section>

        </div>
      ) : (
        <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto p-4">
          <section className="flex flex-col gap-2.5">
            <div className="text-[14px] font-semibold">分支管理</div>
            <div className="flex flex-wrap gap-2">
              <button className="btn" onClick={() => void refreshWorktrees(project.path)}>
                刷新
              </button>
            </div>
            {worktreeError ? <div className="text-fs-caption text-error">{worktreeError}</div> : null}
            {branches.length === 0 ? (
              <div className="text-fs-caption text-secondary-text">暂无分支信息或非 Git 项目</div>
            ) : (
              <div className="flex flex-col gap-2.5">
                {branches.map((branch) => (
                  <div key={branch.name} className="flex items-center justify-between gap-3 rounded-lg border border-border bg-card-bg p-3">
                    <div>
                      <div className="text-[14px] font-semibold">
                        {branch.name}
                        {branch.isMain ? <span className="ml-1.5 text-[11px] text-accent">主分支</span> : null}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        </div>
      )}

      {scriptDialog ? (
        <div className="modal-overlay" role="dialog" aria-modal>
          <div className="modal-panel">
            <div className="text-[16px] font-semibold">{scriptDialog.mode === "new" ? "新增快捷命令" : "编辑快捷命令"}</div>
            <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
              <span>插入通用脚本（可选）</span>
              <select
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                value={scriptDialog.selectedSharedScriptId}
                onChange={(event) => {
                  const selectedId = event.target.value;
                  setScriptDialog((prev) => {
                    if (!prev) {
                      return prev;
                    }
                    if (!selectedId) {
                      return { ...prev, selectedSharedScriptId: "", error: "" };
                    }
                    const selected = sharedScripts.find((item) => item.id === selectedId);
                    if (!selected) {
                      return {
                        ...prev,
                        selectedSharedScriptId: selectedId,
                        error: "通用脚本不存在或已失效",
                      };
                    }
                    const start = applySharedScriptCommandTemplate(
                      selected.commandTemplate,
                      selected.absolutePath,
                    );
                    const paramSchema = mergeScriptParamSchema(start, selected.params, prev.templateParams);
                    const templateParams = buildTemplateParams(paramSchema, prev.templateParams);
                    return {
                      ...prev,
                      selectedSharedScriptId: selected.id,
                      name: prev.name.trim() ? prev.name : selected.name,
                      start,
                      paramSchema,
                      templateParams,
                      error: "",
                    };
                  });
                }}
              >
                <option value="">手动输入命令</option>
                {sharedScripts.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name} ({item.relativePath})
                  </option>
                ))}
              </select>
              {sharedScriptsLoading ? (
                <div className="text-fs-caption text-secondary-text">正在加载通用脚本...</div>
              ) : null}
              {sharedScriptsError ? <div className="text-fs-caption text-error">{sharedScriptsError}</div> : null}
            </label>
            <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
              <span>名称</span>
              <input
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                value={scriptDialog.name}
                onChange={(event) =>
                  setScriptDialog((prev) => (prev ? { ...prev, name: event.target.value, error: "" } : prev))
                }
              />
            </label>
            <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
              <span>启动命令</span>
              <textarea
                className="min-h-[90px] resize-y rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                value={scriptDialog.start}
                onChange={(event) => {
                  const nextStart = event.target.value;
                  setScriptDialog((prev) => {
                    if (!prev) {
                      return prev;
                    }
                    const paramSchema = mergeScriptParamSchema(
                      nextStart,
                      prev.paramSchema,
                      prev.templateParams,
                    );
                    const templateParams = buildTemplateParams(paramSchema, prev.templateParams);
                    return {
                      ...prev,
                      start: nextStart,
                      paramSchema,
                      templateParams,
                      error: "",
                    };
                  });
                }}
                placeholder="例如：pnpm dev"
              />
            </label>
            {scriptDialog.paramSchema.length > 0 ? (
              <section className="flex flex-col gap-2 rounded-md border border-border bg-secondary-background p-2.5">
                <div className="text-[13px] font-semibold text-text">参数配置</div>
                <div className="grid gap-2 sm:grid-cols-2">
                  {scriptDialog.paramSchema.map((field) => (
                    <label key={field.key} className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                      <span>
                        {field.label}
                        {field.required ? <span className="text-error"> *</span> : null}
                      </span>
                      <input
                        type={field.type === "secret" ? "password" : field.type === "number" ? "number" : "text"}
                        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                        value={scriptDialog.templateParams[field.key] ?? ""}
                        onChange={(event) =>
                          setScriptDialog((prev) =>
                            prev
                              ? {
                                  ...prev,
                                  templateParams: {
                                    ...prev.templateParams,
                                    [field.key]: event.target.value,
                                  },
                                  error: "",
                                }
                              : prev,
                          )
                        }
                        placeholder={field.defaultValue ?? `请输入 ${field.label}`}
                      />
                      {field.description ? (
                        <span className="text-fs-caption text-secondary-text">{field.description}</span>
                      ) : null}
                    </label>
                  ))}
                </div>
              </section>
            ) : null}
            {scriptDialog.error ? <div className="text-fs-caption text-error">{scriptDialog.error}</div> : null}
            <div className="flex justify-end gap-2">
              <button type="button" className="btn" onClick={() => setScriptDialog(null)}>
                取消
              </button>
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => {
                  if (!project) {
                    return;
                  }
                  const name = scriptDialog.name.trim();
                  const start = scriptDialog.start.trim();
                  if (!name) {
                    setScriptDialog((prev) => (prev ? { ...prev, error: "名称不能为空" } : prev));
                    return;
                  }
                  if (!start) {
                    setScriptDialog((prev) => (prev ? { ...prev, error: "启动命令不能为空" } : prev));
                    return;
                  }
                  const paramSchema = mergeScriptParamSchema(
                    start,
                    scriptDialog.paramSchema,
                    scriptDialog.templateParams,
                  );
                  const templateParams = buildTemplateParams(paramSchema, scriptDialog.templateParams);
                  const rendered = renderScriptTemplateCommand({
                    id: "validation-only",
                    name,
                    start,
                    paramSchema,
                    templateParams,
                  });
                  if (!rendered.ok) {
                    setScriptDialog((prev) => (prev ? { ...prev, error: rendered.error } : prev));
                    return;
                  }
                  const scriptPayload = {
                    name,
                    start,
                    paramSchema: paramSchema.length > 0 ? paramSchema : undefined,
                    templateParams: paramSchema.length > 0 ? templateParams : undefined,
                  };
                  if (scriptDialog.mode === "new") {
                    void onAddProjectScript(project.id, scriptPayload).then(() =>
                      setScriptDialog(null),
                    );
                    return;
                  }
                  const target = scripts.find((item) => item.id === scriptDialog.scriptId);
                  if (!target) {
                    setScriptDialog((prev) => (prev ? { ...prev, error: "命令不存在或已被删除" } : prev));
                    return;
                  }
                  void onUpdateProjectScript(project.id, { ...target, ...scriptPayload }).then(() =>
                    setScriptDialog(null),
                  );
                }}
              >
                保存
              </button>
            </div>
          </div>
        </div>
      ) : null}
    </aside>
  );
}

function createScriptDialogState(input: {
  mode: "new" | "edit";
  scriptId: string | null;
  name: string;
  start: string;
  paramSchema?: ScriptParamField[] | null;
  templateParams?: Record<string, string> | null;
}): ScriptDialogState {
  const start = input.start ?? "";
  const paramSchema = mergeScriptParamSchema(start, input.paramSchema, input.templateParams);
  const templateParams = buildTemplateParams(paramSchema, input.templateParams);
  return {
    mode: input.mode,
    scriptId: input.scriptId,
    name: input.name ?? "",
    start,
    error: "",
    selectedSharedScriptId: "",
    paramSchema,
    templateParams,
  };
}

function createTodoItemId(): string {
  if (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function") {
    return crypto.randomUUID();
  }
  return `${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

function parseTodoMarkdown(content: string): TodoItem[] {
  if (!content.trim()) {
    return [];
  }
  const lines = content.split(/\r?\n/);
  const items: TodoItem[] = [];
  for (const line of lines) {
    const matched = line.match(/^\s*[-*]\s+\[( |x|X)\]\s+(.*)$/);
    if (!matched) {
      continue;
    }
    const text = matched[2].trim();
    if (!text) {
      continue;
    }
    items.push({
      id: createTodoItemId(),
      text,
      done: matched[1].toLowerCase() === "x",
    });
  }
  return items;
}

function serializeTodoMarkdown(items: TodoItem[]): string {
  return items
    .map((item) => {
      const text = item.text.trim();
      if (!text) {
        return null;
      }
      return `- [${item.done ? "x" : " "}] ${text}`;
    })
    .filter((line): line is string => Boolean(line))
    .join("\n");
}
