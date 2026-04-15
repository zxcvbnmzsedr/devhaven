(function () {
  const MONACO_VERSION = "0.52.2";
  const MONACO_BASE_URL = new URL("./vendor/monaco/vs/", window.location.href);
  const MONACO_BASE = MONACO_BASE_URL.toString().replace(/\/$/, "");
  const MONACO_LOADER_URL = new URL("./vendor/monaco/vs/loader.js", window.location.href).toString();
  const MONACO_WORKER_URL = new URL("./vendor/monaco/vs/base/worker/workerMain.js", window.location.href).toString();

  const statusNode = document.getElementById("status");
  const diffRoot = document.getElementById("diff-root");
  const previousDifferenceButton = document.getElementById("previous-difference");
  const nextDifferenceButton = document.getElementById("next-difference");
  const differenceCounterNode = document.getElementById("difference-counter");
  const requestCounterNode = document.getElementById("request-counter");
  const compareModeChip = document.getElementById("compare-mode-chip");
  const languageChip = document.getElementById("language-chip");
  const editableChip = document.getElementById("editable-chip");
  const viewerModeSegment = document.getElementById("viewer-mode-segment");
  const saveButton = document.getElementById("save-button");
  const refreshButton = document.getElementById("refresh-button");
  const leftPaneHeader = document.getElementById("left-pane-header");
  const rightPaneHeader = document.getElementById("right-pane-header");
  const hideUnchangedRegionsEnabled = false;

  let editor;
  let originalModel;
  let modifiedModel;
  let ready = false;
  let lastPayload = null;
  let suppressModelEvents = false;
  let saveCommandInstalled = false;
  let interactionHandlersInstalled = false;
  let debounceTimer = null;
  let originalSelectionDecorations = [];
  let modifiedSelectionDecorations = [];
  let lastSelectedBlockId = null;
  let currentViewerMode = "sideBySide";
  let modelBindingCount = 0;

  function postMessage(type, payload) {
    const handler = window.webkit?.messageHandlers?.devhavenMonacoDiff;
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

    editor = monaco.editor.createDiffEditor(diffRoot, {
      automaticLayout: true,
      renderSideBySide: true,
      renderOverviewRuler: true,
      renderIndicators: true,
      originalEditable: false,
      readOnly: false,
      diffAlgorithm: "advanced",
      ignoreTrimWhitespace: false,
      smoothScrolling: true,
      cursorSmoothCaretAnimation: "on",
      scrollbar: {
        verticalScrollbarSize: 11,
        horizontalScrollbarSize: 11,
        alwaysConsumeMouseWheel: false
      },
      lineNumbersMinChars: 4,
      fontFamily: "SF Mono, Menlo, Monaco, Consolas, monospace",
      fontSize: 12.5,
      lineHeight: 20,
      minimap: { enabled: false },
      wordWrap: "off",
      stickyScroll: { enabled: false },
      scrollBeyondLastLine: false,
      padding: {
        top: 10,
        bottom: 18
      },
      guides: {
        indentation: true,
        highlightActiveIndentation: true
      },
      bracketPairColorization: { enabled: true },
      hideUnchangedRegions: {
        enabled: hideUnchangedRegionsEnabled,
        contextLineCount: 3,
        minimumLineCount: 5,
        revealLineCount: 10
      }
    });
  }

  function installStaticEventHandlers() {
    previousDifferenceButton.addEventListener("click", () => {
      postMessage("previousDifferenceRequested");
    });
    nextDifferenceButton.addEventListener("click", () => {
      postMessage("nextDifferenceRequested");
    });
    refreshButton.addEventListener("click", () => {
      postMessage("refreshRequested");
    });
    saveButton.addEventListener("click", () => {
      postMessage("saveRequested");
    });
  }

  function languageForPayload(payload) {
    return payload.language || "plaintext";
  }

  function createOrUpdateModels(monaco, payload) {
    const language = languageForPayload(payload);
    if (!originalModel) {
      originalModel = monaco.editor.createModel(payload.originalText, language);
    } else if (originalModel.getValue() !== payload.originalText) {
      originalModel.setValue(payload.originalText);
      monaco.editor.setModelLanguage(originalModel, language);
    } else {
      monaco.editor.setModelLanguage(originalModel, language);
    }

    if (!modifiedModel) {
      modifiedModel = monaco.editor.createModel(payload.modifiedText, language);
      modifiedModel.onDidChangeContent(() => {
        if (suppressModelEvents) return;
        window.clearTimeout(debounceTimer);
        debounceTimer = window.setTimeout(() => {
          postMessage("contentChanged", { text: modifiedModel.getValue() });
        }, 120);
      });
    } else if (modifiedModel.getValue() !== payload.modifiedText) {
      suppressModelEvents = true;
      modifiedModel.setValue(payload.modifiedText);
      suppressModelEvents = false;
      monaco.editor.setModelLanguage(modifiedModel, language);
    } else {
      monaco.editor.setModelLanguage(modifiedModel, language);
    }

    const currentModelPair = editor.getModel();
    const shouldBindModels = !currentModelPair
      || currentModelPair.original !== originalModel
      || currentModelPair.modified !== modifiedModel;

    if (shouldBindModels) {
      editor.setModel({
        original: originalModel,
        modified: modifiedModel
      });
      modelBindingCount += 1;
    }
  }

  function clearSelectedBlockDecorations() {
    if (!editor) return;
    const originalEditor = editor.getOriginalEditor();
    const modifiedEditor = editor.getModifiedEditor();
    originalSelectionDecorations = originalEditor.deltaDecorations(originalSelectionDecorations, []);
    modifiedSelectionDecorations = modifiedEditor.deltaDecorations(modifiedSelectionDecorations, []);
  }

  function clampLineNumber(model, lineNumber) {
    if (!model) return 1;
    return Math.min(Math.max(1, lineNumber), Math.max(1, model.getLineCount()));
  }

  function lineInBlock(startLine, lineCount, lineNumber) {
    if (lineCount <= 0) {
      return false;
    }
    const firstLine = startLine + 1;
    return lineNumber >= firstLine && lineNumber < firstLine + lineCount;
  }

  function findBlockById(blockId) {
    return (lastPayload?.blocks || []).find(item => item.id === blockId) || null;
  }

  function findBlockForLine(side, lineNumber) {
    const blocks = lastPayload?.blocks || [];
    return blocks.find((block) => {
      if (side === "original") {
        return lineInBlock(block.leftStartLine, block.leftLineCount, lineNumber);
      }
      return lineInBlock(block.rightStartLine, block.rightLineCount, lineNumber);
    }) || null;
  }

  function setSelectedBlock(blockId, options) {
    const monaco = window.monaco;
    const resolvedOptions = Object.assign({ reveal: true }, options || {});
    lastSelectedBlockId = blockId || null;

    if (!editor || !monaco || !lastPayload) {
      return;
    }

    clearSelectedBlockDecorations();
    if (!blockId) {
      return;
    }

    const block = findBlockById(blockId);
    if (!block) {
      return;
    }

    const originalEditor = editor.getOriginalEditor();
    const modifiedEditor = editor.getModifiedEditor();
    const leftStart = clampLineNumber(originalModel, block.leftStartLine + 1);
    const leftEnd = clampLineNumber(originalModel, block.leftStartLine + Math.max(block.leftLineCount, 1));
    const rightStart = clampLineNumber(modifiedModel, block.rightStartLine + 1);
    const rightEnd = clampLineNumber(modifiedModel, block.rightStartLine + Math.max(block.rightLineCount, 1));

    if (resolvedOptions.reveal) {
      originalEditor.revealLineInCenter(leftStart);
      modifiedEditor.revealLineInCenter(rightStart);
      originalEditor.setSelection(new monaco.Range(leftStart, 1, leftStart, 1));
      modifiedEditor.setSelection(new monaco.Range(rightStart, 1, rightStart, 1));
    }

    originalSelectionDecorations = originalEditor.deltaDecorations(
      originalSelectionDecorations,
      [{
        range: new monaco.Range(leftStart, 1, leftEnd, 1),
        options: {
          isWholeLine: true,
          className: "devhaven-selected-original",
          linesDecorationsClassName: "devhaven-selected-original-gutter",
          overviewRuler: {
            color: "rgba(255, 199, 94, 0.88)",
            position: monaco.editor.OverviewRulerLane.Full
          }
        }
      }]
    );

    modifiedSelectionDecorations = modifiedEditor.deltaDecorations(
      modifiedSelectionDecorations,
      [{
        range: new monaco.Range(rightStart, 1, rightEnd, 1),
        options: {
          isWholeLine: true,
          className: "devhaven-selected-modified",
          linesDecorationsClassName: "devhaven-selected-modified-gutter",
          overviewRuler: {
            color: "rgba(122, 162, 247, 0.92)",
            position: monaco.editor.OverviewRulerLane.Full
          }
        }
      }]
    );
  }

  function syncActiveBlockFromEditor(side, lineNumber) {
    const block = findBlockForLine(side, lineNumber);
    if (!block) {
      return;
    }
    const shouldNotify = lastSelectedBlockId !== block.id;
    setSelectedBlock(block.id, { reveal: false });
    if (shouldNotify) {
      postMessage("activeBlockChanged", { blockID: block.id });
    }
  }

  function installInteractionHandlers() {
    if (!editor || interactionHandlersInstalled) {
      return;
    }

    const originalEditor = editor.getOriginalEditor();
    const modifiedEditor = editor.getModifiedEditor();

    originalEditor.onDidChangeCursorPosition((event) => {
      syncActiveBlockFromEditor("original", event.position.lineNumber);
    });
    modifiedEditor.onDidChangeCursorPosition((event) => {
      syncActiveBlockFromEditor("modified", event.position.lineNumber);
    });
    originalEditor.onMouseDown((event) => {
      if (event.target.position) {
        syncActiveBlockFromEditor("original", event.target.position.lineNumber);
      }
    });
    modifiedEditor.onMouseDown((event) => {
      if (event.target.position) {
        syncActiveBlockFromEditor("modified", event.target.position.lineNumber);
      }
    });

    interactionHandlersInstalled = true;
  }

  function installCommands(monaco, payload) {
    const modifiedEditor = editor.getModifiedEditor();
    modifiedEditor.updateOptions({ readOnly: !payload.toolbar.isEditable });
    if (!saveCommandInstalled) {
      modifiedEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function () {
        postMessage("saveRequested");
      });
      saveCommandInstalled = true;
    }
  }

  function applyViewerMode(mode) {
    if (!editor) {
      return;
    }
    currentViewerMode = mode === "unified" ? "unified" : "sideBySide";
    editor.updateOptions({
      renderSideBySide: currentViewerMode !== "unified"
    });
  }

  function installTheme(monaco, theme) {
    monaco.editor.defineTheme("devhaven-dark", {
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
        "editorGutter.modifiedBackground": "#e2b71466",
        "editorGutter.addedBackground": "#57c57caa",
        "editorGutter.deletedBackground": "#ff6b81aa",
        "diffEditor.diagonalFill": "#00000000",
        "diffEditor.insertedTextBackground": "#2ea04333",
        "diffEditor.removedTextBackground": "#f8514933",
        "diffEditor.insertedLineBackground": "#2ea04320",
        "diffEditor.removedLineBackground": "#f8514920",
        "diffEditor.border": "#00000000"
      }
    });

    monaco.editor.defineTheme("devhaven-light", {
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
        "editorGutter.modifiedBackground": "#d8a10077",
        "editorGutter.addedBackground": "#1f9d5b88",
        "editorGutter.deletedBackground": "#cf3a4c88",
        "diffEditor.diagonalFill": "#00000000",
        "diffEditor.insertedTextBackground": "#1f883d24",
        "diffEditor.removedTextBackground": "#cf222e24",
        "diffEditor.insertedLineBackground": "#1f883d15",
        "diffEditor.removedLineBackground": "#cf222e15",
        "diffEditor.border": "#00000000"
      }
    });

    document.documentElement.dataset.theme = theme === "vs" ? "light" : "dark";
    monaco.editor.setTheme(theme === "vs" ? "devhaven-light" : "devhaven-dark");
  }

  function escapeHTML(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function renderPaneHeader(node, pane, role) {
    const detailHTML = pane.detailText
      ? `<div class="pane-detail">${escapeHTML(pane.detailText)}</div>`
      : "";
    const renameHTML = pane.renamedFrom
      ? `<div class="pane-rename">Renamed from ${escapeHTML(pane.renamedFrom)}</div>`
      : "";
    const pathHTML = pane.path
      ? `<div class="pane-path">${escapeHTML(pane.path)}</div>`
      : "";

    node.innerHTML = `
      <span class="pane-badge ${role}">${escapeHTML(pane.badge)}</span>
      <div class="pane-text">
        <div class="pane-file-name">${escapeHTML(pane.fileName)}</div>
        ${pathHTML}
        ${detailHTML}
        ${renameHTML}
      </div>
    `;
  }

  function renderViewerModeSegment(toolbar) {
    viewerModeSegment.innerHTML = "";
    (toolbar.availableViewerModes || []).forEach((mode) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "viewer-mode-option" + (toolbar.viewerMode === mode ? " active" : "");
      button.textContent = mode === "unified" ? "统一" : "并排";
      button.addEventListener("click", () => {
        if (toolbar.viewerMode !== mode) {
          postMessage("viewerModeChanged", { mode });
        }
      });
      viewerModeSegment.appendChild(button);
    });
  }

  function renderToolbar(payload) {
    const toolbar = payload.toolbar;
    differenceCounterNode.textContent = `${toolbar.currentDifferenceIndex}/${toolbar.totalDifferences}`;
    requestCounterNode.textContent = `${toolbar.currentRequestIndex}/${toolbar.totalRequests}`;
    compareModeChip.textContent = toolbar.compareModeLabel;
    languageChip.textContent = toolbar.languageLabel;
    editableChip.textContent = toolbar.isEditable ? "可编辑" : "只读";
    previousDifferenceButton.disabled = !toolbar.canGoPrevious;
    nextDifferenceButton.disabled = !toolbar.canGoNext;
    saveButton.hidden = !toolbar.isEditable;
    renderViewerModeSegment(toolbar);
  }

  async function applyPayload(payload) {
    lastPayload = payload;
    if (!ready) return;
    const monaco = window.monaco;
    installTheme(monaco, payload.theme);
    renderToolbar(payload);
    applyViewerMode(payload.toolbar.viewerMode);
    renderPaneHeader(leftPaneHeader, payload.leftPane, "left");
    renderPaneHeader(rightPaneHeader, payload.rightPane, "right");
    createOrUpdateModels(monaco, payload);
    installCommands(monaco, payload);
    installInteractionHandlers();
    setSelectedBlock(lastSelectedBlockId, { reveal: false });
  }

  window.__devHavenMonaco = {
    applyPayload,
    setSelectedBlock(blockId) {
      setSelectedBlock(blockId, { reveal: true });
    },
    focusModifiedEditor() {
      editor?.getModifiedEditor()?.focus();
    },
    debugSetModifiedText(text) {
      modifiedModel?.setValue(text);
    },
    debugRequestSave() {
      postMessage("saveRequested");
    },
    debugSelectLine(side, lineNumber) {
      const monaco = window.monaco;
      if (!editor || !monaco) {
        return;
      }
      const targetEditor = side === "original"
        ? editor.getOriginalEditor()
        : editor.getModifiedEditor();
      const targetModel = side === "original" ? originalModel : modifiedModel;
      const resolvedLineNumber = clampLineNumber(targetModel, lineNumber);
      targetEditor.setSelection(new monaco.Range(resolvedLineNumber, 1, resolvedLineNumber, 1));
      syncActiveBlockFromEditor(side === "original" ? "original" : "modified", resolvedLineNumber);
    },
    debugTriggerToolbarAction(action, mode) {
      switch (action) {
        case "previous":
          postMessage("previousDifferenceRequested");
          break;
        case "next":
          postMessage("nextDifferenceRequested");
          break;
        case "refresh":
          postMessage("refreshRequested");
          break;
        case "viewerMode":
          if (mode) {
            postMessage("viewerModeChanged", { mode });
          }
          break;
        default:
          break;
      }
    },
    debugSnapshot() {
      const monaco = window.monaco;
      return {
        hasEditor: Boolean(editor),
        originalText: originalModel ? originalModel.getValue() : null,
        modifiedText: modifiedModel ? modifiedModel.getValue() : null,
        readOnly: editor && monaco
          ? editor.getModifiedEditor().getOption(monaco.editor.EditorOption.readOnly)
          : null,
        selectedBlockId: lastSelectedBlockId,
        viewerMode: currentViewerMode,
        modelBindingCount,
        hideUnchangedRegionsEnabled
      };
    }
  };

  installStaticEventHandlers();

  loadMonaco()
    .then((monaco) => {
      ensureEditor(monaco);
      const style = document.createElement("style");
      style.textContent = `
        .devhaven-selected-original {
          background: linear-gradient(90deg, rgba(255, 199, 94, 0.18), rgba(255, 199, 94, 0.08));
        }
        .devhaven-selected-modified {
          background: linear-gradient(90deg, rgba(122, 162, 247, 0.18), rgba(122, 162, 247, 0.08));
        }
        .devhaven-selected-original-gutter {
          border-left: 3px solid rgba(255, 199, 94, 0.95);
        }
        .devhaven-selected-modified-gutter {
          border-left: 3px solid rgba(122, 162, 247, 0.98);
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
