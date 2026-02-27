import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import type {
  ScriptParamField,
  ScriptParamFieldType,
  SharedScriptEntry,
  SharedScriptManifestScript,
} from "../models/types";
import {
  listSharedScripts,
  readSharedScriptFile,
  restoreSharedScriptPresets,
  saveSharedScriptsManifest,
  writeSharedScriptFile,
} from "../services/sharedScripts";
import { IconCode, IconFile, IconSearch, IconTrash, IconX } from "./Icons";

type SharedScriptsManagerModalProps = {
  root: string;
  onClose?: () => void;
  inline?: boolean;
  headerActions?: ReactNode;
};

const DEFAULT_COMMAND_TEMPLATE = 'bash "${scriptPath}"';
const BUTTON_FOCUS_RING_CLASS =
  "focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent focus-visible:outline-offset-2";
const INPUT_CLASS =
  "w-full rounded-md border border-border bg-secondary-background px-3 py-2 text-text placeholder:text-secondary-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]";
const TEXTAREA_CLASS =
  "w-full resize-y rounded-md border border-border bg-secondary-background px-3 py-2 text-text placeholder:text-secondary-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]";
const LOCKED_INPUT_CLASS =
  "w-full rounded-md border border-dashed border-border bg-[rgba(148,163,184,0.12)] px-3 py-2 text-secondary-text cursor-not-allowed";

type SharedScriptDraft = SharedScriptManifestScript & {
  draftKey: string;
};

type CreateScriptDialogState = {
  id: string;
  name: string;
  path: string;
  usePathAsId: boolean;
  error: string | null;
};

/** 通用脚本可视化管理（支持弹窗/内嵌两种模式）。 */
export default function SharedScriptsManagerModal({
  root,
  onClose,
  inline = false,
  headerActions,
}: SharedScriptsManagerModalProps) {
  const [scripts, setScripts] = useState<SharedScriptDraft[]>([]);
  const [selectedScriptKey, setSelectedScriptKey] = useState<string | null>(null);
  const [scriptFilter, setScriptFilter] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [isSavingManifest, setIsSavingManifest] = useState(false);
  const [isRestoringPresets, setIsRestoringPresets] = useState(false);
  const [manifestError, setManifestError] = useState<string | null>(null);
  const [manifestMessage, setManifestMessage] = useState<string | null>(null);
  const [manifestSnapshot, setManifestSnapshot] = useState("");
  const [hasManifestSnapshot, setHasManifestSnapshot] = useState(false);
  const draftKeyRef = useRef(0);
  const [createScriptDialog, setCreateScriptDialog] = useState<CreateScriptDialogState | null>(null);

  const [scriptContent, setScriptContent] = useState("");
  const [scriptContentPath, setScriptContentPath] = useState<string | null>(null);
  const [scriptContentSnapshot, setScriptContentSnapshot] = useState("");
  const [isLoadingScriptContent, setIsLoadingScriptContent] = useState(false);
  const [isSavingScriptContent, setIsSavingScriptContent] = useState(false);
  const [scriptContentMessage, setScriptContentMessage] = useState<string | null>(null);
  const [scriptContentError, setScriptContentError] = useState<string | null>(null);

  const nextDraftKey = useCallback(() => {
    draftKeyRef.current += 1;
    return `shared-script-${draftKeyRef.current}-${Date.now().toString(36)}`;
  }, []);

  const selectedScript = useMemo(
    () => scripts.find((item) => item.draftKey === selectedScriptKey) ?? null,
    [scripts, selectedScriptKey],
  );

  const filterKeyword = scriptFilter.trim().toLowerCase();

  const filteredScripts = useMemo(() => {
    if (!filterKeyword) {
      return scripts;
    }
    return scripts.filter((item) =>
      [item.id, item.name, item.path]
        .map((field) => field.trim().toLowerCase())
        .some((field) => field.includes(filterKeyword)),
    );
  }, [filterKeyword, scripts]);

  const selectedScriptVisible = useMemo(() => {
    if (!selectedScript) {
      return true;
    }
    return filteredScripts.some((item) => item.draftKey === selectedScript.draftKey);
  }, [filteredScripts, selectedScript]);

  const totalParams = useMemo(
    () => scripts.reduce((sum, script) => sum + script.params.length, 0),
    [scripts],
  );

  const manifestScripts = useMemo(() => scripts.map(toManifestScript), [scripts]);
  const manifestSerialized = useMemo(
    () => serializeManifestScripts(manifestScripts),
    [manifestScripts],
  );
  const isManifestDirty = useMemo(
    () => hasManifestSnapshot && manifestSerialized !== manifestSnapshot,
    [hasManifestSnapshot, manifestSerialized, manifestSnapshot],
  );
  const isScriptContentDirty = useMemo(
    () => scriptContent !== scriptContentSnapshot,
    [scriptContent, scriptContentSnapshot],
  );

  const loadScripts = useCallback(async () => {
    setIsLoading(true);
    setManifestError(null);
    setManifestMessage(null);
    try {
      const entries = await listSharedScripts(root);
      const normalized = entries.map((entry) => mapSharedEntryToScriptDraft(entry, nextDraftKey()));
      setScripts(normalized);
      setManifestSnapshot(serializeManifestScripts(normalized.map(toManifestScript)));
      setHasManifestSnapshot(true);
      setSelectedScriptKey((prev) => {
        if (prev && normalized.some((item) => item.draftKey === prev)) {
          return prev;
        }
        return normalized[0]?.draftKey ?? null;
      });
    } catch (error) {
      setScripts([]);
      setSelectedScriptKey(null);
      setManifestSnapshot("");
      setHasManifestSnapshot(false);
      setManifestError(error instanceof Error ? error.message : "加载通用脚本失败");
    } finally {
      setIsLoading(false);
    }
  }, [nextDraftKey, root]);

  useEffect(() => {
    if (!hasManifestSnapshot || !isManifestDirty || isLoading || isRestoringPresets || isSavingManifest) {
      return;
    }
    const validationError = validateScripts(manifestScripts);
    if (validationError) {
      setManifestError(validationError);
      return;
    }

    setManifestError(null);
    const timer = window.setTimeout(() => {
      void (async () => {
        setIsSavingManifest(true);
        try {
          await saveSharedScriptsManifest(manifestScripts, root);
          setManifestSnapshot(manifestSerialized);
          setHasManifestSnapshot(true);
          setManifestMessage(null);
        } catch (error) {
          setManifestError(error instanceof Error ? error.message : "自动保存通用脚本清单失败");
        } finally {
          setIsSavingManifest(false);
        }
      })();
    }, 350);

    return () => {
      window.clearTimeout(timer);
    };
  }, [
    hasManifestSnapshot,
    isLoading,
    isManifestDirty,
    isRestoringPresets,
    isSavingManifest,
    manifestScripts,
    manifestSerialized,
    root,
  ]);

  useEffect(() => {
    void loadScripts();
  }, [loadScripts]);

  useEffect(() => {
    if (!selectedScript || !selectedScript.path.trim()) {
      setScriptContent("");
      setScriptContentSnapshot("");
      setScriptContentPath(null);
      setScriptContentError(null);
      setScriptContentMessage(null);
      setIsLoadingScriptContent(false);
      return;
    }
    let cancelled = false;
    const relativePath = selectedScript.path.trim();
    setIsLoadingScriptContent(true);
    setScriptContentError(null);
    setScriptContentMessage(null);
    void readSharedScriptFile(relativePath, root)
      .then((content) => {
        if (cancelled) {
          return;
        }
        setScriptContent(content);
        setScriptContentSnapshot(content);
        setScriptContentPath(relativePath);
      })
      .catch(() => {
        if (cancelled) {
          return;
        }
        setScriptContent("");
        setScriptContentSnapshot("");
        setScriptContentPath(relativePath);
        setScriptContentError("脚本文件不存在，保存内容后将自动创建。");
      })
      .finally(() => {
        if (cancelled) {
          return;
        }
        setIsLoadingScriptContent(false);
      });
    return () => {
      cancelled = true;
    };
  }, [root, selectedScript?.draftKey, selectedScript?.path]);

  const handleAddScript = () => {
    setCreateScriptDialog(createEmptyCreateScriptDialogState());
    setManifestError(null);
    setManifestMessage(null);
  };

  const handleConfirmCreateScript = () => {
    if (!createScriptDialog) {
      return;
    }
    const normalizedPath = normalizeRelativePath(createScriptDialog.path);
    if (!normalizedPath) {
      setCreateScriptDialog((prev) => (prev ? { ...prev, error: "请先填写脚本相对路径。" } : prev));
      return;
    }
    if (!isSafeRelativePath(normalizedPath)) {
      setCreateScriptDialog((prev) => (prev ? { ...prev, error: `脚本相对路径不合法：${normalizedPath}` } : prev));
      return;
    }

    const scriptId = (createScriptDialog.usePathAsId ? normalizedPath : createScriptDialog.id).trim();
    if (!scriptId) {
      setCreateScriptDialog((prev) => (prev ? { ...prev, error: "脚本 ID 不能为空。" } : prev));
      return;
    }
    if (scripts.some((item) => item.id.trim() === scriptId)) {
      setCreateScriptDialog((prev) => (prev ? { ...prev, error: `脚本 ID 已存在：${scriptId}` } : prev));
      return;
    }
    if (scripts.some((item) => normalizeRelativePath(item.path) === normalizedPath)) {
      setCreateScriptDialog((prev) => (prev ? { ...prev, error: `脚本路径已存在：${normalizedPath}` } : prev));
      return;
    }

    const draft: SharedScriptDraft = {
      draftKey: nextDraftKey(),
      id: scriptId,
      name: createScriptDialog.name.trim() || deriveScriptName(normalizedPath),
      path: normalizedPath,
      commandTemplate: DEFAULT_COMMAND_TEMPLATE,
      params: [],
    };
    setScripts((prev) => [...prev, draft]);
    setSelectedScriptKey(draft.draftKey);
    setScriptFilter("");
    setCreateScriptDialog(null);
    setManifestError(null);
    setManifestMessage(null);
  };

  const handleRemoveSelectedScript = () => {
    if (!selectedScript) {
      return;
    }
    setScripts((prev) => {
      const next = prev.filter((item) => item.draftKey !== selectedScript.draftKey);
      setSelectedScriptKey(next[0]?.draftKey ?? null);
      return next;
    });
    setManifestError(null);
    setManifestMessage(null);
  };

  const patchSelectedScript = (patch: Partial<SharedScriptManifestScript>) => {
    if (!selectedScript) {
      return;
    }
    setScripts((prev) =>
      prev.map((item) =>
        item.draftKey === selectedScript.draftKey
          ? {
              ...item,
              ...patch,
            }
          : item,
      ),
    );
    setManifestError(null);
    setManifestMessage(null);
  };

  const handleRestorePresets = async () => {
    setManifestError(null);
    setManifestMessage(null);
    setIsRestoringPresets(true);
    try {
      const result = await restoreSharedScriptPresets(root);
      await loadScripts();
      setScriptFilter("");
      setManifestMessage(
        `内置预设已同步（版本 ${result.presetVersion}）：新增 ${result.addedScripts} 项，补齐文件 ${result.createdFiles} 个。`,
      );
    } catch (error) {
      setManifestError(error instanceof Error ? error.message : "恢复内置预设失败");
    } finally {
      setIsRestoringPresets(false);
    }
  };

  const handleSaveScriptContent = async () => {
    if (!selectedScript) {
      return;
    }
    const relativePath = selectedScript.path.trim();
    if (!relativePath) {
      setScriptContentError("请先填写脚本相对路径。");
      return;
    }
    if (!isScriptContentDirty) {
      setScriptContentMessage("脚本内容未发生变化。");
      return;
    }
    setScriptContentError(null);
    setScriptContentMessage(null);
    setIsSavingScriptContent(true);
    try {
      await writeSharedScriptFile(relativePath, scriptContent, root);
      setScriptContentPath(relativePath);
      setScriptContentSnapshot(scriptContent);
      setScriptContentMessage("脚本文件已保存。");
    } catch (error) {
      setScriptContentError(error instanceof Error ? error.message : "保存脚本文件失败");
    } finally {
      setIsSavingScriptContent(false);
    }
  };

  const panel = (
    <div
      className={
        inline
          ? "flex flex-col gap-3 rounded-xl border border-border bg-secondary-background p-3"
          : "modal-panel min-w-[960px] w-[min(1240px,96vw)] max-h-[92vh] overflow-y-auto"
      }
    >
      <header className="rounded-xl border border-border bg-card-bg p-3.5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="text-[16px] font-semibold text-text">通用脚本管理</div>
            <div className="mt-1 text-fs-caption text-secondary-text">
              在这里维护脚本清单、参数模型与脚本文件内容。
            </div>
          </div>
          {headerActions || (!inline && onClose) ? (
            <div className="flex items-center gap-2">
              {headerActions}
              {!inline && onClose ? (
                <button
                  className={`icon-btn min-h-[40px] min-w-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                  onClick={onClose}
                  aria-label="关闭"
                >
                  <IconX size={14} />
                </button>
              ) : null}
            </div>
          ) : null}
        </div>

        <div className="mt-3 grid gap-2 sm:grid-cols-3">
          <StatusPill label="脚本总数" value={`${scripts.length}`} tone="neutral" />
          <StatusPill label="参数字段" value={`${totalParams}`} tone="neutral" />
          <StatusPill
            label="清单状态"
            value={isSavingManifest ? "自动保存中" : isManifestDirty ? "待自动保存" : "已同步"}
            tone={isSavingManifest || isManifestDirty ? "accent" : "neutral"}
          />
        </div>

        <div className="mt-2 rounded-lg border border-border bg-secondary-background px-3 py-2 text-fs-caption text-secondary-text">
          根目录：<span className="font-mono text-[11px] text-text">{root}</span>
        </div>
      </header>

      <section className="grid min-h-0 gap-3 xl:grid-cols-[300px_minmax(0,1fr)]">
        <aside className="flex min-h-[520px] flex-col rounded-xl border border-border bg-card-bg p-3">
          <div className="mb-2 flex items-center justify-between gap-2">
            <div>
              <div className="text-[13px] font-semibold text-text">脚本清单</div>
              <div className="text-fs-caption text-secondary-text">
                {filteredScripts.length}/{scripts.length} 个脚本
              </div>
            </div>
            <button
              className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
              onClick={handleAddScript}
              disabled={isLoading}
            >
              新增脚本
            </button>
          </div>

          <label className="relative block" aria-label="搜索脚本">
            <IconSearch
              size={14}
              className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-secondary-text"
            />
            <input
              className={`${INPUT_CLASS} pl-9`}
              value={scriptFilter}
              onChange={(event) => setScriptFilter(event.target.value)}
              placeholder="按名称 / ID / 路径搜索"
            />
          </label>

          <div className="mt-2 min-h-0 flex-1 overflow-y-auto pr-1">
            {isLoading ? (
              <div className="rounded-lg border border-border bg-secondary-background px-3 py-3 text-fs-caption text-secondary-text">
                加载中...
              </div>
            ) : filteredScripts.length === 0 ? (
              <div className="rounded-lg border border-dashed border-border bg-secondary-background px-3 py-3 text-fs-caption text-secondary-text">
                {scripts.length === 0
                  ? '暂无脚本，点击上方“新增脚本”创建。'
                  : "没有匹配结果，尝试清空搜索关键字。"}
              </div>
            ) : (
              <div className="flex flex-col gap-1.5">
                {filteredScripts.map((item) => {
                  const isSelected = item.draftKey === selectedScriptKey;
                  return (
                    <button
                      key={item.draftKey}
                      className={[
                        "min-h-[72px] rounded-lg border px-3 py-2 text-left transition-colors",
                        BUTTON_FOCUS_RING_CLASS,
                        isSelected
                          ? "border-accent bg-[rgba(69,59,231,0.12)]"
                          : "border-border bg-secondary-background hover:bg-button-bg",
                      ].join(" ")}
                      onClick={() => setSelectedScriptKey(item.draftKey)}
                    >
                      <div className="flex items-center justify-between gap-2">
                        <div className="truncate text-[13px] font-semibold text-text">
                          {item.name || item.id || "未命名脚本"}
                        </div>
                        <div className="rounded-full border border-border bg-card-bg px-2 py-0.5 text-[11px] text-secondary-text">
                          {item.params.length} 参数
                        </div>
                      </div>
                      <div className="mt-1 truncate text-fs-caption text-secondary-text">
                        ID：{item.id || "--"}
                      </div>
                      <div className="mt-0.5 truncate text-fs-caption text-secondary-text">
                        {item.path || "未设置脚本路径"}
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          {!selectedScriptVisible ? (
            <div className="mt-2 rounded-lg border border-warning/40 bg-[rgba(245,158,11,0.12)] px-3 py-2 text-fs-caption text-warning">
              当前选中脚本被搜索条件隐藏。
              <button className="ml-1 underline" onClick={() => setScriptFilter("")}>
                清空搜索
              </button>
            </div>
          ) : null}
        </aside>

        <div className="flex min-h-[520px] flex-col gap-3">
          {!selectedScript ? (
            <section className="flex min-h-[520px] items-center justify-center rounded-xl border border-dashed border-border bg-card-bg px-4 py-6 text-center">
              <div>
                <div className="text-[14px] font-semibold text-text">请选择脚本开始编辑</div>
                <div className="mt-1 text-fs-caption text-secondary-text">
                  可以先从左侧选择已有脚本，或点击“新增脚本”。
                </div>
              </div>
            </section>
          ) : (
            <>
              <section className="rounded-xl border border-border bg-card-bg p-3">
                <div className="mb-3 flex items-center gap-2 text-[13px] font-semibold text-text">
                  <IconCode size={14} />
                  脚本定义
                </div>
                <div className="grid gap-2 md:grid-cols-2">
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>ID</span>
                    <input
                      className={`${LOCKED_INPUT_CLASS} font-mono`}
                      value={selectedScript.id}
                      readOnly
                      aria-readonly="true"
                      title="该字段创建后锁定"
                    />
                  </label>
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>脚本相对路径</span>
                    <input
                      className={`${LOCKED_INPUT_CLASS} font-mono`}
                      value={selectedScript.path}
                      readOnly
                      aria-readonly="true"
                      title="该字段创建后锁定"
                    />
                  </label>
                </div>

                <div className="mt-2 grid gap-2 md:grid-cols-[minmax(200px,1fr)_minmax(320px,1.4fr)]">
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>名称</span>
                    <input
                      className={INPUT_CLASS}
                      value={selectedScript.name}
                      onChange={(event) => patchSelectedScript({ name: event.target.value })}
                      placeholder="例如 Jenkins 部署"
                    />
                  </label>

                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>命令模板</span>
                    <textarea
                      className={`${TEXTAREA_CLASS} min-h-[84px]`}
                      value={selectedScript.commandTemplate}
                      onChange={(event) => patchSelectedScript({ commandTemplate: event.target.value })}
                      placeholder={`例如 ${DEFAULT_COMMAND_TEMPLATE}`}
                    />
                  </label>
                </div>
              </section>

              <section className="rounded-xl border border-border bg-card-bg p-3">
                <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
                  <div className="text-[13px] font-semibold text-text">参数定义</div>
                  <button
                    className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                    onClick={() =>
                      patchSelectedScript({
                        params: [...selectedScript.params, createEmptyParamField(selectedScript.params.length + 1)],
                      })
                    }
                  >
                    添加参数
                  </button>
                </div>
                {selectedScript.params.length === 0 ? (
                  <div className="rounded-lg border border-dashed border-border bg-secondary-background px-3 py-3 text-fs-caption text-secondary-text">
                    当前没有参数。模板中使用 `${"{host}"}` 等占位符时建议定义参数。
                  </div>
                ) : (
                  <div className="flex flex-col gap-2">
                    {selectedScript.params.map((param, index) => (
                      <ParameterEditor
                        key={`${param.key || "param"}-${index}`}
                        index={index + 1}
                        value={param}
                        onChange={(nextParam) => {
                          const nextParams = [...selectedScript.params];
                          nextParams[index] = nextParam;
                          patchSelectedScript({ params: nextParams });
                        }}
                        onRemove={() => {
                          const nextParams = selectedScript.params.filter((_, itemIndex) => itemIndex !== index);
                          patchSelectedScript({ params: nextParams });
                        }}
                      />
                    ))}
                  </div>
                )}
              </section>

              <section className="rounded-xl border border-border bg-card-bg p-3">
                <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
                  <div className="flex items-center gap-2 text-[13px] font-semibold text-text">
                    <IconFile size={14} />
                    脚本文件内容
                  </div>
                  {scriptContentPath ? (
                    <span className="rounded-full border border-border bg-secondary-background px-2 py-0.5 font-mono text-[11px] text-secondary-text">
                      {scriptContentPath}
                    </span>
                  ) : null}
                </div>

                {isLoadingScriptContent ? (
                  <div className="rounded-lg border border-border bg-secondary-background px-3 py-3 text-fs-caption text-secondary-text">
                    加载脚本内容中...
                  </div>
                ) : (
                  <textarea
                    className={`${TEXTAREA_CLASS} min-h-[220px] font-mono text-[12px] leading-relaxed`}
                    value={scriptContent}
                    onChange={(event) => {
                      setScriptContent(event.target.value);
                      setScriptContentMessage(null);
                      setScriptContentError(null);
                    }}
                    placeholder="#!/usr/bin/env bash"
                  />
                )}

                <div className="mt-2 flex flex-wrap items-center justify-between gap-2">
                  <div className="text-fs-caption text-secondary-text" role="status" aria-live="polite">
                    {isScriptContentDirty ? "脚本内容有变更，保存后写入文件。" : "脚本内容与磁盘文件一致。"}
                  </div>
                  <button
                    className={`btn btn-primary min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                    onClick={() => void handleSaveScriptContent()}
                    disabled={
                      isLoadingScriptContent ||
                      isSavingScriptContent ||
                      !selectedScript.path.trim() ||
                      !isScriptContentDirty
                    }
                  >
                    {isSavingScriptContent ? "保存中..." : "保存脚本文件"}
                  </button>
                </div>

                {scriptContentError ? (
                  <div className="mt-2 text-fs-caption text-error">{scriptContentError}</div>
                ) : null}
                {scriptContentMessage ? (
                  <div className="mt-2 text-fs-caption text-success">{scriptContentMessage}</div>
                ) : null}
              </section>
            </>
          )}
        </div>
      </section>

      <footer className="rounded-xl border border-border bg-card-bg px-3 py-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <button
              className={`btn btn-danger min-h-[40px] gap-1.5 ${BUTTON_FOCUS_RING_CLASS}`}
              onClick={handleRemoveSelectedScript}
              disabled={!selectedScript}
            >
              <IconTrash size={14} />
              删除当前脚本
            </button>
            <button
              className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
              onClick={() => void handleRestorePresets()}
              disabled={isRestoringPresets}
            >
              {isRestoringPresets ? "恢复中..." : "恢复内置预设"}
            </button>
          </div>

          <div className="flex flex-wrap items-center gap-2">
            {!inline && onClose ? (
              <button className={`btn min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`} onClick={onClose}>
                关闭
              </button>
            ) : null}
            <div className="rounded-md border border-border bg-secondary-background px-2.5 py-2 text-fs-caption text-secondary-text">
              {isSavingManifest
                ? "正在自动保存清单..."
                : isManifestDirty
                  ? "已检测到变更，稍后自动保存。"
                  : "清单自动保存已开启。"}
            </div>
          </div>
        </div>

        {manifestError ? <div className="mt-2 text-fs-caption text-error">{manifestError}</div> : null}
        {manifestMessage ? <div className="mt-2 text-fs-caption text-success">{manifestMessage}</div> : null}
      </footer>
    </div>
  );

  const createScriptDialogView = createScriptDialog ? (
    <div className="modal-overlay" role="dialog" aria-modal>
      <div className="modal-panel w-[min(560px,92vw)]">
        <div className="text-[16px] font-semibold text-text">新增通用脚本</div>

        <div className="mt-3 grid gap-2">
          <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
            <span>脚本相对路径</span>
            <input
              className={INPUT_CLASS}
              value={createScriptDialog.path}
              onChange={(event) =>
                setCreateScriptDialog((prev) => {
                  if (!prev) {
                    return prev;
                  }
                  const nextPath = event.target.value;
                  return {
                    ...prev,
                    path: nextPath,
                    id: prev.usePathAsId ? nextPath : prev.id,
                    error: null,
                  };
                })
              }
              placeholder="例如 ops/jenkins-deploy.sh"
            />
          </label>

          <label className="inline-flex items-center gap-2 text-[13px] text-secondary-text">
            <input
              className="h-4 w-4 rounded border border-border bg-card-bg accent-accent"
              type="checkbox"
              checked={createScriptDialog.usePathAsId}
              onChange={(event) =>
                setCreateScriptDialog((prev) => {
                  if (!prev) {
                    return prev;
                  }
                  const checked = event.target.checked;
                  return {
                    ...prev,
                    usePathAsId: checked,
                    id: checked ? prev.path : prev.id,
                    error: null,
                  };
                })
              }
            />
            ID 使用路径（推荐）
          </label>

          <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
            <span>脚本 ID</span>
            <input
              className={createScriptDialog.usePathAsId ? `${LOCKED_INPUT_CLASS} font-mono` : INPUT_CLASS}
              value={createScriptDialog.usePathAsId ? createScriptDialog.path : createScriptDialog.id}
              onChange={(event) =>
                setCreateScriptDialog((prev) => (prev ? { ...prev, id: event.target.value, error: null } : prev))
              }
              placeholder="唯一标识，例如 jenkins-deploy"
              disabled={createScriptDialog.usePathAsId}
            />
          </label>

          <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
            <span>名称（可选）</span>
            <input
              className={INPUT_CLASS}
              value={createScriptDialog.name}
              onChange={(event) =>
                setCreateScriptDialog((prev) => (prev ? { ...prev, name: event.target.value, error: null } : prev))
              }
              placeholder="不填则按路径自动生成"
            />
          </label>
        </div>

        {createScriptDialog.error ? (
          <div className="mt-2 text-fs-caption text-error">{createScriptDialog.error}</div>
        ) : null}

        <div className="mt-4 flex items-center justify-end gap-2">
          <button
            className={`btn min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
            onClick={() => setCreateScriptDialog(null)}
          >
            取消
          </button>
          <button
            className={`btn btn-primary min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
            onClick={handleConfirmCreateScript}
          >
            创建脚本
          </button>
        </div>
      </div>
    </div>
  ) : null;

  if (inline) {
    return (
      <>
        {panel}
        {createScriptDialogView}
      </>
    );
  }

  return (
    <>
      <div className="modal-overlay" role="dialog" aria-modal>
        {panel}
      </div>
      {createScriptDialogView}
    </>
  );
}

type ParameterEditorProps = {
  index: number;
  value: ScriptParamField;
  onChange: (value: ScriptParamField) => void;
  onRemove: () => void;
};

function ParameterEditor({ index, value, onChange, onRemove }: ParameterEditorProps) {
  return (
    <div className="rounded-lg border border-border bg-secondary-background p-3">
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        <div className="text-fs-caption text-secondary-text">参数 {index}</div>
        <button className={`btn btn-outline min-h-[36px] ${BUTTON_FOCUS_RING_CLASS}`} onClick={onRemove}>
          删除参数
        </button>
      </div>

      <div className="grid gap-2 md:grid-cols-2">
        <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
          <span>参数 key</span>
          <input
            className={INPUT_CLASS}
            value={value.key}
            onChange={(event) => onChange({ ...value, key: event.target.value })}
            placeholder="例如 host"
          />
        </label>

        <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
          <span>显示名</span>
          <input
            className={INPUT_CLASS}
            value={value.label}
            onChange={(event) => onChange({ ...value, label: event.target.value })}
            placeholder="例如 主机地址"
          />
        </label>
      </div>

      <div className="mt-2 grid gap-2 md:grid-cols-[140px_minmax(0,1fr)]">
        <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
          <span>类型</span>
          <select
            className={INPUT_CLASS}
            value={value.type}
            onChange={(event) => onChange({ ...value, type: normalizeParamType(event.target.value) })}
          >
            <option value="text">text</option>
            <option value="number">number</option>
            <option value="secret">secret</option>
          </select>
        </label>

        <label className="flex flex-col gap-1 text-[12px] text-secondary-text">
          <span>默认值（可选）</span>
          <input
            className={INPUT_CLASS}
            value={value.defaultValue ?? ""}
            onChange={(event) => onChange({ ...value, defaultValue: event.target.value || undefined })}
            placeholder="可选"
          />
        </label>
      </div>

      <label className="mt-2 inline-flex items-center gap-2 text-[12px] text-secondary-text">
        <input
          className="h-4 w-4 rounded border border-border bg-card-bg accent-accent"
          type="checkbox"
          checked={Boolean(value.required)}
          onChange={(event) => onChange({ ...value, required: event.target.checked })}
        />
        必填参数
      </label>

      <label className="mt-2 flex flex-col gap-1 text-[12px] text-secondary-text">
        <span>参数说明（可选）</span>
        <input
          className={INPUT_CLASS}
          value={value.description ?? ""}
          onChange={(event) => onChange({ ...value, description: event.target.value || undefined })}
          placeholder="用于提示使用者如何填写"
        />
      </label>
    </div>
  );
}

type StatusPillProps = {
  label: string;
  value: string;
  tone: "neutral" | "accent";
};

function StatusPill({ label, value, tone }: StatusPillProps) {
  return (
    <div
      className={[
        "rounded-lg border px-3 py-2",
        tone === "accent"
          ? "border-accent bg-[rgba(69,59,231,0.15)]"
          : "border-border bg-secondary-background",
      ].join(" ")}
    >
      <div className="text-[11px] uppercase tracking-wide text-secondary-text">{label}</div>
      <div className="mt-1 text-[13px] font-semibold text-text">{value}</div>
    </div>
  );
}

function mapSharedEntryToScriptDraft(entry: SharedScriptEntry, draftKey: string): SharedScriptDraft {
  return {
    draftKey,
    id: entry.id,
    name: entry.name,
    path: entry.relativePath,
    commandTemplate: entry.commandTemplate || DEFAULT_COMMAND_TEMPLATE,
    params: entry.params ?? [],
  };
}

function toManifestScript(script: SharedScriptDraft): SharedScriptManifestScript {
  return {
    id: script.id,
    name: script.name,
    path: script.path,
    commandTemplate: script.commandTemplate,
    params: script.params,
  };
}

function createEmptyCreateScriptDialogState(): CreateScriptDialogState {
  return {
    id: "",
    name: "",
    path: "",
    usePathAsId: true,
    error: null,
  };
}

function createEmptyParamField(index: number): ScriptParamField {
  return {
    key: `param${index}`,
    label: `参数 ${index}`,
    type: "text",
    required: false,
  };
}

function validateScripts(scripts: SharedScriptManifestScript[]): string | null {
  const usedIds = new Set<string>();
  const usedPaths = new Set<string>();
  for (const script of scripts) {
    const id = script.id.trim();
    if (!id) {
      return "脚本 ID 不能为空";
    }
    if (usedIds.has(id)) {
      return `脚本 ID 重复：${id}`;
    }
    usedIds.add(id);

    const path = script.path.trim();
    if (!path) {
      return `脚本 ${id} 缺少相对路径`;
    }
    const normalizedPath = normalizeRelativePath(path);
    if (!isSafeRelativePath(normalizedPath)) {
      return `脚本 ${id} 的相对路径不合法：${normalizedPath}`;
    }
    if (usedPaths.has(normalizedPath)) {
      return `脚本路径重复：${normalizedPath}`;
    }
    usedPaths.add(normalizedPath);
    for (const param of script.params ?? []) {
      if (!param.key?.trim()) {
        return `脚本 ${id} 存在空参数 key`;
      }
    }
  }
  return null;
}

function deriveScriptName(path: string): string {
  const normalizedPath = normalizeRelativePath(path);
  const segments = normalizedPath.split("/").filter(Boolean);
  const fileName = segments[segments.length - 1] ?? normalizedPath;
  const stem = fileName.replace(/\.[^.]+$/, "").trim();
  return stem || fileName;
}

function normalizeRelativePath(path: string): string {
  return path.replace(/\\/g, "/").trim();
}

function isSafeRelativePath(path: string): boolean {
  const normalized = normalizeRelativePath(path);
  if (!normalized || normalized.startsWith("/") || normalized.startsWith("~")) {
    return false;
  }
  const segments = normalized.split("/").filter(Boolean);
  return segments.length > 0 && !segments.some((segment) => segment === "." || segment === "..");
}

function normalizeParamType(type: string): ScriptParamFieldType {
  if (type === "number" || type === "secret") {
    return type;
  }
  return "text";
}

function serializeManifestScripts(scripts: SharedScriptManifestScript[]): string {
  return JSON.stringify(scripts);
}
