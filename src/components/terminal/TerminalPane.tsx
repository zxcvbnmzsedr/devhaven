import { useCallback, useEffect, useRef, useState } from "react";
import { Terminal, type IDisposable, type ILink, type ILinkProvider, type ITheme } from "xterm";
import { FitAddon } from "xterm-addon-fit";
import { SearchAddon } from "xterm-addon-search";
import { WebglAddon } from "xterm-addon-webgl";
import { WebLinksAddon } from "xterm-addon-web-links";
import { SerializeAddon } from "xterm-addon-serialize";
import "xterm/css/xterm.css";

import { copyToClipboard, openInFinder } from "../../services/system";
import {
  buildTerminalPtyRegistryKey,
  cacheTerminalPtyState,
  consumeTerminalPtyCachedState,
  ensureTerminalPtyId,
  listenTerminalExit,
  listenTerminalOutput,
  releaseTerminalPtySession,
  resizeTerminal,
  retainTerminalPtySession,
  writeTerminal,
} from "../../services/terminal";
import { openPathRuntime, openUrlRuntime } from "../../platform/runtime";
import { APP_RESUME_EVENT } from "../../utils/appResume";
import { trimTerminalOutputTail } from "./terminalEscapeTrim";

const TERMINAL_SCROLLBACK_LINES = 5000;
const CONNECT_OUTPUT_BUFFER_MAX_CHARS = 512 * 1024;
const REPLAY_OVERLAP_SCAN_MAX_CHARS = 64 * 1024;
const WAKE_RECOVERY_DELAYS_MS = [120, 360] as const;
const SEARCH_OPTIONS = {
  caseSensitive: false,
  regex: false,
  wholeWord: false,
};
const SAFE_LINK_PROTOCOLS = new Set(["http:", "https:", "mailto:"]);
const LOCAL_PATH_TOKEN_REGEX = /(?<![:/A-Za-z0-9._~-])(?:~\/|\/|Users\/)[^\s"'<>`|]+/g;
const LOCAL_PATH_TRAILING_PUNCTUATION = /[.,;!?]+$/;
const LOCAL_PATH_MATCH_WINDOW_MAX_CHARS = 2048;

type LocalPathToken = {
  displayPath: string;
  openPath: string;
};

function isMacOS() {
  if (typeof navigator === "undefined") {
    return false;
  }
  return /mac/i.test(navigator.userAgent);
}

function toSafeLink(rawUrl: string): string | null {
  try {
    const parsed = new URL(rawUrl);
    if (!SAFE_LINK_PROTOCOLS.has(parsed.protocol.toLowerCase())) {
      return null;
    }
    return parsed.toString();
  } catch {
    return null;
  }
}

function shouldOpenByModifierKey(event: MouseEvent, isMac: boolean): boolean {
  return isMac ? event.metaKey || event.ctrlKey : event.ctrlKey || event.metaKey;
}

function resolveHomeDirFromCwd(cwd: string): string | null {
  const segments = cwd.split("/");
  if (segments.length < 3) {
    return null;
  }

  const username = segments[2];
  if (!username) {
    return null;
  }

  if (segments[1] === "Users") {
    return `/Users/${username}`;
  }
  if (segments[1] === "home") {
    return `/home/${username}`;
  }

  return null;
}

function parseLocalPathToken(rawPath: string, homeDir: string | null): LocalPathToken | null {
  const trimmed = rawPath.trim();
  if (!(trimmed.startsWith("/") || trimmed.startsWith("~/") || trimmed.startsWith("Users/"))) {
    return null;
  }
  const displayPath = trimmed.replace(LOCAL_PATH_TRAILING_PUNCTUATION, "");
  if (displayPath.length <= 1 || displayPath.includes("\0")) {
    return null;
  }

  if (displayPath.startsWith("/")) {
    return { displayPath, openPath: displayPath };
  }
  if (displayPath.startsWith("Users/")) {
    return { displayPath, openPath: `/${displayPath}` };
  }
  if (displayPath.startsWith("~/")) {
    if (!homeDir) {
      return null;
    }
    return { displayPath, openPath: `${homeDir}${displayPath.slice(1)}` };
  }

  return null;
}

function shouldContinueWrappedPathScan(lineText: string): boolean {
  return lineText.indexOf(" ") === -1;
}

function getWindowedLineStrings(bufferLineNumber: number, term: Terminal): [string[], number] {
  const activeBuffer = term.buffer.active;
  const currentLine = activeBuffer.getLine(bufferLineNumber);
  if (!currentLine) {
    return [[], bufferLineNumber];
  }

  const currentLineText = currentLine.translateToString(true);
  const strings: string[] = [currentLineText];
  let startLine = bufferLineNumber;

  if (currentLine.isWrapped && currentLineText[0] !== " ") {
    let scannedChars = 0;
    while (scannedChars < LOCAL_PATH_MATCH_WINDOW_MAX_CHARS) {
      const previousLineNumber = startLine - 1;
      const previousLine = activeBuffer.getLine(previousLineNumber);
      if (!previousLine) {
        break;
      }

      const previousText = previousLine.translateToString(true);
      strings.unshift(previousText);
      scannedChars += previousText.length;
      startLine = previousLineNumber;

      if (!previousLine.isWrapped || !shouldContinueWrappedPathScan(previousText)) {
        break;
      }
    }
  }

  let endLine = bufferLineNumber;
  let scannedChars = 0;
  while (scannedChars < LOCAL_PATH_MATCH_WINDOW_MAX_CHARS) {
    const nextLineNumber = endLine + 1;
    const nextLine = activeBuffer.getLine(nextLineNumber);
    if (!nextLine || !nextLine.isWrapped) {
      break;
    }

    const nextText = nextLine.translateToString(true);
    strings.push(nextText);
    scannedChars += nextText.length;
    endLine = nextLineNumber;

    if (!shouldContinueWrappedPathScan(nextText)) {
      break;
    }
  }

  return [strings, startLine];
}

function mapStringIndexToBufferPosition(
  term: Terminal,
  bufferLineNumber: number,
  startColumn: number,
  stringIndex: number,
): [number, number] {
  const activeBuffer = term.buffer.active;
  const reusableCell = activeBuffer.getNullCell();
  let lineNumber = bufferLineNumber;
  let column = startColumn;

  while (stringIndex > 0) {
    const line = activeBuffer.getLine(lineNumber);
    if (!line) {
      return [-1, -1];
    }

    for (let cellIndex = column; cellIndex < line.length; cellIndex += 1) {
      line.getCell(cellIndex, reusableCell);
      const chars = reusableCell.getChars();

      if (reusableCell.getWidth()) {
        stringIndex -= chars.length || 1;
        if (cellIndex === line.length - 1 && chars === "") {
          const nextLine = activeBuffer.getLine(lineNumber + 1);
          if (nextLine && nextLine.isWrapped) {
            nextLine.getCell(0, reusableCell);
            if (reusableCell.getWidth() === 2) {
              stringIndex += 1;
            }
          }
        }
      }

      if (stringIndex < 0) {
        return [lineNumber, cellIndex];
      }
    }

    lineNumber += 1;
    column = 0;
  }

  return [lineNumber, column];
}

function createLocalPathLinkProvider(
  term: Terminal,
  cwd: string,
  onActivate: (event: MouseEvent, path: string) => void,
): ILinkProvider {
  const homeDir = resolveHomeDirFromCwd(cwd);

  return {
    provideLinks(bufferLineNumber, callback) {
      const [windowedLineStrings, startLineNumber] = getWindowedLineStrings(bufferLineNumber - 1, term);
      const mergedText = windowedLineStrings.join("");
      if (!mergedText.includes("/")) {
        callback(undefined);
        return;
      }

      const links: ILink[] = [];
      LOCAL_PATH_TOKEN_REGEX.lastIndex = 0;
      let match: RegExpExecArray | null = null;
      while ((match = LOCAL_PATH_TOKEN_REGEX.exec(mergedText)) !== null) {
        const parsedPath = parseLocalPathToken(match[0], homeDir);
        if (!parsedPath) {
          continue;
        }

        const [startLine, startColumn] = mapStringIndexToBufferPosition(term, startLineNumber, 0, match.index);
        const [endLine, endColumn] = mapStringIndexToBufferPosition(
          term,
          startLine,
          startColumn,
          parsedPath.displayPath.length,
        );
        if (startLine < 0 || startColumn < 0 || endLine < 0 || endColumn < 0) {
          continue;
        }

        links.push({
          range: {
            start: { x: startColumn + 1, y: startLine + 1 },
            end: { x: endColumn, y: endLine + 1 },
          },
          text: parsedPath.openPath,
          activate: onActivate,
        });
      }
      callback(links.length > 0 ? links : undefined);
    },
  };
}

function mergeReplayWithBufferedOutput(replayData: string, bufferedOutput: string): string {
  if (!replayData) {
    return bufferedOutput;
  }
  if (!bufferedOutput) {
    return replayData;
  }

  const maxOverlap = Math.min(REPLAY_OVERLAP_SCAN_MAX_CHARS, replayData.length, bufferedOutput.length);
  for (let overlap = maxOverlap; overlap > 0; overlap -= 1) {
    if (replayData.endsWith(bufferedOutput.slice(0, overlap))) {
      return replayData + bufferedOutput.slice(overlap);
    }
  }

  return replayData + bufferedOutput;
}
export type TerminalPaneProps = {
  sessionId: string;
  cwd: string;
  savedState?: string | null;
  windowLabel: string;
  clientId: string;
  useWebgl: boolean;
  theme: ITheme;
  isActive: boolean;
  onActivate: (sessionId: string) => void;
  onExit: (sessionId: string, code?: number | null) => void;
  onPtyReady?: (sessionId: string, ptyId: string) => void;
  onRegisterSnapshotProvider: (sessionId: string, provider: () => string | null) => () => void;
  preserveSessionOnUnmount?: boolean;
};

export default function TerminalPane({
  sessionId,
  cwd,
  savedState,
  windowLabel,
  clientId,
  useWebgl,
  theme,
  isActive,
  onActivate,
  onExit,
  onPtyReady,
  onRegisterSnapshotProvider,
  preserveSessionOnUnmount = false,
}: TerminalPaneProps) {
  const containerRef = useRef<HTMLDivElement | null>(null);
  const termRef = useRef<Terminal | null>(null);
  const fitAddonRef = useRef<FitAddon | null>(null);
  const searchAddonRef = useRef<SearchAddon | null>(null);
  const serializeAddonRef = useRef<SerializeAddon | null>(null);
  const webLinksAddonRef = useRef<WebLinksAddon | null>(null);
  const webglAddonRef = useRef<WebglAddon | null>(null);
  const webglContextLossListenerRef = useRef<IDisposable | null>(null);
  const resizeFrameRef = useRef<number | null>(null);
  const wakeRecoveryFrameRef = useRef<number | null>(null);
  const wakeRecoveryTimersRef = useRef<number[]>([]);
  const lastResizeSignatureRef = useRef<string | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const ptyIdRef = useRef<string | null>(null);
  const syncPtySizeRef = useRef<() => void>(() => undefined);
  const restoredRef = useRef(false);
  const initialSavedStateRef = useRef<string | null>(savedState ?? null);
  const themeRef = useRef<ITheme>(theme);
  const searchOpenRef = useRef(false);
  const isMacRef = useRef(isMacOS());
  const [searchOpen, setSearchOpen] = useState(false);
  const [searchKeyword, setSearchKeyword] = useState("");
  const [webglPermanentlyDisabled, setWebglPermanentlyDisabled] = useState(false);
  themeRef.current = theme;

  const disposeWebglAddon = useCallback(() => {
    try {
      webglContextLossListenerRef.current?.dispose();
    } catch {
      // ignore
    } finally {
      webglContextLossListenerRef.current = null;
    }

    try {
      webglAddonRef.current?.dispose();
    } catch (error) {
      console.warn("释放 WebGL 终端渲染器失败。", error);
    } finally {
      webglAddonRef.current = null;
    }
  }, []);

  const clearWakeRecoverySchedule = useCallback(() => {
    if (wakeRecoveryFrameRef.current !== null) {
      window.cancelAnimationFrame(wakeRecoveryFrameRef.current);
      wakeRecoveryFrameRef.current = null;
    }

    for (const timer of wakeRecoveryTimersRef.current) {
      window.clearTimeout(timer);
    }
    wakeRecoveryTimersRef.current = [];
  }, []);

  const ensureWebglRenderer = useCallback(
    (options?: { forceRecreate?: boolean }) => {
      const term = termRef.current;
      if (!term) {
        return;
      }

      if (!useWebgl || webglPermanentlyDisabled) {
        if (webglAddonRef.current) {
          disposeWebglAddon();
        }
        return;
      }

      if (options?.forceRecreate && webglAddonRef.current) {
        disposeWebglAddon();
      }

      if (webglAddonRef.current) {
        return;
      }

      try {
        const addon = new WebglAddon();
        const contextLossUnlisten = addon.onContextLoss(() => {
          console.warn("检测到 WebGL 上下文丢失，已回退到默认终端渲染器。");
          setWebglPermanentlyDisabled(true);
          disposeWebglAddon();
        });
        term.loadAddon(addon);
        webglContextLossListenerRef.current?.dispose();
        webglContextLossListenerRef.current = contextLossUnlisten;
        webglAddonRef.current = addon;
      } catch (error) {
        console.warn("WebGL 终端渲染初始化失败，将回退到默认渲染。", error);
        setWebglPermanentlyDisabled(true);
        disposeWebglAddon();
      }
    },
    [disposeWebglAddon, useWebgl, webglPermanentlyDisabled],
  );

  const recoverTerminalAfterResume = useCallback(
    (reason: string) => {
      if (typeof document !== "undefined" && document.visibilityState === "hidden") {
        return;
      }

      clearWakeRecoverySchedule();

      const runRecoveryPass = (forceRecreateWebgl: boolean) => {
        const term = termRef.current;
        if (!term) {
          return;
        }

        if (forceRecreateWebgl && isMacRef.current && useWebgl) {
          ensureWebglRenderer({ forceRecreate: true });
        } else {
          ensureWebglRenderer();
        }

        syncPtySizeRef.current();

        try {
          term.refresh(0, Math.max(0, term.rows - 1));
        } catch (error) {
          console.warn(`终端在 ${reason} 后刷新失败。`, error);
        }

        if (isActive) {
          term.focus();
        }
      };

      wakeRecoveryFrameRef.current = window.requestAnimationFrame(() => {
        wakeRecoveryFrameRef.current = null;
        runRecoveryPass(true);
      });

      for (const delay of WAKE_RECOVERY_DELAYS_MS) {
        const timer = window.setTimeout(() => {
          wakeRecoveryTimersRef.current = wakeRecoveryTimersRef.current.filter((item) => item !== timer);
          runRecoveryPass(false);
        }, delay);
        wakeRecoveryTimersRef.current.push(timer);
      }
    },
    [clearWakeRecoverySchedule, ensureWebglRenderer, isActive, useWebgl],
  );

  const closeSearch = useCallback(() => {
    searchAddonRef.current?.clearDecorations();
    setSearchOpen(false);
  }, []);

  const triggerSearch = useCallback(
    (forward: boolean, incremental: boolean) => {
      const addon = searchAddonRef.current;
      const keyword = searchKeyword.trim();
      if (!addon || !keyword) {
        return false;
      }
      if (forward) {
        return addon.findNext(keyword, { ...SEARCH_OPTIONS, incremental });
      }
      return addon.findPrevious(keyword, SEARCH_OPTIONS);
    },
    [searchKeyword],
  );

  useEffect(() => {
    searchOpenRef.current = searchOpen;
    if (searchOpen) {
      requestAnimationFrame(() => {
        searchInputRef.current?.focus();
        searchInputRef.current?.select();
      });
    }
  }, [searchOpen]);

  useEffect(() => {
    if (!searchOpen) {
      return;
    }
    if (!searchKeyword.trim()) {
      searchAddonRef.current?.clearDecorations();
      return;
    }
    triggerSearch(true, true);
  }, [searchKeyword, searchOpen, triggerSearch]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) {
      return;
    }
    const registryKey = buildTerminalPtyRegistryKey(windowLabel, sessionId);
    retainTerminalPtySession(registryKey);
    const cachedState = consumeTerminalPtyCachedState(registryKey);

    let disposed = false;
    const term = new Terminal({
      // 需要用 parser hook 过滤光标形态控制序列（Ghostty: shell-integration-features = no-cursor）。
      allowProposedApi: true,
      fontFamily:
        "\"Hack Nerd Font\", \"Hack\", \"Noto Sans SC\", ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
      fontSize: 12,
      cursorStyle: "block",
      cursorBlink: true,
      scrollback: TERMINAL_SCROLLBACK_LINES,
      theme: themeRef.current,
    });
    // 参考 Tabby：在 macOS 上拦截 Cmd 系快捷键，避免：
    // - 被浏览器/ WebView 当成默认快捷键（全选/复制等）触发页面滚动；
    // - 被 xterm 认为是“用户输入”导致 viewport 自动滚动到光标（底部）。
    //
    // 约定：真正的 SIGINT 仍使用 Ctrl+C；Cmd 组合键不下发到 PTY。
    term.attachCustomKeyEventHandler((event: KeyboardEvent) => {
      if (event.type !== "keydown") {
        return true;
      }

      if (!event.metaKey && !event.ctrlKey && !event.altKey && event.key === "Escape" && searchOpenRef.current) {
        closeSearch();
        event.preventDefault();
        event.stopPropagation();
        return false;
      }

      // 仅按下 Cmd（Meta）时也可能触发“滚到光标区域”，因此直接拦截。
      if (event.key === "Meta" || event.code === "MetaLeft" || event.code === "MetaRight") {
        event.preventDefault();
        event.stopPropagation();
        return false;
      }

      // 在终端聚焦时，统一拦截所有 Cmd 组合键，避免落到 WebView 默认行为。
      // 保留 Ctrl/Alt 的终端语义（例如 Ctrl+C / Option+B 等）。
      if (event.metaKey && !event.ctrlKey && !event.altKey) {
        const key = event.key.toLowerCase();
        if (key === "f") {
          setSearchOpen(true);
          event.preventDefault();
          event.stopPropagation();
          return false;
        }
        // 允许系统粘贴走默认通路（paste event），否则会导致终端无法 Cmd+V 粘贴。
        if (key === "v") {
          return true;
        }
        if (key === "a") {
          term.selectAll();
        } else if (key === "c") {
          const selection = term.getSelection();
          if (selection) {
            void copyToClipboard(selection);
            term.clearSelection();
          }
        }

        event.preventDefault();
        event.stopPropagation();
        return false;
      }

      if (
        !isMacRef.current &&
        event.ctrlKey &&
        event.shiftKey &&
        !event.metaKey &&
        !event.altKey &&
        event.key.toLowerCase() === "f"
      ) {
        setSearchOpen(true);
        event.preventDefault();
        event.stopPropagation();
        return false;
      }
      return true;
    });
    // 忽略 DECSCUSR（CSI Ps SP q），避免 shell/应用切换插入/正常模式时改成条形光标等。
    const cursorStyleHandler = term.parser.registerCsiHandler({ intermediates: " ", final: "q" }, () => true);
    const fitAddon = new FitAddon();
    const searchAddon = new SearchAddon();
    const serializeAddon = new SerializeAddon();
    const webLinksAddon = new WebLinksAddon((event, rawUrl) => {
      const shouldOpen = shouldOpenByModifierKey(event, isMacRef.current);
      if (!shouldOpen) {
        return;
      }
      const safeUrl = toSafeLink(rawUrl);
      if (!safeUrl) {
        console.warn("忽略不安全链接协议。", rawUrl);
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      void openUrlRuntime(safeUrl).catch((error) => {
        console.warn("打开链接失败。", error);
      });
    });
    const localPathLinkProvider = term.registerLinkProvider(
      createLocalPathLinkProvider(term, cwd, (event, resolvedPath) => {
        const shouldOpen = shouldOpenByModifierKey(event, isMacRef.current);
        if (!shouldOpen) {
          return;
        }
        event.preventDefault();
        event.stopPropagation();
        void openInFinder(resolvedPath)
          .catch((error) => {
            console.warn("在 Finder 中打开本地路径失败，回退到系统默认打开。", error);
            return openPathRuntime(resolvedPath);
          })
          .catch((error) => {
            console.warn("打开本地路径失败。", error);
          });
      }),
    );
    term.loadAddon(fitAddon);
    term.loadAddon(searchAddon);
    term.loadAddon(serializeAddon);
    term.loadAddon(webLinksAddon);
    const safeFit = () => {
      if (disposed) {
        return;
      }
      const core = (term as Terminal & { _core?: { _renderService?: { hasRenderer?: () => boolean } } })._core;
      const renderService = core?._renderService;
      if (renderService && typeof renderService.hasRenderer === "function" && !renderService.hasRenderer()) {
        return;
      }
      try {
        fitAddon.fit();
      } catch (error) {
        console.warn("终端尺寸自适配失败，稍后将重试。", error);
      }
    };
    const flushPtyResize = () => {
      const ptyId = ptyIdRef.current;
      if (!ptyId) {
        return;
      }
      // 避免布局抖动/隐藏容器阶段把 PTY 缩成 0x0，导致全屏 TUI（如 codex）渲染异常。
      const nextCols = Math.max(2, term.cols);
      const nextRows = Math.max(2, term.rows);
      const resizeSignature = `${ptyId}:${nextCols}x${nextRows}`;
      if (lastResizeSignatureRef.current === resizeSignature) {
        return;
      }
      lastResizeSignatureRef.current = resizeSignature;
      void resizeTerminal(ptyId, nextCols, nextRows).catch(() => undefined);
    };
    const schedulePtyResize = () => {
      if (resizeFrameRef.current !== null) {
        return;
      }
      // 合并到同一帧并按尺寸去重，避免重复 resize IPC。
      resizeFrameRef.current = window.requestAnimationFrame(() => {
        resizeFrameRef.current = null;
        if (disposed) {
          return;
        }
        flushPtyResize();
      });
    };
    const syncPtySize = () => {
      safeFit();
      schedulePtyResize();
    };
    syncPtySizeRef.current = syncPtySize;

    term.open(container);
    const renderOnce = term.onRender(() => {
      renderOnce.dispose();
      syncPtySize();
    });
    requestAnimationFrame(() => {
      if (disposed) {
        return;
      }
      syncPtySize();
    });
    if (document.fonts?.ready) {
      void document.fonts.ready.then(() => {
        if (disposed) {
          return;
        }
        syncPtySize();
      });
    }
    termRef.current = term;
    fitAddonRef.current = fitAddon;
    searchAddonRef.current = searchAddon;
    serializeAddonRef.current = serializeAddon;
    webLinksAddonRef.current = webLinksAddon;
    webglAddonRef.current = null;

    const resizeObserver = new ResizeObserver(() => {
      syncPtySize();
    });
    resizeObserver.observe(container);

    const disposable = term.onData((data) => {
      const ptyId = ptyIdRef.current;
      if (!ptyId) {
        return;
      }
      void writeTerminal(ptyId, data).catch(() => undefined);
    });

    let unlistenOutput: (() => void) | null = null;
    let unlistenExit: (() => void) | null = null;

    const connect = async () => {
      let ptyId: string | null = null;
      let replayData: string | null = null;
      let hydrated = false;
      let bufferedOutput = "";

      const flushBufferedOutput = () => {
        if (!bufferedOutput) {
          return;
        }
        term.write(bufferedOutput);
        bufferedOutput = "";
      };

      try {
        const outputUnlisten = await listenTerminalOutput((event) => {
          if (event.payload.sessionId !== sessionId) {
            return;
          }
          if (disposed) {
            return;
          }
          const chunk = event.payload.data;
          if (!chunk) {
            return;
          }

          if (!hydrated) {
            bufferedOutput += chunk;
            if (bufferedOutput.length > CONNECT_OUTPUT_BUFFER_MAX_CHARS) {
              bufferedOutput = trimTerminalOutputTail(bufferedOutput, CONNECT_OUTPUT_BUFFER_MAX_CHARS);
            }
            return;
          }

          term.write(chunk);
        });
        if (disposed) {
          outputUnlisten();
          return;
        }
        unlistenOutput = outputUnlisten;
      } catch (error) {
        console.error("订阅终端输出事件失败。", error);
        term.write("\r\n[订阅终端输出事件失败：请检查 Tauri capabilities 是否允许 terminal-* 窗口使用 core:event.listen]\r\n");
        return;
      }

      try {
        const exitUnlisten = await listenTerminalExit((event) => {
          if (event.payload.sessionId !== sessionId) {
            return;
          }
          if (disposed) {
            return;
          }
          onExit(sessionId, event.payload.code ?? null);
        });
        if (disposed) {
          exitUnlisten();
          unlistenOutput?.();
          return;
        }
        unlistenExit = exitUnlisten;
      } catch (error) {
        console.error("订阅终端退出事件失败。", error);
        term.write("\r\n[订阅终端退出事件失败：请检查 Tauri capabilities 是否允许 terminal-* 窗口使用 core:event.listen]\r\n");
      }

      try {
        const ready = await ensureTerminalPtyId(registryKey, {
          projectPath: cwd,
          cols: term.cols,
          rows: term.rows,
          windowLabel,
          sessionId,
          clientId,
        });
        ptyId = ready.ptyId;
        replayData = ready.replayData ?? null;
      } catch (error) {
        unlistenOutput?.();
        unlistenOutput = null;
        unlistenExit?.();
        unlistenExit = null;
        console.error("创建终端会话失败。", error);
        term.write("\r\n[创建终端会话失败]\r\n");
        return;
      }

      if (disposed) {
        return;
      }

      ptyIdRef.current = ptyId;
      syncPtySize();

      if (!restoredRef.current) {
        const baseState = cachedState ?? initialSavedStateRef.current ?? "";
        const replayRestoredState = replayData ? mergeReplayWithBufferedOutput(baseState, replayData) : baseState;
        const stateToRestore = bufferedOutput
          ? mergeReplayWithBufferedOutput(replayRestoredState, bufferedOutput)
          : replayRestoredState;
        if (stateToRestore) {
          restoredRef.current = true;
          term.write(stateToRestore);
          bufferedOutput = "";
        }
      }
      hydrated = true;
      flushBufferedOutput();

      // 当输出/退出事件监听建立后再通知外部：避免外部过早下发命令导致丢失起始输出。
      onPtyReady?.(sessionId, ptyId);
    };

    void connect();

    const unregisterSnapshot = onRegisterSnapshotProvider(sessionId, () => {
      const addon = serializeAddonRef.current;
      if (!addon) {
        return null;
      }
      return addon.serialize({
        excludeAltBuffer: false,
        excludeModes: true,
        scrollback: TERMINAL_SCROLLBACK_LINES,
      });
    });

    return () => {
      disposed = true;
      try {
        const addon = serializeAddonRef.current;
        if (addon) {
          cacheTerminalPtyState(
            registryKey,
            addon.serialize({
              excludeAltBuffer: false,
              excludeModes: true,
              scrollback: TERMINAL_SCROLLBACK_LINES,
            }),
          );
        }
      } catch (error) {
        console.warn("缓存终端状态失败。", error);
      }
      unregisterSnapshot();
      searchAddonRef.current = null;
      webLinksAddonRef.current = null;
      cursorStyleHandler.dispose();
      localPathLinkProvider.dispose();
      renderOnce.dispose();
      disposable.dispose();
      resizeObserver.disconnect();
      if (resizeFrameRef.current !== null) {
        window.cancelAnimationFrame(resizeFrameRef.current);
        resizeFrameRef.current = null;
      }
      clearWakeRecoverySchedule();
      syncPtySizeRef.current = () => undefined;
      lastResizeSignatureRef.current = null;
      unlistenOutput?.();
      unlistenExit?.();
      releaseTerminalPtySession(registryKey, clientId, { preserve: preserveSessionOnUnmount });
      // 注意：xterm@5 的 AddonManager 会在 core dispose 之后再 dispose addons，
      // WebglAddon 的 dispose 会调用 renderService.setRenderer，这时 renderService 已被 dispose
      // 会导致 `this._renderer.value.onRequestRedraw` 报错。
      //
      // 这里手动先 dispose WebglAddon，并把 `term.dispose()` 延迟到下一轮事件循环，
      // 避免 WebglAddon dispose 触发的渲染刷新/Viewport 定时器在 renderer 被销毁后执行，
      // 导致 `this._renderer.value.dimensions` 等空引用报错。
      disposeWebglAddon();
      setTimeout(() => {
        try {
          term.dispose();
        } catch (error) {
          console.warn("释放终端实例失败。", error);
        }
      }, 0);
    };
  }, [
    clientId,
    clearWakeRecoverySchedule,
    closeSearch,
    cwd,
    disposeWebglAddon,
    onExit,
    onPtyReady,
    onRegisterSnapshotProvider,
    sessionId,
    windowLabel,
    preserveSessionOnUnmount,
  ]);

  useEffect(() => {
    const term = termRef.current;
    if (!term) {
      return;
    }
    try {
      term.options.theme = theme;
      term.refresh(0, Math.max(0, term.rows - 1));
    } catch (error) {
      console.warn("更新终端主题失败。", error);
    }
  }, [theme]);

  useEffect(() => {
    ensureWebglRenderer();
  }, [ensureWebglRenderer]);

  useEffect(() => {
    if (typeof window === "undefined") {
      return;
    }

    const handleResume = () => {
      recoverTerminalAfterResume("应用恢复可见");
    };

    window.addEventListener(APP_RESUME_EVENT, handleResume as EventListener);
    return () => {
      clearWakeRecoverySchedule();
      window.removeEventListener(APP_RESUME_EVENT, handleResume as EventListener);
    };
  }, [clearWakeRecoverySchedule, recoverTerminalAfterResume]);

  useEffect(() => {
    if (!isActive) {
      return;
    }
    syncPtySizeRef.current();
    try {
      termRef.current?.refresh(0, Math.max(0, (termRef.current?.rows ?? 1) - 1));
    } catch (error) {
      console.warn("终端激活后刷新失败。", error);
    }
    termRef.current?.focus();
  }, [isActive]);

  return (
    <div
      className={`terminal-pane relative flex h-full w-full min-h-0 min-w-0 p-[10px] ${
        isActive ? "outline outline-1 outline-[var(--terminal-accent-outline)]" : ""
      }`}
      onMouseDownCapture={(event) => {
        const target = event.target;
        if (target instanceof Element && target.closest("[data-terminal-search-overlay=true]")) {
          return;
        }
        onActivate(sessionId);
        // 关键：当 Pane 已经是 active 时，useEffect 不会再次触发 focus。
        // 这会导致 ⌘A/⌘C 落到浏览器默认行为（全选页面/复制）并引发页面滚动到底部。
        requestAnimationFrame(() => termRef.current?.focus());
      }}
    >
      {searchOpen ? (
        <div
          data-terminal-search-overlay="true"
          className="absolute left-4 top-3 z-30 flex w-[240px] items-center gap-1 rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-panel-bg)]/95 p-1.5 shadow-md"
        >
          <input
            ref={searchInputRef}
            value={searchKeyword}
            onChange={(event) => setSearchKeyword(event.target.value)}
            placeholder="搜索当前 Pane..."
            className="h-7 w-full rounded-md border border-[var(--terminal-divider)] bg-[var(--terminal-bg)] px-2 text-[12px] text-[var(--terminal-fg)] outline-none focus-visible:border-[var(--terminal-accent-outline)]"
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                event.stopPropagation();
                triggerSearch(!event.shiftKey, false);
                return;
              }
              if (event.key === "Escape") {
                event.preventDefault();
                event.stopPropagation();
                closeSearch();
              }
            }}
          />
          <button
            type="button"
            title="上一个 (Shift+Enter)"
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] text-[11px] text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
            onClick={() => triggerSearch(false, false)}
          >
            ↑
          </button>
          <button
            type="button"
            title="下一个 (Enter)"
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] text-[11px] text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
            onClick={() => triggerSearch(true, false)}
          >
            ↓
          </button>
          <button
            type="button"
            title="关闭 (Esc)"
            className="inline-flex h-7 w-7 items-center justify-center rounded-md border border-[var(--terminal-divider)] text-[11px] text-[var(--terminal-muted-fg)] hover:bg-[var(--terminal-hover-bg)] hover:text-[var(--terminal-fg)]"
            onClick={() => closeSearch()}
          >
            ×
          </button>
        </div>
      ) : null}
      <div ref={containerRef} className="min-h-0 min-w-0 flex-1" />
    </div>
  );
}
