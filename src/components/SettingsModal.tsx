import { useEffect, useMemo, useState } from "react";
import { getVersion } from "@tauri-apps/api/app";
import { openUrl } from "@tauri-apps/plugin-opener";

import type { AppSettings, GitIdentity } from "../models/types";
import { checkForUpdates } from "../services/update";
import {
  TERMINAL_THEME_PRESETS,
  getTerminalThemePresetByName,
  parseTerminalThemeSetting,
} from "../themes/terminalThemes";
import { normalizeGitIdentities } from "../utils/gitIdentity";
import { IconX } from "./Icons";

type UpdateState =
  | { status: "idle" }
  | { status: "checking" }
  | { status: "latest"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "update"; currentVersion: string; latestVersion: string; url?: string }
  | { status: "error"; message: string; currentVersion?: string };

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

export type SettingsModalProps = {
  settings: AppSettings;
  onClose: () => void;
  onSaveSettings: (settings: AppSettings) => Promise<void>;
};

/** 设置弹窗，提供更新检查、终端与 Git 身份配置。 */
export default function SettingsModal({
  settings,
  onClose,
  onSaveSettings,
}: SettingsModalProps) {
  const [gitIdentities, setGitIdentities] = useState<GitIdentity[]>(settings.gitIdentities);
  const [showMonitorWindow, setShowMonitorWindow] = useState(settings.showMonitorWindow);
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
  const [isSaving, setIsSaving] = useState(false);

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
  const nextSettings = useMemo<AppSettings>(
    () => ({
      ...settings,
      showMonitorWindow,
      terminalUseWebglRenderer,
      terminalTheme: terminalThemeSetting,
      gitIdentities: normalizedGitIdentities,
    }),
    [normalizedGitIdentities, settings, showMonitorWindow, terminalThemeSetting, terminalUseWebglRenderer],
  );
  const isDirty = useMemo(() => {
    const normalizedStoredIdentities = normalizeGitIdentities(settings.gitIdentities);
    return !(
      isSameIdentities(nextSettings.gitIdentities, normalizedStoredIdentities) &&
      nextSettings.showMonitorWindow === settings.showMonitorWindow &&
      nextSettings.terminalUseWebglRenderer === settings.terminalUseWebglRenderer &&
      canonicalizeTerminalThemeSetting(nextSettings.terminalTheme) ===
        canonicalizeTerminalThemeSetting(settings.terminalTheme)
    );
  }, [nextSettings, settings]);

  useEffect(() => {
    setGitIdentities(settings.gitIdentities);
    setShowMonitorWindow(settings.showMonitorWindow);
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
  }, [
    settings.gitIdentities,
    settings.showMonitorWindow,
    settings.terminalUseWebglRenderer,
    settings.terminalTheme,
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

  const handleToggleMonitorWindow = (enabled: boolean) => {
    setShowMonitorWindow(enabled);
  };

  const handleToggleTerminalWebgl = (enabled: boolean) => {
    setTerminalUseWebglRenderer(enabled);
  };

  const handleToggleTerminalFollowSystem = (enabled: boolean) => {
    setTerminalFollowSystem(enabled);
  };

  useEffect(() => {
    let active = true;
    getVersion()
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
      await openUrl(updateState.url);
    } catch (error) {
      console.error("打开发布页面失败。", error);
    }
  };


  return (
    <div className="modal-overlay" role="dialog" aria-modal>
      <div className="modal-panel min-w-[600px] w-[min(760px,92vw)] max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between gap-4">
          <div>
            <div className="text-[16px] font-semibold">设置</div>
            <div className="text-fs-caption text-secondary-text">关闭窗口将自动保存</div>
          </div>
          <button className="icon-btn" onClick={() => void handleClose()} aria-label="关闭" disabled={isSaving}>
            <IconX size={14} />
          </button>
        </div>

        <section className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div className="text-[13px] font-semibold">更新与版本</div>
          <div className="flex flex-wrap items-center gap-2.5">
            <div className="rounded-full bg-button-bg px-2.5 py-1 text-fs-caption">当前版本：{versionLabel || "--"}</div>
            <button className="btn btn-outline" onClick={() => void handleCheckUpdate()}>
              {updateState.status === "checking" ? "检查中..." : "检查更新"}
            </button>
            {updateState.status === "update" || updateState.status === "latest" ? (
              <button className="btn" onClick={() => void handleOpenRelease()} disabled={!updateState.url}>
                查看发布
              </button>
            ) : null}
          </div>
          <UpdateStatusLine state={updateState} />
        </section>

        <section className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div className="text-[13px] font-semibold">悬浮窗</div>
          <label className="flex items-center gap-2 text-text">
            <input
              className="h-3.5 w-3.5"
              type="checkbox"
              checked={showMonitorWindow}
              onChange={(event) => handleToggleMonitorWindow(event.target.checked)}
            />
            <span>显示 CLI 悬浮监控窗（只读）</span>
          </label>
        </section>

        <section className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div className="text-[13px] font-semibold">终端</div>
          <label className="flex items-center gap-2 text-text">
            <input
              className="h-3.5 w-3.5"
              type="checkbox"
              checked={terminalUseWebglRenderer}
              onChange={(event) => handleToggleTerminalWebgl(event.target.checked)}
            />
            <span>启用 WebGL 渲染（提升性能）</span>
          </label>

          <div className="h-px bg-divider" />

          <div className="text-[12px] font-semibold text-text">主题</div>
          <label className="flex items-center gap-2 text-text">
            <input
              className="h-3.5 w-3.5"
              type="checkbox"
              checked={terminalFollowSystem}
              onChange={(event) => handleToggleTerminalFollowSystem(event.target.checked)}
            />
            <span>跟随系统浅/深色</span>
          </label>

          {terminalFollowSystem ? (
            <div className="grid grid-cols-[64px_minmax(0,1fr)] items-center gap-2">
              <div className="text-fs-caption text-secondary-text">浅色</div>
              <select
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                value={terminalLightTheme}
                onChange={(event) => setTerminalLightTheme(event.target.value)}
              >
                {terminalThemeOptions.map((name) => (
                  <option key={`terminal-theme-light-${name}`} value={name}>
                    {name}
                  </option>
                ))}
              </select>
              <div className="text-fs-caption text-secondary-text">深色</div>
              <select
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                value={terminalDarkTheme}
                onChange={(event) => setTerminalDarkTheme(event.target.value)}
              >
                {terminalThemeOptions.map((name) => (
                  <option key={`terminal-theme-dark-${name}`} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </div>
          ) : (
            <div className="grid grid-cols-[64px_minmax(0,1fr)] items-center gap-2">
              <div className="text-fs-caption text-secondary-text">主题</div>
              <select
                className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                value={terminalSingleTheme}
                onChange={(event) => setTerminalSingleTheme(event.target.value)}
              >
                {terminalThemeOptions.map((name) => (
                  <option key={`terminal-theme-${name}`} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </div>
          )}
        </section>

        <section className="flex flex-col gap-3 rounded-xl border border-border bg-card-bg p-3">
          <div className="mb-1 flex items-center justify-between gap-3">
            <div className="text-[13px] font-semibold">Git 身份</div>
            {isSaving && (
              <div className="rounded-md bg-[rgba(69,59,231,0.1)] px-2 py-1 text-[11px] text-accent animate-pulse">
                保存中...
              </div>
            )}
          </div>
          <div className="flex flex-col gap-2">
            {gitIdentities.map((identity, index) => (
              <div
                key={`git-identity-${index}`}
                className="grid grid-cols-[minmax(140px,1fr)_minmax(180px,1fr)_auto] items-center gap-2"
              >
                <input
                  className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                  value={identity.name}
                  onChange={(event) => handleUpdateGitIdentity(index, "name", event.target.value)}
                  placeholder="用户名"
                  aria-label={`Git 用户名 ${index + 1}`}
                />
                <input
                  type="email"
                  className="rounded-md border border-border bg-card-bg px-2 py-2 text-text focus:outline-2 focus:outline-accent focus:outline-offset-[-1px]"
                  value={identity.email}
                  onChange={(event) => handleUpdateGitIdentity(index, "email", event.target.value)}
                  placeholder="邮箱"
                  aria-label={`Git 邮箱 ${index + 1}`}
                />
                <button
                  className="btn btn-outline whitespace-nowrap"
                  onClick={() => handleRemoveGitIdentity(index)}
                >
                  移除
                </button>
              </div>
            ))}
          </div>
          <div className="flex items-center justify-end gap-2">
            <button className="btn btn-outline" onClick={handleAddGitIdentity}>
              添加身份
            </button>
          </div>
        </section>

      </div>
    </div>
  );
}

type UpdateStatusLineProps = {
  state: UpdateState;
};

function UpdateStatusLine({ state }: UpdateStatusLineProps) {
  if (state.status === "idle") {
    return null;
  }
  if (state.status === "checking") {
    return <div className="text-fs-caption text-secondary-text">检查中...</div>;
  }
  if (state.status === "error") {
    return <div className="text-fs-caption text-error">检查失败：{state.message}</div>;
  }
  if (state.status === "update") {
    return (
      <div className="text-fs-caption text-warning">
        发现新版本 {state.latestVersion}，当前 {state.currentVersion}
      </div>
    );
  }
  return <div className="text-fs-caption text-success">已是最新版本 {state.latestVersion}</div>;
}
