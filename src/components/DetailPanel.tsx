import { memo, useEffect, useMemo, useRef, useState } from "react";
import DOMPurify from "dompurify";
import { marked } from "marked";

import type { Project, ProjectScript, ScriptParamField, SharedScriptEntry, TagData } from "../models/types";
import type { BranchListItem } from "../models/branch";
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
import DetailOverviewTab from "./DetailOverviewTab";
import DetailEditTab from "./DetailEditTab";
import DetailAutomationTab from "./DetailAutomationTab";

export type DetailPanelProps = {
  isOpen: boolean;
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

type DetailTab = "overview" | "edit" | "automation";
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

/** 右侧详情面板（overlay 抽屉），负责项目详情、编辑与自动化管理。 */
function DetailPanel({
  isOpen,
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
    if (!project || activeTab !== "automation") {
      return;
    }
    void refreshWorktrees(project.path);
  }, [project?.id, activeTab]);

  const refreshWorktrees = async (path: string) => {
    try {
      const list = await listBranches(path);
      setBranches(list);
      setWorktreeError(null);
    } catch (error) {
      setWorktreeError(error instanceof Error ? error.message : String(error));
    }
  };

  const handleAddTag = (tagName: string) => {
    if (!project) {
      return;
    }
    void onAddTagToProject(project.id, tagName);
  };

  const handleRemoveTag = (tagName: string) => {
    if (!project) {
      return;
    }
    void onRemoveTagFromProject(project.id, tagName);
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

  const handleInitFromReadme = () => {
    if (fallbackReadme) {
      setNotes(fallbackReadme.content);
      setHasProjectNotes(true);
    }
  };

  const handleRunScript = (scriptId: string) => {
    if (!project) {
      return;
    }
    void onRunProjectScript(project.id, scriptId);
  };

  const handleStopScript = (scriptId: string) => {
    if (!project) {
      return;
    }
    void onStopProjectScript(project.id, scriptId);
  };

  const handleNewScript = () => {
    setScriptDialog(
      createScriptDialogState({
        mode: "new",
        scriptId: null,
        name: "",
        start: "",
        paramSchema: [],
        templateParams: {},
      }),
    );
  };

  const handleEditScript = (script: ProjectScript) => {
    setScriptDialog(
      createScriptDialogState({
        mode: "edit",
        scriptId: script.id,
        name: script.name,
        start: script.start,
        paramSchema: script.paramSchema,
        templateParams: script.templateParams,
      }),
    );
  };

  const handleRemoveScript = (scriptId: string) => {
    if (!project) {
      return;
    }
    void onRemoveProjectScript(project.id, scriptId);
  };

  const handleRefreshBranches = () => {
    if (!project) {
      return;
    }
    void refreshWorktrees(project.path);
  };

  const scripts = useMemo(() => project?.scripts ?? [], [project]);
  const displayPath = useMemo(() => formatPathWithTilde(project?.path ?? ""), [project?.path]);
  const fallbackReadmePreview = useMemo(() => {
    if (!fallbackReadme?.content) {
      return "";
    }
    const rendered = marked.parse(fallbackReadme.content);
    return typeof rendered === "string" ? DOMPurify.sanitize(rendered) : "";
  }, [fallbackReadme?.content]);

  const asideClass = `absolute right-0 top-0 h-full w-[420px] flex flex-col border-l border-divider bg-background shadow-2xl z-50 overflow-hidden transition-transform duration-200 ease-out ${
    isOpen ? "translate-x-0" : "translate-x-full pointer-events-none"
  }`;

  if (!project) {
    return (
      <aside className={asideClass}>
        <div className="p-4 text-secondary-text">请选择一个项目查看详情</div>
      </aside>
    );
  }

  return (
    <aside className={asideClass}>
      <div className="flex items-center justify-between border-b border-divider bg-secondary-background p-4">
        <div>
          <div className="text-[16px] font-semibold">{project.name}</div>
          <div className="max-w-[360px] truncate text-fs-caption text-secondary-text" title={project.path}>
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
            activeTab === "edit" ? "bg-[rgba(69,59,231,0.2)] text-text" : "text-secondary-text"
          }`}
          onClick={() => setActiveTab("edit")}
        >
          编辑
        </button>
        <button
          className={`rounded-lg px-3 py-1.5 ${
            activeTab === "automation" ? "bg-[rgba(69,59,231,0.2)] text-text" : "text-secondary-text"
          }`}
          onClick={() => setActiveTab("automation")}
        >
          自动化
        </button>
      </div>
      {activeTab === "overview" ? (
        <DetailOverviewTab
          project={project}
          projectTags={projectTags}
          availableTags={availableTags}
          getTagColor={getTagColor}
          onAddTag={handleAddTag}
          onRemoveTag={handleRemoveTag}
          todoItems={todoItems}
          todoDraft={todoDraft}
          onTodoDraftChange={setTodoDraft}
          onAddTodo={handleAddTodo}
          onToggleTodo={handleToggleTodo}
          onRemoveTodo={handleRemoveTodo}
        />
      ) : activeTab === "edit" ? (
        <DetailEditTab
          project={project}
          notes={notes}
          onNotesChange={setNotes}
          hasProjectNotes={hasProjectNotes}
          fallbackReadme={fallbackReadme}
          fallbackReadmeLoading={fallbackReadmeLoading}
          fallbackReadmePreview={fallbackReadmePreview}
          onInitFromReadme={handleInitFromReadme}
        />
      ) : (
        <DetailAutomationTab
          project={project}
          scripts={scripts}
          onRunScript={handleRunScript}
          onStopScript={handleStopScript}
          onNewScript={handleNewScript}
          onEditScript={handleEditScript}
          onRemoveScript={handleRemoveScript}
          branches={branches}
          worktreeError={worktreeError}
          onRefreshBranches={handleRefreshBranches}
        />
      )}

      {scriptDialog ? (
        <div className="absolute inset-0 z-50 flex items-center justify-center bg-[rgba(0,0,0,0.45)]" role="dialog" aria-modal>
          <div className="modal-panel max-h-[calc(100%-32px)] overflow-y-auto">
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

export default memo(DetailPanel);

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
