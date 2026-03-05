import { useEffect, useId, useMemo, useState, type ReactNode } from "react";

import type { AppSettings, GitIdentity } from "../models/types";
import {
  getAppVersionRuntime,
  getHomeDirRuntime,
  openUrlRuntime,
} from "../platform/runtime";
import { openInFinder } from "../services/system";
import { checkForUpdates } from "../services/update";
import {
  TERMINAL_THEME_PRESETS,
  getTerminalThemePresetByName,
  parseTerminalThemeSetting,
} from "../themes/terminalThemes";
import { normalizeGitIdentities } from "../utils/gitIdentity";
import { IconMaximize2, IconMinimize2, IconX } from "./Icons";
import SharedScriptsManagerModal from "./SharedScriptsManagerModal";

type UpdateState =
  | { status: "idle" }
  | { status: "checking" }
  | { status: "latest"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "update"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "error"; message: string; currentVersion?: string };

const DEFAULT_SHARED_SCRIPTS_ROOT = "~/.devhaven/scripts";
const DEFAULT_VITE_DEV_PORT = 1420;
const BUTTON_FOCUS_RING_CLASS =
  "focus-visible:outline focus-visible:outline-2 focus-visible:outline-accent focus-visible:outline-offset-2";
const INPUT_CLASS =
  "w-full rounded-md border border-border bg-card-bg px-3 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]";

type SettingsCategoryId = "general" | "terminal" | "scripts" | "workflow";

type SettingsCategory = {
  id: SettingsCategoryId;
  label: string;
  description: string;
};

const SETTINGS_CATEGORIES: SettingsCategory[] = [
  { id: "general", label: "常规", description: "应用更新、版本与浏览器访问配置。" },
  { id: "terminal", label: "终端", description: "终端渲染与主题显示设置。" },
  { id: "scripts", label: "脚本", description: "管理通用脚本清单、参数与脚本文件。" },
  { id: "workflow", label: "协作", description: "Git 身份与提交配置。" },
];

const isSameIdentities = (left: GitIdentity[], right: GitIdentity[]) => {
  if (left.length !== right.length) {
    return false;
  }
  return left.every((item, index) => item.name === right[index].name && item.email === right[index].email);
};

function canonicalizeTerminalThemeSetting(setting: string | null | undefined): string {
  const parsed = parseTerminalThemeSetting(setting);
  if (parsed.kind === "system") {
    const light = getTerminalThemePresetByName(parsed.light).name;
    const dark = getTerminalThemePresetByName(parsed.dark).name;
    return `light:${light},dark:${dark}`;
  }
  return getTerminalThemePresetByName(parsed.name).name;
}

function normalizeViteDevPort(port: number | string | null | undefined): number {
  const candidate =
    typeof port === "number"
      ? port
      : typeof port === "string"
        ? Number.parseInt(port.trim(), 10)
        : Number.NaN;
  if (!Number.isInteger(candidate) || candidate < 1 || candidate > 65535) {
    return DEFAULT_VITE_DEV_PORT;
  }
  return candidate;
}

export type SettingsModalProps = {
  settings: AppSettings;
  onClose: () => void;
  onSaveSettings: (settings: AppSettings) => Promise<void>;
};

/** 设置弹窗，左侧分类、右侧内容，统一承载更新、终端与协作设置项。 */
export default function SettingsModal({
  settings,
  onClose,
  onSaveSettings,
}: SettingsModalProps) {
  const [gitIdentities, setGitIdentities] = useState<GitIdentity[]>(settings.gitIdentities);
  const [terminalUseWebglRenderer, setTerminalUseWebglRenderer] = useState(
    settings.terminalUseWebglRenderer,
  );
  const [terminalFollowSystem, setTerminalFollowSystem] = useState(false);
  const [terminalSingleTheme, setTerminalSingleTheme] = useState(() =>
    getTerminalThemePresetByName(settings.terminalTheme).name,
  );
  const [terminalLightTheme, setTerminalLightTheme] = useState("iTerm2 Solarized Light");
  const [terminalDarkTheme, setTerminalDarkTheme] = useState("iTerm2 Solarized Dark");
  const [versionLabel, setVersionLabel] = useState("");
  const [updateState, setUpdateState] = useState<UpdateState>({ status: "idle" });
  const [viteDevPortInput, setViteDevPortInput] = useState(() => String(settings.viteDevPort));
  const [isSaving, setIsSaving] = useState(false);
  const [isExpanded, setIsExpanded] = useState(false);
  const [activeCategoryId, setActiveCategoryId] = useState<SettingsCategoryId>("general");
  const dialogTitleId = useId();
  const terminalSingleThemeSelectId = useId();
  const terminalLightThemeSelectId = useId();
  const terminalDarkThemeSelectId = useId();

  const normalizedGitIdentities = useMemo(() => normalizeGitIdentities(gitIdentities), [gitIdentities]);
  const terminalThemeSetting = useMemo(() => {
    if (terminalFollowSystem) {
      const light = getTerminalThemePresetByName(terminalLightTheme).name;
      const dark = getTerminalThemePresetByName(terminalDarkTheme).name;
      return `light:${light},dark:${dark}`;
    }
    return getTerminalThemePresetByName(terminalSingleTheme).name;
  }, [terminalDarkTheme, terminalFollowSystem, terminalLightTheme, terminalSingleTheme]);

  const terminalThemeOptions = useMemo(() => TERMINAL_THEME_PRESETS.map((preset) => preset.name), []);
  const sharedScriptsRoot = useMemo(
    () => settings.sharedScriptsRoot?.trim() || DEFAULT_SHARED_SCRIPTS_ROOT,
    [settings.sharedScriptsRoot],
  );
  const normalizedViteDevPort = useMemo(() => normalizeViteDevPort(viteDevPortInput), [viteDevPortInput]);
  const nextSettings = useMemo<AppSettings>(
    () => ({
      ...settings,
      terminalUseWebglRenderer,
      terminalTheme: terminalThemeSetting,
      gitIdentities: normalizedGitIdentities,
      sharedScriptsRoot,
      viteDevPort: normalizedViteDevPort,
    }),
    [
      normalizedGitIdentities,
      settings,
      terminalThemeSetting,
      terminalUseWebglRenderer,
      sharedScriptsRoot,
      normalizedViteDevPort,
    ],
  );
  const isDirty = useMemo(() => {
    const normalizedStoredIdentities = normalizeGitIdentities(settings.gitIdentities);
    return !(
      isSameIdentities(nextSettings.gitIdentities, normalizedStoredIdentities) &&
      nextSettings.terminalUseWebglRenderer === settings.terminalUseWebglRenderer &&
      canonicalizeTerminalThemeSetting(nextSettings.terminalTheme) ===
        canonicalizeTerminalThemeSetting(settings.terminalTheme) &&
      nextSettings.sharedScriptsRoot ===
        (settings.sharedScriptsRoot?.trim() || DEFAULT_SHARED_SCRIPTS_ROOT) &&
      nextSettings.viteDevPort === normalizeViteDevPort(settings.viteDevPort)
    );
  }, [nextSettings, settings]);

  useEffect(() => {
    setGitIdentities(settings.gitIdentities);
    setTerminalUseWebglRenderer(settings.terminalUseWebglRenderer);
    const parsedTerminalTheme = parseTerminalThemeSetting(settings.terminalTheme);
    if (parsedTerminalTheme.kind === "system") {
      setTerminalFollowSystem(true);
      setTerminalLightTheme(getTerminalThemePresetByName(parsedTerminalTheme.light).name);
      setTerminalDarkTheme(getTerminalThemePresetByName(parsedTerminalTheme.dark).name);
    } else {
      setTerminalFollowSystem(false);
      setTerminalSingleTheme(getTerminalThemePresetByName(parsedTerminalTheme.name).name);
    }
    setViteDevPortInput(String(settings.viteDevPort));
  }, [
    settings.gitIdentities,
    settings.terminalUseWebglRenderer,
    settings.terminalTheme,
    settings.viteDevPort,
  ]);

  const handleAddGitIdentity = () => {
    setGitIdentities((prev) => [...prev, { name: "", email: "" }]);
  };

  const handleUpdateGitIdentity = (index: number, field: "name" | "email", value: string) => {
    setGitIdentities((prev) =>
      prev.map((item, currentIndex) =>
        currentIndex === index ? { ...item, [field]: value } : item,
      ),
    );
  };

  const handleRemoveGitIdentity = (index: number) => {
    setGitIdentities((prev) => prev.filter((_, currentIndex) => currentIndex !== index));
  };

  const handleToggleTerminalWebgl = (enabled: boolean) => {
    setTerminalUseWebglRenderer(enabled);
  };

  const handleToggleTerminalFollowSystem = (enabled: boolean) => {
    setTerminalFollowSystem(enabled);
  };

  useEffect(() => {
    let active = true;
    getAppVersionRuntime()
      .then((version) => {
        if (active) {
          setVersionLabel(version);
        }
      })
      .catch(() => {
        if (active) {
          setVersionLabel("");
        }
      });
    return () => {
      active = false;
    };
  }, []);

  const handleClose = async () => {
    if (isSaving) {
      return;
    }
    if (isDirty) {
      setIsSaving(true);
      try {
        await onSaveSettings(nextSettings);
      } finally {
        setIsSaving(false);
      }
    }
    onClose();
  };

  const handleCheckUpdate = async () => {
    if (updateState.status === "checking") {
      return;
    }
    setUpdateState({ status: "checking" });
    const result = await checkForUpdates();
    if (result.status === "error") {
      setUpdateState({ status: "error", message: result.message, currentVersion: result.currentVersion });
      return;
    }
    if (result.status === "update") {
      setUpdateState({
        status: "update",
        currentVersion: result.currentVersion,
        latestVersion: result.latestVersion,
        url: result.url,
      });
      return;
    }
    setUpdateState({
      status: "latest",
      currentVersion: result.currentVersion,
      latestVersion: result.latestVersion,
      url: result.url,
    });
  };

  const handleOpenRelease = async () => {
    if (updateState.status !== "update" && updateState.status !== "latest") {
      return;
    }
    if (!updateState.url) {
      return;
    }
    try {
      await openUrlRuntime(updateState.url);
    } catch (error) {
      console.error("打开发布页面失败。", error);
    }
  };

  const handleOpenSharedScriptsRoot = async () => {
    try {
      const resolvedPath = await resolveHomePath(sharedScriptsRoot);
      await openInFinder(resolvedPath);
    } catch (error) {
      console.error("打开通用脚本目录失败。", error);
    }
  };

  const activeCategory =
    SETTINGS_CATEGORIES.find((category) => category.id === activeCategoryId) || SETTINGS_CATEGORIES[0];

  const renderCategoryContent = () => {
    if (activeCategoryId === "general") {
      return (
        <div className="flex flex-col gap-3">
          <SettingsSectionCard
            title="更新与版本"
            description="检查新版本并快速跳转到发布页。"
          >
            <div className="flex flex-wrap items-center gap-2.5">
              <div className="rounded-full border border-border bg-button-bg px-2.5 py-1 text-fs-caption text-text">
                当前版本：{versionLabel || "--"}
              </div>
              <button
                className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                onClick={() => void handleCheckUpdate()}
              >
                {updateState.status === "checking" ? "检查中..." : "检查更新"}
              </button>
              {updateState.status === "update" || updateState.status === "latest" ? (
                <button
                  className={`btn min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                  onClick={() => void handleOpenRelease()}
                  disabled={!updateState.url}
                >
                  查看发布
                </button>
              ) : null}
            </div>
            <UpdateStatusLine state={updateState} />
          </SettingsSectionCard>

          <SettingsSectionCard
            title="浏览器访问端口"
            description="用于浏览器访问 DevHaven 的端口（开发态重启 dev 生效，打包后重启应用生效）。"
          >
            <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text md:max-w-[220px]">
              <span>端口</span>
              <input
                type="number"
                min={1}
                max={65535}
                className={INPUT_CLASS}
                value={viteDevPortInput}
                placeholder={String(DEFAULT_VITE_DEV_PORT)}
                onChange={(event) => setViteDevPortInput(event.target.value)}
                onBlur={() => setViteDevPortInput(String(normalizedViteDevPort))}
              />
            </label>
            <div className="text-fs-caption text-secondary-text">
              保存后会提示重启；开发态重启 dev，打包后重启应用即可生效。
            </div>
          </SettingsSectionCard>
        </div>
      );
    }

    if (activeCategoryId === "terminal") {
      return (
        <div className="flex flex-col gap-3">
          <SettingsSectionCard
            title="渲染性能"
            description="根据设备能力选择终端渲染策略。"
          >
            <SettingsToggleRow
              title="启用 WebGL 渲染"
              description="通常可提升终端滚动和高频输出场景性能。"
              checked={terminalUseWebglRenderer}
              onChange={handleToggleTerminalWebgl}
            />
          </SettingsSectionCard>

          <SettingsSectionCard
            title="主题"
            description="支持固定主题或跟随系统浅/深色。"
          >
            <div className="flex flex-col gap-3">
              <SettingsToggleRow
                title="跟随系统浅/深色"
                description="开启后可分别设置浅色与深色主题。"
                checked={terminalFollowSystem}
                onChange={handleToggleTerminalFollowSystem}
              />

              {terminalFollowSystem ? (
                <div className="grid gap-2 md:grid-cols-2">
                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text" htmlFor={terminalLightThemeSelectId}>
                    <span>浅色主题</span>
                    <select
                      id={terminalLightThemeSelectId}
                      className={INPUT_CLASS}
                      value={terminalLightTheme}
                      onChange={(event) => setTerminalLightTheme(event.target.value)}
                    >
                      {terminalThemeOptions.map((name) => (
                        <option key={`terminal-theme-light-${name}`} value={name}>
                          {name}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text" htmlFor={terminalDarkThemeSelectId}>
                    <span>深色主题</span>
                    <select
                      id={terminalDarkThemeSelectId}
                      className={INPUT_CLASS}
                      value={terminalDarkTheme}
                      onChange={(event) => setTerminalDarkTheme(event.target.value)}
                    >
                      {terminalThemeOptions.map((name) => (
                        <option key={`terminal-theme-dark-${name}`} value={name}>
                          {name}
                        </option>
                      ))}
                    </select>
                  </label>
                </div>
              ) : (
                <label className="flex flex-col gap-1.5 text-[13px] text-secondary-text" htmlFor={terminalSingleThemeSelectId}>
                  <span>终端主题</span>
                  <select
                    id={terminalSingleThemeSelectId}
                    className={INPUT_CLASS}
                    value={terminalSingleTheme}
                    onChange={(event) => setTerminalSingleTheme(event.target.value)}
                  >
                    {terminalThemeOptions.map((name) => (
                      <option key={`terminal-theme-${name}`} value={name}>
                        {name}
                      </option>
                    ))}
                  </select>
                </label>
              )}
            </div>
          </SettingsSectionCard>
        </div>
      );
    }

    if (activeCategoryId === "scripts") {
      return (
        <div className="flex flex-col gap-3">
          <SharedScriptsManagerModal
            root={sharedScriptsRoot}
            inline
            headerActions={(
              <button
                className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                onClick={() => void handleOpenSharedScriptsRoot()}
              >
                打开目录
              </button>
            )}
          />
        </div>
      );
    }

    if (activeCategoryId === "workflow") {
      return (
        <div className="flex flex-col gap-3">
          <SettingsSectionCard
            title="Git 身份"
            description="维护常用提交身份，保存时自动清理空行。"
          >
            <div className="flex flex-col gap-2">
              {gitIdentities.length === 0 ? (
                <div className="rounded-lg border border-dashed border-border bg-secondary-background px-3 py-3 text-fs-caption text-secondary-text">
                  暂无 Git 身份，点击下方“添加身份”创建。
                </div>
              ) : null}

              {gitIdentities.map((identity, index) => {
                const nameInputId = `settings-git-identity-name-${index}`;
                const emailInputId = `settings-git-identity-email-${index}`;
                return (
                  <div
                    key={`git-identity-${index}`}
                    className="rounded-lg border border-border bg-secondary-background px-3 py-3"
                  >
                    <div className="mb-2 text-fs-caption text-secondary-text">身份 {index + 1}</div>
                    <div className="grid gap-2 md:grid-cols-[minmax(140px,1fr)_minmax(220px,1fr)_auto] md:items-end">
                      <label className="flex flex-col gap-1 text-[13px] text-secondary-text" htmlFor={nameInputId}>
                        <span>用户名</span>
                        <input
                          id={nameInputId}
                          className={INPUT_CLASS}
                          value={identity.name}
                          onChange={(event) => handleUpdateGitIdentity(index, "name", event.target.value)}
                          placeholder="用户名"
                        />
                      </label>

                      <label className="flex flex-col gap-1 text-[13px] text-secondary-text" htmlFor={emailInputId}>
                        <span>邮箱</span>
                        <input
                          id={emailInputId}
                          type="email"
                          className={INPUT_CLASS}
                          value={identity.email}
                          onChange={(event) => handleUpdateGitIdentity(index, "email", event.target.value)}
                          placeholder="邮箱"
                        />
                      </label>

                      <button
                        className={`btn btn-outline min-h-[40px] whitespace-nowrap ${BUTTON_FOCUS_RING_CLASS}`}
                        onClick={() => handleRemoveGitIdentity(index)}
                      >
                        移除
                      </button>
                    </div>
                  </div>
                );
              })}
            </div>

            <div className="flex items-center justify-end">
              <button
                className={`btn btn-outline min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                onClick={handleAddGitIdentity}
              >
                添加身份
              </button>
            </div>
          </SettingsSectionCard>
        </div>
      );
    }

    return null;
  };

  return (
    <>
      <div className="modal-overlay" role="presentation">
        <div
          className={[
            "modal-panel min-w-[320px] overflow-hidden",
            isExpanded ? "w-[min(1520px,99vw)] h-[96vh]" : "w-[min(980px,96vw)] h-[min(88vh,760px)]",
          ].join(" ")}
          role="dialog"
          aria-modal="true"
          aria-labelledby={dialogTitleId}
        >
          <header className="rounded-xl border border-border bg-card-bg px-4 py-3">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div id={dialogTitleId} className="text-[16px] font-semibold text-text">
                  设置
                </div>
                <div className="mt-1 text-fs-caption text-secondary-text">
                  统一管理应用更新、终端体验、脚本与协作配置。
                </div>
              </div>

              <div className="flex items-center gap-2">
                <div
                  className={[
                    "rounded-full border px-2 py-1 text-fs-caption",
                    isDirty
                      ? "border-accent bg-[rgba(69,59,231,0.15)] text-accent"
                      : "border-border bg-button-bg text-secondary-text",
                  ].join(" ")}
                >
                  {isDirty ? "有未保存变更" : "已同步"}
                </div>

                <button
                  className={`icon-btn min-h-[40px] min-w-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                  onClick={() => setIsExpanded((prev) => !prev)}
                  title={isExpanded ? "还原" : "放大"}
                  aria-label={isExpanded ? "还原设置窗口大小" : "放大设置窗口"}
                  disabled={isSaving}
                >
                  {isExpanded ? <IconMinimize2 size={14} /> : <IconMaximize2 size={14} />}
                </button>

                <button
                  className={`icon-btn min-h-[40px] min-w-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
                  onClick={() => void handleClose()}
                  aria-label="关闭设置"
                  disabled={isSaving}
                >
                  <IconX size={14} />
                </button>
              </div>
            </div>
          </header>

          <div className="mt-3 grid min-h-0 flex-1 gap-3 md:grid-cols-[260px_minmax(0,1fr)]">
            <aside className="rounded-xl border border-border bg-card-bg p-2.5">
              <div className="flex gap-2 overflow-x-auto pb-1 md:flex-col md:overflow-visible md:pb-0">
                {SETTINGS_CATEGORIES.map((category) => {
                  const isActive = category.id === activeCategoryId;
                  return (
                    <button
                      key={category.id}
                      className={[
                        "min-h-[44px] min-w-[148px] rounded-lg border px-3 py-2 text-left transition-colors",
                        BUTTON_FOCUS_RING_CLASS,
                        isActive
                          ? "border-accent bg-[rgba(69,59,231,0.12)] text-text"
                          : "border-border bg-secondary-background text-secondary-text hover:bg-button-bg hover:text-text",
                      ].join(" ")}
                      onClick={() => setActiveCategoryId(category.id)}
                      aria-current={isActive ? "page" : undefined}
                    >
                      <div className="text-[13px] font-semibold">{category.label}</div>
                      {category.description ? (
                        <div className="mt-0.5 text-fs-caption leading-5 opacity-90">{category.description}</div>
                      ) : null}
                    </button>
                  );
                })}
              </div>
            </aside>

            <section className="flex min-h-0 flex-col rounded-xl border border-border bg-card-bg p-4">
              <div className="mb-3 border-b border-divider pb-3">
                <div className="text-[14px] font-semibold text-text">{activeCategory.label}</div>
                {activeCategory.description ? (
                  <div className="mt-1 text-fs-caption text-secondary-text">{activeCategory.description}</div>
                ) : null}
              </div>
              <div className="min-h-0 flex-1 overflow-y-auto pr-1">{renderCategoryContent()}</div>
            </section>
          </div>

          <footer className="mt-3 flex items-center justify-between gap-3 rounded-xl border border-border bg-card-bg px-4 py-3">
            <div className="text-fs-caption text-secondary-text">
              {isSaving
                ? "正在保存设置，请稍候..."
                : isDirty
                  ? "检测到变更，点击右侧按钮保存并关闭。"
                  : "当前配置已同步，点击右侧按钮关闭。"}
            </div>
            <button
              className={`btn btn-primary min-h-[40px] ${BUTTON_FOCUS_RING_CLASS}`}
              onClick={() => void handleClose()}
              disabled={isSaving}
            >
              {isSaving ? "保存中..." : isDirty ? "保存并关闭" : "关闭"}
            </button>
          </footer>
        </div>
      </div>

    </>
  );
}

type SettingsSectionCardProps = {
  title: string;
  description: string;
  children: ReactNode;
};

function SettingsSectionCard({ title, description, children }: SettingsSectionCardProps) {
  return (
    <section className="rounded-xl border border-border bg-secondary-background p-3">
      <div className="mb-2">
        <div className="text-[13px] font-semibold text-text">{title}</div>
        <div className="mt-1 text-fs-caption text-secondary-text">{description}</div>
      </div>
      <div className="flex flex-col gap-2.5">{children}</div>
    </section>
  );
}

type SettingsToggleRowProps = {
  title: string;
  description?: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
};

function SettingsToggleRow({ title, description, checked, onChange }: SettingsToggleRowProps) {
  return (
    <div className="flex items-start justify-between gap-3 rounded-lg border border-border bg-card-bg px-3 py-2.5">
      <div className="min-w-0">
        <div className="text-[13px] font-medium text-text">{title}</div>
        {description ? <div className="mt-1 text-fs-caption text-secondary-text">{description}</div> : null}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={title}
        className={[
          "relative mt-0.5 h-7 w-12 shrink-0 rounded-full border transition-colors duration-200 motion-reduce:transition-none",
          BUTTON_FOCUS_RING_CLASS,
          checked ? "border-accent bg-[rgba(69,59,231,0.25)]" : "border-border bg-button-bg",
        ].join(" ")}
        onClick={() => onChange(!checked)}
      >
        <span
          className={[
            "absolute left-1 top-1 h-5 w-5 rounded-full bg-white shadow transition-transform duration-200 motion-reduce:transition-none",
            checked ? "translate-x-5" : "translate-x-0",
          ].join(" ")}
        />
      </button>
    </div>
  );
}

async function resolveHomePath(path: string): Promise<string> {
  const homePath = (await getHomeDirRuntime()).replace(/[\\/]+$/, "");
  if (path === "~") {
    return homePath;
  }
  if (path.startsWith("~/") || path.startsWith("~\\")) {
    return `${homePath}/${path.slice(2)}`;
  }
  return path;
}

type UpdateStatusLineProps = {
  state: UpdateState;
};

function UpdateStatusLine({ state }: UpdateStatusLineProps) {
  if (state.status === "idle") {
    return null;
  }
  if (state.status === "checking") {
    return (
      <div className="text-fs-caption text-secondary-text" role="status" aria-live="polite">
        检查中...
      </div>
    );
  }
  if (state.status === "error") {
    return (
      <div className="text-fs-caption text-error" role="alert">
        检查失败：{state.message}
      </div>
    );
  }
  if (state.status === "update") {
    return (
      <div className="text-fs-caption text-warning" role="status" aria-live="polite">
        发现新版本 {state.latestVersion}，当前 {state.currentVersion}
      </div>
    );
  }
  return (
    <div className="text-fs-caption text-success" role="status" aria-live="polite">
      已是最新版本 {state.latestVersion}
    </div>
  );
}
