use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, State};

use crate::agent_control::{
    emit_control_plane_changed, now_millis, AgentControlState, AgentSessionEventInput,
    ControlPlaneChangedPayload,
};

#[derive(Debug, Clone, Default)]
pub struct AgentLauncherState {
    inner: Arc<Mutex<HashMap<String, AgentRuntimeSession>>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentSpawnInput {
    pub provider: String,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub terminal_session_id: Option<String>,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentSpawnResult {
    pub agent_session_id: String,
    pub provider: String,
    pub status: String,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub terminal_session_id: Option<String>,
    pub cwd: String,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentStopResult {
    pub agent_session_id: String,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentRuntimeDiagnoseResult {
    pub registered_sessions: usize,
    pub running_sessions: usize,
    pub latest_updated_at: Option<i64>,
    pub control_plane_session_count: usize,
    pub unread_notification_count: usize,
}

#[derive(Debug, Clone)]
struct AgentRuntimeSession {
    agent_session_id: String,
    provider: String,
    project_path: String,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    terminal_session_id: Option<String>,
    cwd: String,
    status: String,
    updated_at: i64,
}

pub fn spawn_agent_runtime(
    launcher: &AgentLauncherState,
    control_state: &AgentControlState,
    input: AgentSpawnInput,
) -> Result<AgentSpawnResult, String> {
    let provider = normalize_required_text(input.provider, "provider")?;
    let project_path = normalize_required_text(input.project_path, "projectPath")?;
    let cwd = input.cwd.unwrap_or_else(|| project_path.clone());
    let agent_session_id = crate::agent_control::next_record_id();
    let updated_at = now_millis();

    let runtime = AgentRuntimeSession {
        agent_session_id: agent_session_id.clone(),
        provider: provider.clone(),
        project_path: project_path.clone(),
        workspace_id: input.workspace_id.clone(),
        pane_id: input.pane_id.clone(),
        surface_id: input.surface_id.clone(),
        terminal_session_id: input.terminal_session_id.clone(),
        cwd: cwd.clone(),
        status: "running".to_string(),
        updated_at,
    };

    launcher
        .inner
        .lock()
        .map_err(|_| "agent launcher 锁已损坏".to_string())?
        .insert(agent_session_id.clone(), runtime);

    control_state.upsert_agent_session_event(AgentSessionEventInput {
        agent_session_id: Some(agent_session_id.clone()),
        provider: provider.clone(),
        status: "running".to_string(),
        message: Some(format!("{provider} 已启动")),
        terminal_session_id: input.terminal_session_id.clone(),
        project_path: Some(project_path.clone()),
        workspace_id: input.workspace_id.clone(),
        pane_id: input.pane_id.clone(),
        surface_id: input.surface_id.clone(),
        cwd: Some(cwd.clone()),
    })?;

    Ok(AgentSpawnResult {
        agent_session_id,
        provider,
        status: "running".to_string(),
        project_path,
        workspace_id: input.workspace_id,
        pane_id: input.pane_id,
        surface_id: input.surface_id,
        terminal_session_id: input.terminal_session_id,
        cwd,
        updated_at,
    })
}

pub fn stop_agent_runtime(
    launcher: &AgentLauncherState,
    control_state: &AgentControlState,
    agent_session_id: &str,
    _force: bool,
) -> Result<AgentStopResult, String> {
    let mut sessions = launcher
        .inner
        .lock()
        .map_err(|_| "agent launcher 锁已损坏".to_string())?;
    let session = sessions
        .get_mut(agent_session_id)
        .ok_or_else(|| format!("运行中的 agent session 不存在: {agent_session_id}"))?;
    session.status = "stopped".to_string();
    session.updated_at = now_millis();

    control_state.upsert_agent_session_event(AgentSessionEventInput {
        agent_session_id: Some(session.agent_session_id.clone()),
        provider: session.provider.clone(),
        status: "stopped".to_string(),
        message: Some(format!("{} 已停止", session.provider)),
        terminal_session_id: session.terminal_session_id.clone(),
        project_path: Some(session.project_path.clone()),
        workspace_id: session.workspace_id.clone(),
        pane_id: session.pane_id.clone(),
        surface_id: session.surface_id.clone(),
        cwd: Some(session.cwd.clone()),
    })?;

    Ok(AgentStopResult {
        agent_session_id: session.agent_session_id.clone(),
        project_path: session.project_path.clone(),
        workspace_id: session.workspace_id.clone(),
        updated_at: session.updated_at,
    })
}

pub fn diagnose_agent_runtime(
    launcher: &AgentLauncherState,
    control_state: &AgentControlState,
) -> Result<AgentRuntimeDiagnoseResult, String> {
    let sessions = launcher
        .inner
        .lock()
        .map_err(|_| "agent launcher 锁已损坏".to_string())?;
    let registered_sessions = sessions.len();
    let running_sessions = sessions
        .values()
        .filter(|session| session.status == "running" || session.status == "waiting")
        .count();
    let latest_updated_at = sessions.values().map(|session| session.updated_at).max();
    drop(sessions);

    let control_plane = control_state.export_control_plane_file()?;
    let unread_notification_count = control_plane
        .notifications
        .values()
        .filter(|notification| !notification.read)
        .count();

    Ok(AgentRuntimeDiagnoseResult {
        registered_sessions,
        running_sessions,
        latest_updated_at,
        control_plane_session_count: control_plane.agent_sessions.len(),
        unread_notification_count,
    })
}

pub fn spawn_agent_command(
    app: &AppHandle,
    launcher: &AgentLauncherState,
    control_state: &AgentControlState,
    input: AgentSpawnInput,
) -> Result<AgentSpawnResult, String> {
    let result = spawn_agent_runtime(launcher, control_state, input)?;
    emit_control_plane_changed(
        app,
        ControlPlaneChangedPayload {
            project_path: result.project_path.clone(),
            workspace_id: result.workspace_id.clone(),
            notification_id: None,
            notification: None,
            reason: "agent-session".to_string(),
            updated_at: result.updated_at,
        },
    );
    Ok(result)
}

pub fn stop_agent_command(
    app: &AppHandle,
    launcher: &AgentLauncherState,
    control_state: &AgentControlState,
    agent_session_id: String,
    force: bool,
) -> Result<(), String> {
    let result = stop_agent_runtime(launcher, control_state, &agent_session_id, force)?;
    emit_control_plane_changed(
        app,
        ControlPlaneChangedPayload {
            project_path: result.project_path,
            workspace_id: result.workspace_id,
            notification_id: None,
            notification: None,
            reason: "agent-session".to_string(),
            updated_at: result.updated_at,
        },
    );
    Ok(())
}

pub fn diagnose_agent_runtime_command(
    launcher: State<'_, AgentLauncherState>,
    control_state: State<'_, AgentControlState>,
) -> Result<AgentRuntimeDiagnoseResult, String> {
    diagnose_agent_runtime(&launcher, &control_state)
}

fn normalize_required_text(value: String, field: &str) -> Result<String, String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() {
        return Err(format!("{field} 不能为空"));
    }
    Ok(trimmed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn agent_launcher_spawn_registers_runtime_session_and_control_plane_state() {
        let launcher = AgentLauncherState::default();
        let control_state = crate::agent_control::AgentControlState::default();

        let result = spawn_agent_runtime(
            &launcher,
            &control_state,
            AgentSpawnInput {
                provider: "codex".to_string(),
                project_path: "/repo".to_string(),
                workspace_id: Some("project-1".to_string()),
                pane_id: Some("pane-1".to_string()),
                surface_id: Some("pane-1".to_string()),
                terminal_session_id: None,
                cwd: Some("/repo".to_string()),
            },
        )
        .expect("spawn should work");

        assert_eq!(result.provider, "codex");
        assert_eq!(result.status, "running");
        let tree = control_state
            .export_control_plane_file()
            .expect("export should work");
        assert!(tree.agent_sessions.contains_key(&result.agent_session_id));
    }
}
