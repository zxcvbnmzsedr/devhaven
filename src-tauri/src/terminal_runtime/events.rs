use serde::Serialize;
use tauri::{AppHandle, Emitter};

use super::types::QuickCommandState;
use crate::web_event_bus;

pub const QUICK_COMMAND_STATE_CHANGED_EVENT: &str = "quick-command-state-changed";

pub fn scoped_terminal_output_event(session_id: &str) -> String {
    format!("terminal-pane-output:{session_id}")
}

pub fn scoped_terminal_exit_event(session_id: &str) -> String {
    format!("terminal-pane-exit:{session_id}")
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalOutputEventPayload {
    pub session_id: String,
    pub data: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seq_start: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub seq_end: Option<u64>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalExitEventPayload {
    pub session_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<i32>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickCommandStateChangedPayload {
    pub job_id: String,
    pub script_id: String,
    pub project_id: String,
    pub project_path: String,
    pub state: QuickCommandState,
    pub updated_at: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub exit_code: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

pub fn emit_terminal_output(app: &AppHandle, payload: TerminalOutputEventPayload) {
    let scoped_event = scoped_terminal_output_event(&payload.session_id);
    if let Err(error) = app.emit(&scoped_event, payload.clone()) {
        log::warn!("发送 {scoped_event} 失败: {}", error);
    }
    web_event_bus::publish(&scoped_event, payload);
}

pub fn emit_terminal_exit(app: &AppHandle, payload: TerminalExitEventPayload) {
    let scoped_event = scoped_terminal_exit_event(&payload.session_id);
    if let Err(error) = app.emit(&scoped_event, payload.clone()) {
        log::warn!("发送 {scoped_event} 失败: {}", error);
    }
    web_event_bus::publish(&scoped_event, payload);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scoped_terminal_output_event_includes_session_id() {
        assert_eq!(scoped_terminal_output_event("abc"), "terminal-pane-output:abc");
        assert_eq!(scoped_terminal_exit_event("xyz"), "terminal-pane-exit:xyz");
    }
}
