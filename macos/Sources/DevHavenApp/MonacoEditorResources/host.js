(function () {
  const MONACO_VERSION = "0.52.2";
  const MONACO_BASE_URL = new URL("../MonacoDiffResources/vendor/monaco/vs/", window.location.href);
  const MONACO_BASE = MONACO_BASE_URL.toString().replace(/\/$/, "");
  const MONACO_LOADER_URL = new URL("../MonacoDiffResources/vendor/monaco/vs/loader.js", window.location.href).toString();
  const MONACO_WORKER_URL = new URL("../MonacoDiffResources/vendor/monaco/vs/base/worker/workerMain.js", window.location.href).toString();

  const editorRoot = document.getElementById("editor-root");
  const statusNode = document.getElementById("status");

  let editor;
  let model;
  let ready = false;
  let lastPayload = null;
  let suppressModelEvents = false;
  let saveCommandInstalled = false;
  let lastActionId = null;
  let debounceTimer = null;
  let lineDecorations = [];
  let inlineDecorations = [];

  function postMessage(type, payload) {
    const handler = window.webkit?.messageHandlers?.devhavenMonacoEditor;
    if (!handler) return;
    handler.postMessage(Object.assign({ type }, payload || {}));
  }

  function showStatus(message) {
    statusNode.textContent = message;
    statusNode.classList.remove("hidden");
  }

  function hideStatus() {
    statusNode.classList.add("hidden");
  }

  function buildWorkerURL() {
    const source =
      `self.MonacoEnvironment={baseUrl:'${MONACO_BASE}/'};` +
      `importScripts('${MONACO_WORKER_URL}');`;
    return `data:text/javascript;charset=utf-8,${encodeURIComponent(source)}`;
  }

  window.MonacoEnvironment = {
    getWorkerUrl: function () {
      return buildWorkerURL();
    }
  };

  function loadMonaco() {
    return new Promise((resolve, reject) => {
      const existingRequire = window.require;
      if (existingRequire && window.monaco) {
        resolve(window.monaco);
        return;
      }

      const loader = document.createElement("script");
      loader.src = MONACO_LOADER_URL;
      loader.onload = function () {
        window.require.config({ paths: { vs: MONACO_BASE } });
        window.require(["vs/editor/editor.main"], function () {
          resolve(window.monaco);
        }, reject);
      };
      loader.onerror = reject;
      document.head.appendChild(loader);
    });
  }

  function ensureEditor(monaco) {
    if (editor) return;

    editor = monaco.editor.create(editorRoot, {
      automaticLayout: true,
      readOnly: false,
      minimap: { enabled: false },
      smoothScrolling: true,
      cursorSmoothCaretAnimation: "on",
      scrollBeyondLastLine: false,
      stickyScroll: { enabled: false },
      lineNumbersMinChars: 4,
      fontFamily: "SF Mono, Menlo, Monaco, Consolas, monospace",
      fontSize: 12.5,
      lineHeight: 20,
      padding: {
        top: 10,
        bottom: 18
      },
      scrollbar: {
        verticalScrollbarSize: 11,
        horizontalScrollbarSize: 11,
        alwaysConsumeMouseWheel: false
      },
      guides: {
        indentation: true,
        highlightActiveIndentation: true
      },
      bracketPairColorization: { enabled: true }
    });
  }

  function installTheme(monaco, theme) {
    monaco.editor.defineTheme("devhaven-editor-dark", {
      base: "vs-dark",
      inherit: true,
      rules: [
        { token: "comment", foreground: "7A8394" },
        { token: "keyword", foreground: "C792EA" },
        { token: "string", foreground: "C3E88D" },
        { token: "number", foreground: "F78C6C" },
        { token: "type.identifier", foreground: "82AAFF" },
        { token: "identifier", foreground: "D7DAE0" }
      ],
      colors: {
        "editor.background": "#17191d",
        "editor.foreground": "#d7dae0",
        "editorLineNumber.foreground": "#5c6473",
        "editorLineNumber.activeForeground": "#c7ccd6",
        "editor.selectionBackground": "#2b467033",
        "editor.inactiveSelectionBackground": "#2b467022",
        "editorCursor.foreground": "#8ab4ff",
        "editorIndentGuide.background1": "#2a2f38",
        "editorIndentGuide.activeBackground1": "#454c59",
        "editorWhitespace.foreground": "#39414f",
        "editorOverviewRuler.border": "#00000000",
        "editorGutter.background": "#14161a",
        "editorRuler.foreground": "#39414f",
        "editor.findMatchBackground": "#ffc75e44",
        "editor.findMatchBorder": "#ffc75e88",
        "editor.findMatchHighlightBackground": "#7aa2f733",
        "editor.lineHighlightBackground": "#ffffff08",
        "editor.lineHighlightBorder": "#00000000"
      }
    });

    monaco.editor.defineTheme("devhaven-editor-light", {
      base: "vs",
      inherit: true,
      rules: [
        { token: "comment", foreground: "7D8590" },
        { token: "keyword", foreground: "7C4DFF" },
        { token: "string", foreground: "0B8F5C" },
        { token: "number", foreground: "D05C1F" },
        { token: "type.identifier", foreground: "005CC5" },
        { token: "identifier", foreground: "1f2430" }
      ],
      colors: {
        "editor.background": "#fbfcff",
        "editor.foreground": "#1f2430",
        "editorLineNumber.foreground": "#9aa3b2",
        "editorLineNumber.activeForeground": "#4a5160",
        "editor.selectionBackground": "#9ecbff44",
        "editor.inactiveSelectionBackground": "#9ecbff26",
        "editorCursor.foreground": "#245bdb",
        "editorIndentGuide.background1": "#dfe5ef",
        "editorIndentGuide.activeBackground1": "#c4cedd",
        "editorWhitespace.foreground": "#d2d8e2",
        "editorOverviewRuler.border": "#00000000",
        "editorGutter.background": "#f5f7fc",
        "editorRuler.foreground": "#d2d8e2",
        "editor.findMatchBackground": "#c78b0033",
        "editor.findMatchBorder": "#c78b0077",
        "editor.findMatchHighlightBackground": "#245bdb22",
        "editor.lineHighlightBackground": "#245bdb0d",
        "editor.lineHighlightBorder": "#00000000"
      }
    });

    document.documentElement.dataset.theme = theme === "vs" ? "light" : "dark";
    monaco.editor.setTheme(theme === "vs" ? "devhaven-editor-light" : "devhaven-editor-dark");
  }

  function languageForPayload(payload) {
    return payload.language || "plaintext";
  }

  function installModelListener() {
    if (!model) {
      return;
    }
    model.onDidChangeContent(() => {
      if (suppressModelEvents) {
        return;
      }
      window.clearTimeout(debounceTimer);
      debounceTimer = window.setTimeout(() => {
        postMessage("contentChanged", { text: model.getValue() });
      }, 120);
    });
  }

  function createOrUpdateModel(monaco, payload) {
    const language = languageForPayload(payload);
    if (!model) {
      model = monaco.editor.createModel(payload.text, language);
      installModelListener();
    } else if (model.getValue() !== payload.text) {
      suppressModelEvents = true;
      model.setValue(payload.text);
      suppressModelEvents = false;
      monaco.editor.setModelLanguage(model, language);
    } else {
      monaco.editor.setModelLanguage(model, language);
    }

    editor.setModel(model);
  }

  function lineNumbersOption(payload) {
    return payload.displayOptions?.showsLineNumbers ? "on" : "off";
  }

  function wordWrapOption(payload) {
    return payload.displayOptions?.usesSoftWraps ? "on" : "off";
  }

  function whitespaceOption(payload) {
    return payload.displayOptions?.showsWhitespaceCharacters ? "all" : "none";
  }

  function rulersOption(payload) {
    if (!payload.displayOptions?.showsRightMargin) {
      return [];
    }
    return [Math.max(40, Number(payload.displayOptions.rightMarginColumn) || 120)];
  }

  function applyDisplayOptions(payload) {
    editor.updateOptions({
      readOnly: !payload.isEditable,
      lineNumbers: lineNumbersOption(payload),
      renderLineHighlight: payload.displayOptions?.highlightsCurrentLine ? "line" : "none",
      wordWrap: wordWrapOption(payload),
      renderWhitespace: whitespaceOption(payload),
      rulers: rulersOption(payload)
    });
  }

  function installCommands(monaco) {
    if (!editor || saveCommandInstalled) {
      return;
    }

    editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function () {
      postMessage("saveRequested");
    });
    saveCommandInstalled = true;
  }

  function clampLineNumber(lineNumber) {
    if (!model) {
      return 1;
    }
    return Math.min(Math.max(1, lineNumber), Math.max(1, model.getLineCount()));
  }

  function clampColumn(lineNumber, column) {
    if (!model) {
      return 1;
    }
    const maxColumn = model.getLineMaxColumn(clampLineNumber(lineNumber));
    return Math.min(Math.max(1, column), maxColumn);
  }

  function lineHighlightClassName(kind) {
    switch (kind) {
      case "added":
        return "devhaven-line-added";
      case "removed":
        return "devhaven-line-removed";
      case "changed":
        return "devhaven-line-changed";
      case "conflict":
        return "devhaven-line-conflict";
      default:
        return "devhaven-line-changed";
    }
  }

  function lineHighlightGutterClassName(kind) {
    switch (kind) {
      case "added":
        return "devhaven-line-added-gutter";
      case "removed":
        return "devhaven-line-removed-gutter";
      case "changed":
        return "devhaven-line-changed-gutter";
      case "conflict":
        return "devhaven-line-conflict-gutter";
      default:
        return "devhaven-line-changed-gutter";
    }
  }

  function inlineHighlightClassName(kind) {
    switch (kind) {
      case "added":
        return "devhaven-inline-added";
      case "removed":
        return "devhaven-inline-removed";
      case "changed":
        return "devhaven-inline-changed";
      case "conflict":
        return "devhaven-inline-conflict";
      default:
        return "devhaven-inline-changed";
    }
  }

  function applyDecorations(monaco, payload) {
    if (!editor || !model) {
      return;
    }

    const nextLineDecorations = (payload.highlights || [])
      .filter((highlight) => Number(highlight.lineCount) > 0)
      .map((highlight) => {
        const startLine = clampLineNumber(Number(highlight.startLine) + 1);
        const endLine = clampLineNumber(Number(highlight.startLine) + Math.max(Number(highlight.lineCount), 1));
        return {
          range: new monaco.Range(startLine, 1, endLine, 1),
          options: {
            isWholeLine: true,
            className: lineHighlightClassName(highlight.kind),
            linesDecorationsClassName: lineHighlightGutterClassName(highlight.kind)
          }
        };
      });
    lineDecorations = editor.deltaDecorations(lineDecorations, nextLineDecorations);

    const nextInlineDecorations = (payload.inlineHighlights || [])
      .filter((highlight) => Number(highlight.length) > 0)
      .map((highlight) => {
        const lineNumber = clampLineNumber(Number(highlight.lineIndex) + 1);
        const startColumn = clampColumn(lineNumber, Number(highlight.startColumn) + 1);
        const endColumn = clampColumn(lineNumber, startColumn + Number(highlight.length));
        if (endColumn <= startColumn) {
          return null;
        }
        return {
          range: new monaco.Range(lineNumber, startColumn, lineNumber, endColumn),
          options: {
            inlineClassName: inlineHighlightClassName(highlight.kind)
          }
        };
      })
      .filter((decoration) => decoration !== null);
    inlineDecorations = editor.deltaDecorations(inlineDecorations, nextInlineDecorations);
  }

  function triggerEditorAction(actionId) {
    if (!editor) {
      return;
    }

    lastActionId = actionId;
    editor.focus();

    const action = editor.getAction ? editor.getAction(actionId) : null;
    if (action && typeof action.run === "function") {
      action.run();
      return;
    }

    try {
      editor.trigger("keyboard", actionId, null);
    } catch (error) {
      console.warn("Failed to trigger Monaco action", actionId, error);
    }
  }

  async function applyPayload(payload) {
    lastPayload = payload;
    if (!ready) {
      return;
    }

    const monaco = window.monaco;
    installTheme(monaco, payload.theme);
    createOrUpdateModel(monaco, payload);
    applyDisplayOptions(payload);
    applyDecorations(monaco, payload);
    installCommands(monaco);
  }

  window.__devHavenMonacoEditor = {
    applyPayload,
    focusEditor() {
      editor?.focus();
    },
    startSearch() {
      triggerEditorAction("actions.find");
    },
    showReplace() {
      if (!lastPayload?.isEditable) {
        return;
      }
      triggerEditorAction("editor.action.startFindReplaceAction");
    },
    findNext() {
      triggerEditorAction("editor.action.nextMatchFindAction");
    },
    findPrevious() {
      triggerEditorAction("editor.action.previousMatchFindAction");
    },
    useSelectionForFind() {
      triggerEditorAction("actions.findWithSelection");
    },
    closeSearch() {
      triggerEditorAction("closeFindWidget");
    },
    goToLine(lineNumber) {
      if (!editor || !window.monaco) {
        return;
      }
      const resolvedLineNumber = clampLineNumber(Number(lineNumber) || 1);
      lastActionId = "editor.action.gotoLine";
      editor.focus();
      editor.setSelection(new window.monaco.Selection(resolvedLineNumber, 1, resolvedLineNumber, 1));
      editor.revealLineInCenter(resolvedLineNumber);
    },
    revealLine(lineNumber) {
      if (!editor) {
        return;
      }
      const resolvedLineNumber = clampLineNumber(Number(lineNumber) || 1);
      editor.revealLineInCenter(resolvedLineNumber);
    },
    debugSetText(text) {
      model?.setValue(text);
    },
    debugRequestSave() {
      postMessage("saveRequested");
    },
    debugSnapshot() {
      const rawOptions = editor?.getRawOptions?.() || null;
      return {
        hasEditor: Boolean(editor),
        text: model ? model.getValue() : null,
        language: model?.getLanguageId?.() || null,
        readOnly: rawOptions ? Boolean(rawOptions.readOnly) : null,
        lineNumber: editor?.getPosition?.()?.lineNumber ?? null,
        lastActionId,
        wordWrap: rawOptions?.wordWrap ?? null,
        lineNumbers: rawOptions?.lineNumbers ?? null,
        renderWhitespace: rawOptions?.renderWhitespace ?? null,
        lineDecorationCount: lineDecorations.length,
        inlineDecorationCount: inlineDecorations.length,
        rulers: Array.isArray(rawOptions?.rulers)
          ? rawOptions.rulers.map((entry) => {
            if (typeof entry === "number") {
              return entry;
            }
            if (entry && typeof entry.column === "number") {
              return entry.column;
            }
            return null;
          }).filter((entry) => entry !== null)
          : []
      };
    }
  };

  loadMonaco()
    .then((monaco) => {
      ensureEditor(monaco);
      const style = document.createElement("style");
      style.textContent = `
        .devhaven-line-added {
          background: linear-gradient(90deg, rgba(87, 197, 124, 0.16), rgba(87, 197, 124, 0.06));
        }
        .devhaven-line-removed {
          background: linear-gradient(90deg, rgba(255, 107, 129, 0.14), rgba(255, 107, 129, 0.05));
        }
        .devhaven-line-changed {
          background: linear-gradient(90deg, rgba(255, 199, 94, 0.18), rgba(255, 199, 94, 0.07));
        }
        .devhaven-line-conflict {
          background: linear-gradient(90deg, rgba(255, 149, 0, 0.18), rgba(255, 149, 0, 0.07));
        }
        .devhaven-line-added-gutter {
          border-left: 3px solid rgba(87, 197, 124, 0.92);
        }
        .devhaven-line-removed-gutter {
          border-left: 3px solid rgba(255, 107, 129, 0.92);
        }
        .devhaven-line-changed-gutter {
          border-left: 3px solid rgba(255, 199, 94, 0.95);
        }
        .devhaven-line-conflict-gutter {
          border-left: 3px solid rgba(255, 149, 0, 0.95);
        }
        .devhaven-inline-added {
          background: rgba(87, 197, 124, 0.24);
          border-radius: 3px;
        }
        .devhaven-inline-removed {
          background: rgba(255, 107, 129, 0.20);
          border-radius: 3px;
        }
        .devhaven-inline-changed {
          background: rgba(255, 199, 94, 0.28);
          border-radius: 3px;
        }
        .devhaven-inline-conflict {
          background: rgba(255, 149, 0, 0.28);
          border-radius: 3px;
        }
      `;
      document.head.appendChild(style);
      ready = true;
      hideStatus();
      postMessage("ready");
      if (lastPayload) {
        applyPayload(lastPayload);
      }
    })
    .catch((error) => {
      console.error(error);
      showStatus(`Monaco load failed (${MONACO_VERSION})`);
    });
})();
