const messageHandler =
  window.webkit?.messageHandlers?.devhavenRunConfigurationSheet;

export function postMessage(message) {
  messageHandler?.postMessage(message);
}

export function installSheetBridge(handlers) {
  const bridge = {
    applyPayload: handlers.applyPayload,
    debugSnapshot: handlers.debugSnapshot,
    debugSelect: handlers.debugSelect,
    debugAdd: handlers.debugAdd,
    debugSetField: handlers.debugSetField,
    debugSetBool: handlers.debugSetBool,
    debugRequestDuplicate: handlers.debugRequestDuplicate,
    debugRequestDelete: handlers.debugRequestDelete,
    debugRequestCancel: handlers.debugRequestCancel,
    debugRequestSave: handlers.debugRequestSave,
  };

  window.__devHavenRunConfigurationSheet = bridge;

  return function cleanup() {
    if (window.__devHavenRunConfigurationSheet === bridge) {
      delete window.__devHavenRunConfigurationSheet;
    }
  };
}
