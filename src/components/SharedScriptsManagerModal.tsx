import { useEffect, useMemo, useRef, useState } from "react";

import type {
  ScriptParamField,
  ScriptParamFieldType,
  SharedScriptEntry,
  SharedScriptManifestScript,
} from "../models/types";
import {
  listSharedScripts,
  readSharedScriptFile,
  saveSharedScriptsManifest,
  writeSharedScriptFile,
} from "../services/sharedScripts";
import { IconX } from "./Icons";

type SharedScriptsManagerModalProps = {
  root: string;
  onClose?: () => void;
  inline?: boolean;
};

const DEFAULT_COMMAND_TEMPLATE = 'bash "${scriptPath}"';

type SharedScriptDraft = SharedScriptManifestScript & {
  draftKey: string;
};

/** 通用脚本可视化管理（支持弹窗/内嵌两种模式）。 */
export default function SharedScriptsManagerModal({
  root,
  onClose,
  inline = false,
}: SharedScriptsManagerModalProps) {
  const [scripts, setScripts] = useState<SharedScriptDraft[]>([]);
  const [selectedScriptKey, setSelectedScriptKey] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [isSavingManifest, setIsSavingManifest] = useState(false);
  const [manifestError, setManifestError] = useState<string | null>(null);
  const [manifestMessage, setManifestMessage] = useState<string | null>(null);
  const draftKeyRef = useRef(0);

  const [scriptContent, setScriptContent] = useState("");
  const [scriptContentPath, setScriptContentPath] = useState<string | null>(null);
  const [isLoadingScriptContent, setIsLoadingScriptContent] = useState(false);
  const [isSavingScriptContent, setIsSavingScriptContent] = useState(false);
  const [scriptContentMessage, setScriptContentMessage] = useState<string | null>(null);
  const [scriptContentError, setScriptContentError] = useState<string | null>(null);

  const nextDraftKey = () => {
    draftKeyRef.current += 1;
    return `shared-script-${draftKeyRef.current}-${Date.now().toString(36)}`;
  };

  const selectedScript = useMemo(
    () => scripts.find((item) => item.draftKey === selectedScriptKey) ?? null,
    [scripts, selectedScriptKey],
  );

  const manifestScripts = useMemo(() => scripts.map(toManifestScript), [scripts]);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    setManifestError(null);
    setManifestMessage(null);
    void listSharedScripts(root)
      .then((entries) => {
        if (cancelled) {
          return;
        }
        const normalized = entries.map((entry) => mapSharedEntryToScriptDraft(entry, nextDraftKey()));
        setScripts(normalized);
        setSelectedScriptKey(normalized[0]?.draftKey ?? null);
      })
      .catch((error) => {
        if (cancelled) {
          return;
        }
        setScripts([]);
        setSelectedScriptKey(null);
        setManifestError(error instanceof Error ? error.message : "加载通用脚本失败");
      })
      .finally(() => {
        if (cancelled) {
          return;
        }
        setIsLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [root]);

  useEffect(() => {
    if (!selectedScript || !selectedScript.path.trim()) {
      setScriptContent("");
      setScriptContentPath(null);
      setScriptContentError(null);
      setScriptContentMessage(null);
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
        setScriptContentPath(relativePath);
      })
      .catch(() => {
        if (cancelled) {
          return;
        }
        setScriptContent("");
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
    const draft = createEmptyScriptDraft(scripts.length + 1, nextDraftKey());
    setScripts((prev) => [...prev, draft]);
    setSelectedScriptKey(draft.draftKey);
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

  const handleSaveManifest = async () => {
    const validationError = validateScripts(manifestScripts);
    if (validationError) {
      setManifestError(validationError);
      return;
    }
    setManifestError(null);
    setManifestMessage(null);
    setIsSavingManifest(true);
    try {
      await saveSharedScriptsManifest(manifestScripts, root);
      setManifestMessage("通用脚本清单已保存。");
    } catch (error) {
      setManifestError(error instanceof Error ? error.message : "保存通用脚本清单失败");
    } finally {
      setIsSavingManifest(false);
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
    setScriptContentError(null);
    setScriptContentMessage(null);
    setIsSavingScriptContent(true);
    try {
      await writeSharedScriptFile(relativePath, scriptContent, root);
      setScriptContentPath(relativePath);
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
          : "modal-panel min-w-[900px] w-[min(1120px,96vw)] max-h-[92vh] overflow-y-auto"
      }
    >
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="text-[16px] font-semibold">通用脚本管理</div>
          <div className="text-fs-caption text-secondary-text">目录：{root}</div>
        </div>
        {!inline && onClose ? (
          <button className="icon-btn" onClick={onClose} aria-label="关闭">
            <IconX size={14} />
          </button>
        ) : null}
      </div>
      <section className="grid gap-3 md:grid-cols-[280px_minmax(0,1fr)]">
        <div className="rounded-xl border border-border bg-card-bg p-3">
          <div className="mb-2 flex items-center justify-between gap-2">
            <div className="text-[13px] font-semibold">脚本列表</div>
            <button className="btn btn-outline" onClick={handleAddScript} disabled={isLoading}>
              新增
            </button>
          </div>
          {isLoading ? (
            <div className="text-fs-caption text-secondary-text">加载中...</div>
          ) : scripts.length === 0 ? (
            <div className="text-fs-caption text-secondary-text">暂无脚本，点击“新增”创建。</div>
          ) : (
            <div className="flex max-h-[380px] flex-col gap-1 overflow-y-auto">
              {scripts.map((item) => (
                <button
                  key={item.draftKey}
                  className={`text-left rounded-md border px-2.5 py-2 ${
                    item.draftKey === selectedScriptKey
                      ? "border-accent bg-[rgba(69,59,231,0.08)]"
                      : "border-border bg-card-bg hover:bg-secondary-background"
                  }`}
                  onClick={() => setSelectedScriptKey(item.draftKey)}
                >
                  <div className="truncate text-[13px] font-semibold">{item.name || item.id}</div>
                  <div className="truncate text-fs-caption text-secondary-text">{item.path || "--"}</div>
                </button>
              ))}
            </div>
          )}
          {manifestError ? <div className="mt-2 text-fs-caption text-error">{manifestError}</div> : null}
          {manifestMessage ? <div className="mt-2 text-fs-caption text-success">{manifestMessage}</div> : null}
        </div>

          <div className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
            {!selectedScript ? (
              <div className="text-fs-caption text-secondary-text">请选择或新增一个脚本。</div>
            ) : (
              <>
                <div className="grid gap-2 md:grid-cols-2">
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>ID</span>
                    <input
                      className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                      value={selectedScript.id}
                      onChange={(event) => patchSelectedScript({ id: event.target.value })}
                      placeholder="唯一标识，例如 jenkins-deploy"
                    />
                  </label>
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                    <span>名称</span>
                    <input
                      className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                      value={selectedScript.name}
                      onChange={(event) => patchSelectedScript({ name: event.target.value })}
                      placeholder="例如 Jenkins 部署"
                    />
                  </label>
                </div>

                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                  <span>脚本相对路径</span>
                  <input
                    className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                    value={selectedScript.path}
                    onChange={(event) => patchSelectedScript({ path: event.target.value })}
                    placeholder="例如 ops/jenkins-deploy.sh"
                  />
                </label>

                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text">
                  <span>命令模板</span>
                  <textarea
                    className="min-h-[84px] resize-y rounded-md border border-border bg-card-bg px-2 py-2 text-text"
                    value={selectedScript.commandTemplate}
                    onChange={(event) => patchSelectedScript({ commandTemplate: event.target.value })}
                    placeholder={`例如 ${DEFAULT_COMMAND_TEMPLATE}`}
                  />
                </label>

                <section className="rounded-md border border-border bg-secondary-background p-2.5">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <div className="text-[13px] font-semibold text-text">参数</div>
                    <button
                      className="btn btn-outline"
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
                    <div className="text-fs-caption text-secondary-text">
                      当前没有参数。模板里使用 `${"{host}"}` 等占位符时建议在此定义。
                    </div>
                  ) : (
                    <div className="flex flex-col gap-2">
                      {selectedScript.params.map((param, index) => (
                        <ParameterEditor
                          key={`${param.key || "param"}-${index}`}
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

                <section className="rounded-md border border-border bg-secondary-background p-2.5">
                  <div className="mb-2 text-[13px] font-semibold text-text">脚本内容</div>
                  {isLoadingScriptContent ? (
                    <div className="text-fs-caption text-secondary-text">加载脚本内容中...</div>
                  ) : (
                    <textarea
                      className="min-h-[210px] w-full resize-y rounded-md border border-border bg-card-bg px-2 py-2 font-mono text-[12px] leading-relaxed text-text"
                      value={scriptContent}
                      onChange={(event) => setScriptContent(event.target.value)}
                      placeholder="#!/usr/bin/env bash"
                    />
                  )}
                  <div className="mt-2 flex flex-wrap items-center gap-2">
                    <button
                      className="btn btn-primary"
                      onClick={() => void handleSaveScriptContent()}
                      disabled={isLoadingScriptContent || isSavingScriptContent}
                    >
                      {isSavingScriptContent ? "保存中..." : "保存脚本文件"}
                    </button>
                    {scriptContentPath ? (
                      <span className="text-fs-caption text-secondary-text">当前文件：{scriptContentPath}</span>
                    ) : null}
                  </div>
                  {scriptContentError ? (
                    <div className="mt-1 text-fs-caption text-error">{scriptContentError}</div>
                  ) : null}
                  {scriptContentMessage ? (
                    <div className="mt-1 text-fs-caption text-success">{scriptContentMessage}</div>
                  ) : null}
                </section>
              </>
            )}
          </div>
        </section>

      <div className="flex justify-between gap-2">
        <button
          className="btn btn-outline"
          onClick={handleRemoveSelectedScript}
          disabled={!selectedScript}
        >
          删除当前脚本
        </button>
        <div className="flex gap-2">
          {!inline && onClose ? (
            <button className="btn" onClick={onClose}>
              关闭
            </button>
          ) : null}
          <button
            className="btn btn-primary"
            onClick={() => void handleSaveManifest()}
            disabled={isSavingManifest}
          >
            {isSavingManifest ? "保存中..." : "保存清单"}
          </button>
        </div>
      </div>
    </div>
  );

  if (inline) {
    return panel;
  }

  return (
    <div className="modal-overlay" role="dialog" aria-modal>
      {panel}
    </div>
  );
}

type ParameterEditorProps = {
  value: ScriptParamField;
  onChange: (value: ScriptParamField) => void;
  onRemove: () => void;
};

function ParameterEditor({ value, onChange, onRemove }: ParameterEditorProps) {
  return (
    <div className="grid gap-2 rounded-md border border-border bg-card-bg p-2 md:grid-cols-[1fr_1fr_120px_auto]">
      <input
        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
        value={value.key}
        onChange={(event) => onChange({ ...value, key: event.target.value })}
        placeholder="参数 key"
      />
      <input
        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
        value={value.label}
        onChange={(event) => onChange({ ...value, label: event.target.value })}
        placeholder="显示名"
      />
      <select
        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text"
        value={value.type}
        onChange={(event) => onChange({ ...value, type: normalizeParamType(event.target.value) })}
      >
        <option value="text">text</option>
        <option value="number">number</option>
        <option value="secret">secret</option>
      </select>
      <button className="btn btn-outline whitespace-nowrap" onClick={onRemove}>
        删除
      </button>
      <input
        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text md:col-span-2"
        value={value.defaultValue ?? ""}
        onChange={(event) => onChange({ ...value, defaultValue: event.target.value || undefined })}
        placeholder="默认值（可选）"
      />
      <label className="flex items-center gap-2 text-[12px] text-secondary-text md:col-span-2">
        <input
          className="h-3.5 w-3.5"
          type="checkbox"
          checked={Boolean(value.required)}
          onChange={(event) => onChange({ ...value, required: event.target.checked })}
        />
        必填参数
      </label>
      <input
        className="rounded-md border border-border bg-card-bg px-2 py-2 text-text md:col-span-4"
        value={value.description ?? ""}
        onChange={(event) => onChange({ ...value, description: event.target.value || undefined })}
        placeholder="参数说明（可选）"
      />
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

function createEmptyScriptDraft(index: number, draftKey: string): SharedScriptDraft {
  return {
    draftKey,
    id: `shared-script-${index}-${draftKey}`,
    name: "",
    path: "",
    commandTemplate: DEFAULT_COMMAND_TEMPLATE,
    params: [],
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
    if (!isSafeRelativePath(path)) {
      return `脚本 ${id} 的相对路径不合法：${path}`;
    }
    for (const param of script.params ?? []) {
      if (!param.key?.trim()) {
        return `脚本 ${id} 存在空参数 key`;
      }
    }
  }
  return null;
}

function isSafeRelativePath(path: string): boolean {
  const normalized = path.replace(/\\/g, "/").trim();
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
