import { startTransition, useEffect, useRef, useState } from "react";
import { installSheetBridge, postMessage } from "./bridge";
import ConfigurationSidebar from "./components/ConfigurationSidebar";
import ConfigurationEditor from "./components/ConfigurationEditor";
import SheetFooter from "./components/SheetFooter";

function setTheme(theme) {
  document.documentElement.dataset.theme = theme === "dark" ? "dark" : "light";
}

function resolveSelectedConfiguration(payload) {
  if (!payload || !payload.configurations || payload.configurations.length === 0) {
    return null;
  }

  const selected = payload.configurations.find(
    (configuration) => configuration.id === payload.selectedConfigurationID
  );

  return selected || payload.configurations[0];
}

function buildSnapshot(payload) {
  if (!payload) {
    return null;
  }

  const selectedConfiguration = resolveSelectedConfiguration(payload);

  return {
    theme: payload.theme,
    projectPath: payload.projectPath,
    configurationCount: payload.configurations.length,
    selectedConfigurationID: payload.selectedConfigurationID,
    selectedName: selectedConfiguration?.name || null,
    selectedKind: selectedConfiguration?.kind || null,
    selectedRemoteFollow: selectedConfiguration?.remoteFollow ?? null,
    selectedCommandPreview: selectedConfiguration?.commandPreview || null,
    validationMessage: payload.validationMessage || null,
    isSaving: Boolean(payload.isSaving),
  };
}

export default function App() {
  const [payload, setPayload] = useState(null);
  const latestPayloadRef = useRef(null);

  function updateLocalPayload(updater) {
    setPayload((current) => {
      if (!current) {
        return current;
      }
      const nextPayload = updater(current);
      latestPayloadRef.current = nextPayload;
      setTheme(nextPayload?.theme);
      return nextPayload;
    });
  }

  function applyPayload(nextPayload) {
    latestPayloadRef.current = nextPayload;
    setTheme(nextPayload?.theme);
    startTransition(() => {
      setPayload(nextPayload);
    });
  }

  function selectConfiguration(configurationID) {
    updateLocalPayload((current) => ({
      ...current,
      selectedConfigurationID: configurationID,
      validationMessage: null,
    }));
    postMessage({ type: "selectConfiguration", configurationID });
  }

  function addConfiguration(kind) {
    postMessage({ type: "addConfiguration", kind });
  }

  function updateStringField(configurationID, field, value) {
    updateLocalPayload((current) => ({
      ...current,
      configurations: current.configurations.map((configuration) =>
        configuration.id === configurationID
          ? { ...configuration, [field]: value }
          : configuration
      ),
    }));

    postMessage({
      type: "updateStringField",
      configurationID,
      field,
      value,
    });
  }

  function updateBooleanField(configurationID, field, value) {
    const nextValue = Boolean(value);

    updateLocalPayload((current) => ({
      ...current,
      configurations: current.configurations.map((configuration) =>
        configuration.id === configurationID
          ? { ...configuration, [field]: nextValue }
          : configuration
      ),
    }));

    postMessage({
      type: "updateBooleanField",
      configurationID,
      field,
      value: nextValue,
    });
  }

  useEffect(() => {
    const cleanupBridge = installSheetBridge({
      applyPayload,
      debugSnapshot() {
        return buildSnapshot(latestPayloadRef.current);
      },
      debugSelect: selectConfiguration,
      debugAdd: addConfiguration,
      debugSetField: updateStringField,
      debugSetBool: updateBooleanField,
      debugRequestDuplicate(configurationID) {
        postMessage({ type: "duplicateConfiguration", configurationID });
      },
      debugRequestDelete(configurationID) {
        postMessage({ type: "deleteConfiguration", configurationID });
      },
      debugRequestCancel() {
        postMessage({ type: "cancelRequested" });
      },
      debugRequestSave() {
        postMessage({ type: "saveRequested" });
      },
    });

    postMessage({ type: "ready" });
    return cleanupBridge;
  }, []);

  useEffect(() => {
    latestPayloadRef.current = payload;
    setTheme(payload?.theme);
  }, [payload]);

  if (!payload) {
    return <div className="loading-state">正在准备运行配置…</div>;
  }

  return (
    <div className="sheet-page">
      <header className="sheet-header">
        <div className="header-copy">
          <h1>{payload.title}</h1>
          <p>{payload.subtitle}</p>
        </div>
        <div className="project-path mono" title={payload.projectPath}>
          {payload.projectPath}
        </div>
      </header>

      <div className="sheet-body">
        <ConfigurationSidebar
          payload={payload}
          onAddConfiguration={addConfiguration}
          onSelectConfiguration={selectConfiguration}
        />
        <ConfigurationEditor
          payload={payload}
          selectedConfiguration={resolveSelectedConfiguration(payload)}
          onUpdateStringField={updateStringField}
          onUpdateBooleanField={updateBooleanField}
          onRequestDuplicate={(configurationID) =>
            postMessage({ type: "duplicateConfiguration", configurationID })
          }
          onRequestDelete={(configurationID) =>
            postMessage({ type: "deleteConfiguration", configurationID })
          }
        />
      </div>

      <SheetFooter
        payload={payload}
        onCancel={() => postMessage({ type: "cancelRequested" })}
        onSave={() => postMessage({ type: "saveRequested" })}
      />
    </div>
  );
}
