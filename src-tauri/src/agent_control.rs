use std::collections::HashMap;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter};
use uuid::Uuid;

use crate::web_event_bus;

pub const DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT: &str = "devhaven-control-plane-changed";

#[derive(Debug, Clone, Default)]
pub struct AgentControlState {
    inner: Arc<Mutex<ControlPlaneRegistry>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TerminalBindingRecord {
    pub terminal_session_id: String,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub cwd: String,
    pub window_label: Option<String>,
    pub updated_at: i64,
    pub exited: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionRecord {
    pub agent_session_id: String,
    pub provider: String,
    pub status: String,
    pub message: Option<String>,
    pub terminal_session_id: Option<String>,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub cwd: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NotificationRecord {
    pub id: String,
    pub message: String,
    pub read: bool,
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub terminal_session_id: Option<String>,
    pub agent_session_id: Option<String>,
    pub created_at: i64,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ControlPlaneSurfaceTreeNode {
    pub pane_id: String,
    pub surface_id: String,
    pub terminal_session_id: Option<String>,
    pub unread_count: usize,
    pub agent_session: Option<AgentSessionRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ControlPlaneTree {
    pub workspace_id: String,
    pub project_path: String,
    pub panes: Vec<ControlPlaneSurfaceTreeNode>,
    pub notifications: Vec<NotificationRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ControlPlaneIdentifyResult {
    pub project_path: String,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub terminal_session_id: Option<String>,
    pub agent_session_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentSessionEventInput {
    pub agent_session_id: Option<String>,
    pub provider: String,
    pub status: String,
    pub message: Option<String>,
    pub terminal_session_id: Option<String>,
    pub project_path: Option<String>,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub cwd: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NotificationInput {
    pub message: String,
    pub terminal_session_id: Option<String>,
    pub agent_session_id: Option<String>,
    pub project_path: Option<String>,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum AgentSessionStatus {
    Started,
    Running,
    Waiting,
    Failed,
    Completed,
    Stopped,
}

impl AgentSessionStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Started => "started",
            Self::Running => "running",
            Self::Waiting => "waiting",
            Self::Failed => "failed",
            Self::Completed => "completed",
            Self::Stopped => "stopped",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DevHavenIdentifyRequest {
    pub terminal_session_id: Option<String>,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DevHavenTreeRequest {
    pub project_path: Option<String>,
    pub workspace_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DevHavenNotifyRequest {
    pub terminal_session_id: Option<String>,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub agent_session_id: Option<String>,
    pub project_path: Option<String>,
    pub title: Option<String>,
    pub message: String,
    pub level: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct DevHavenAgentSessionEventRequest {
    pub agent_session_id: Option<String>,
    pub terminal_session_id: Option<String>,
    pub workspace_id: Option<String>,
    pub pane_id: Option<String>,
    pub surface_id: Option<String>,
    pub provider: String,
    pub status: AgentSessionStatus,
    pub project_path: Option<String>,
    pub cwd: Option<String>,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct NotificationMutationRequest {
    pub notification_id: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ControlPlaneChangedPayload {
    pub project_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub workspace_id: Option<String>,
    pub reason: String,
    pub updated_at: i64,
}

pub const AGENT_CONTROL_PLANE_FILE_VERSION: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct AgentControlPlaneFile {
    pub version: u32,
    pub bindings: HashMap<String, TerminalBindingRecord>,
    pub agent_sessions: HashMap<String, AgentSessionRecord>,
    pub notifications: HashMap<String, NotificationRecord>,
}

impl Default for AgentControlPlaneFile {
    fn default() -> Self {
        Self {
            version: AGENT_CONTROL_PLANE_FILE_VERSION,
            bindings: HashMap::new(),
            agent_sessions: HashMap::new(),
            notifications: HashMap::new(),
        }
    }
}

#[derive(Debug, Default, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ControlPlaneRegistry {
    terminal_bindings: HashMap<String, TerminalBindingRecord>,
    agent_sessions: HashMap<String, AgentSessionRecord>,
    notifications: HashMap<String, NotificationRecord>,
}

#[derive(Debug, Clone)]
struct ResolvedContext {
    project_path: String,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    terminal_session_id: Option<String>,
    cwd: Option<String>,
}

impl AgentControlState {
    pub fn register_terminal_binding(&self, binding: TerminalBindingRecord) -> Result<(), String> {
        let mut registry = self.inner.lock().map_err(|_| "control plane 锁已损坏".to_string())?;
        registry.register_terminal_binding(binding);
        Ok(())
    }

    pub fn mark_terminal_session_exited(&self, terminal_session_id: &str) -> Result<(), String> {
        let mut registry = self.inner.lock().map_err(|_| "control plane 锁已损坏".to_string())?;
        registry.mark_terminal_session_exited(terminal_session_id);
        Ok(())
    }

    pub fn upsert_agent_session_event(&self, input: AgentSessionEventInput) -> Result<AgentSessionRecord, String> {
        let mut registry = self.inner.lock().map_err(|_| "control plane 锁已损坏".to_string())?;
        registry.upsert_agent_session_event(input)
    }

    pub fn push_notification(&self, input: NotificationInput) -> Result<NotificationRecord, String> {
        let mut registry = self.inner.lock().map_err(|_| "control plane 锁已损坏".to_string())?;
        registry.push_notification(input)
    }

    pub fn mark_notification_read(&self, notification_id: &str, read: bool) -> Result<NotificationRecord, String> {
        let mut registry = self.inner.lock().map_err(|_| "control plane 锁已损坏".to_string())?;
        registry.mark_notification_read(notification_id, read)
    }

    pub fn export_control_plane_file(&self) -> Result<AgentControlPlaneFile, String> {
        let registry = self
            .inner
            .lock()
            .map_err(|_| "control plane 锁已损坏".to_string())?;
        Ok(registry.to_file())
    }

    pub fn replace_from_control_plane_file(
        &self,
        file: AgentControlPlaneFile,
    ) -> Result<(), String> {
        let mut registry = self
            .inner
            .lock()
            .map_err(|_| "control plane 锁已损坏".to_string())?;
        *registry = ControlPlaneRegistry::from_file(file);
        Ok(())
    }

}

pub fn identify_control_plane(
    state: tauri::State<'_, AgentControlState>,
    request: DevHavenIdentifyRequest,
) -> Result<ControlPlaneIdentifyResult, String> {
    let registry = state
        .inner
        .lock()
        .map_err(|_| "control plane 锁已损坏".to_string())?;
    registry
        .identify_request(&request)
        .ok_or_else(|| "未找到匹配的控制面上下文".to_string())
}

pub fn tree_control_plane(
    state: tauri::State<'_, AgentControlState>,
    request: DevHavenTreeRequest,
) -> Result<Option<ControlPlaneTree>, String> {
    let registry = state
        .inner
        .lock()
        .map_err(|_| "control plane 锁已损坏".to_string())?;
    let project_path = request
        .project_path
        .or_else(|| request.workspace_id.as_deref().and_then(|value| registry.find_project_path_for_workspace(value)))
        .ok_or_else(|| "缺少 project_path / workspace_id 上下文".to_string())?;
    registry.tree(&project_path, request.workspace_id.as_deref())
}

pub fn notify_control_plane(
    app: &AppHandle,
    state: tauri::State<'_, AgentControlState>,
    request: DevHavenNotifyRequest,
) -> Result<NotificationRecord, String> {
    let message = match normalize_optional_text(request.title.clone()) {
        Some(title) => format!("{title}：{}", request.message),
        None => request.message,
    };
    let record = state.push_notification(NotificationInput {
        message,
        terminal_session_id: request.terminal_session_id,
        agent_session_id: request.agent_session_id,
        project_path: request.project_path,
        workspace_id: request.workspace_id,
        pane_id: request.pane_id,
        surface_id: request.surface_id,
    })?;
    emit_control_plane_changed(
        app,
        ControlPlaneChangedPayload {
            project_path: record.project_path.clone(),
            workspace_id: record.workspace_id.clone(),
            reason: "notification".to_string(),
            updated_at: record.updated_at,
        },
    );
    Ok(record)
}

pub fn upsert_agent_session_event(
    app: &AppHandle,
    state: tauri::State<'_, AgentControlState>,
    request: DevHavenAgentSessionEventRequest,
) -> Result<AgentSessionRecord, String> {
    let record = state.upsert_agent_session_event(AgentSessionEventInput {
        agent_session_id: request.agent_session_id,
        provider: request.provider,
        status: request.status.as_str().to_string(),
        message: request.message,
        terminal_session_id: request.terminal_session_id,
        project_path: request.project_path,
        workspace_id: request.workspace_id,
        pane_id: request.pane_id,
        surface_id: request.surface_id,
        cwd: request.cwd,
    })?;
    emit_control_plane_changed(
        app,
        ControlPlaneChangedPayload {
            project_path: record.project_path.clone(),
            workspace_id: record.workspace_id.clone(),
            reason: "agent-session".to_string(),
            updated_at: record.updated_at,
        },
    );
    Ok(record)
}

pub fn mark_notification_read_state(
    app: &AppHandle,
    state: tauri::State<'_, AgentControlState>,
    request: NotificationMutationRequest,
    read: bool,
) -> Result<(), String> {
    let record = state.mark_notification_read(&request.notification_id, read)?;
    emit_control_plane_changed(
        app,
        ControlPlaneChangedPayload {
            project_path: record.project_path,
            workspace_id: record.workspace_id,
            reason: if read {
                "notification-read".to_string()
            } else {
                "notification-unread".to_string()
            },
            updated_at: record.updated_at,
        },
    );
    Ok(())
}

impl ControlPlaneRegistry {
    pub fn to_file(&self) -> AgentControlPlaneFile {
        AgentControlPlaneFile {
            version: AGENT_CONTROL_PLANE_FILE_VERSION,
            bindings: self.terminal_bindings.clone(),
            agent_sessions: self.agent_sessions.clone(),
            notifications: self.notifications.clone(),
        }
    }

    pub fn from_file(file: AgentControlPlaneFile) -> Self {
        Self {
            terminal_bindings: file.bindings,
            agent_sessions: file.agent_sessions,
            notifications: file.notifications,
        }
    }

    pub fn register_terminal_binding(&mut self, mut binding: TerminalBindingRecord) {
        binding.updated_at = now_millis();
        binding.exited = false;
        self.terminal_bindings
            .insert(binding.terminal_session_id.clone(), binding);
    }

    pub fn mark_terminal_session_exited(&mut self, terminal_session_id: &str) {
        if let Some(binding) = self.terminal_bindings.get_mut(terminal_session_id) {
            binding.exited = true;
            binding.updated_at = now_millis();
        }
    }

    pub fn upsert_agent_session_event(&mut self, input: AgentSessionEventInput) -> Result<AgentSessionRecord, String> {
        let requested_agent_session_id = input.agent_session_id.clone();
        let agent_session_id = requested_agent_session_id.clone().unwrap_or_else(next_record_id);
        let now = now_millis();
        let status = normalize_agent_status(&input.status)?;
        let context = self.resolve_event_context(
            input.terminal_session_id.as_deref(),
            input.project_path,
            input.workspace_id,
            input.pane_id,
            input.surface_id,
            input.cwd,
            requested_agent_session_id.as_deref(),
        )?;

        if let Some(existing) = self.agent_sessions.get_mut(&agent_session_id) {
            existing.provider = input.provider;
            existing.status = status;
            existing.message = normalize_optional_text(input.message).or(existing.message.clone());
            existing.terminal_session_id = context.terminal_session_id.or(existing.terminal_session_id.clone());
            existing.project_path = context.project_path;
            existing.workspace_id = context.workspace_id;
            existing.pane_id = context.pane_id;
            existing.surface_id = context.surface_id;
            existing.cwd = context.cwd.or(existing.cwd.clone());
            existing.updated_at = now;
            return Ok(existing.clone());
        }

        let record = AgentSessionRecord {
            agent_session_id: agent_session_id.clone(),
            provider: input.provider,
            status,
            message: normalize_optional_text(input.message),
            terminal_session_id: context.terminal_session_id,
            project_path: context.project_path,
            workspace_id: context.workspace_id,
            pane_id: context.pane_id,
            surface_id: context.surface_id,
            cwd: context.cwd,
            created_at: now,
            updated_at: now,
        };
        self.agent_sessions.insert(agent_session_id, record.clone());
        Ok(record)
    }

    pub fn push_notification(&mut self, input: NotificationInput) -> Result<NotificationRecord, String> {
        let message = normalize_required_text(input.message, "message")?;
        let now = now_millis();
        let context = self.resolve_event_context(
            input.terminal_session_id.as_deref(),
            input.project_path,
            input.workspace_id,
            input.pane_id,
            input.surface_id,
            None,
            input.agent_session_id.as_deref(),
        )?;

        let record = NotificationRecord {
            id: next_record_id(),
            message,
            read: false,
            project_path: context.project_path,
            workspace_id: context.workspace_id,
            pane_id: context.pane_id,
            surface_id: context.surface_id,
            terminal_session_id: context.terminal_session_id,
            agent_session_id: input.agent_session_id,
            created_at: now,
            updated_at: now,
        };
        self.notifications.insert(record.id.clone(), record.clone());
        Ok(record)
    }

    pub fn mark_notification_read(&mut self, notification_id: &str, read: bool) -> Result<NotificationRecord, String> {
        let notification = self
            .notifications
            .get_mut(notification_id)
            .ok_or_else(|| format!("通知不存在: {}", notification_id))?;
        notification.read = read;
        notification.updated_at = now_millis();
        Ok(notification.clone())
    }

    pub fn identify(&self, terminal_session_id: Option<&str>) -> Option<ControlPlaneIdentifyResult> {
        let session_id = terminal_session_id?;
        let binding = self.terminal_bindings.get(session_id)?;
        let latest_agent = self.latest_agent_for_binding(binding).map(|value| value.agent_session_id.clone());
        Some(ControlPlaneIdentifyResult {
            project_path: binding.project_path.clone(),
            workspace_id: binding.workspace_id.clone(),
            pane_id: binding.pane_id.clone(),
            surface_id: binding.surface_id.clone(),
            terminal_session_id: Some(binding.terminal_session_id.clone()),
            agent_session_id: latest_agent,
        })
    }

    pub fn identify_request(
        &self,
        request: &DevHavenIdentifyRequest,
    ) -> Option<ControlPlaneIdentifyResult> {
        if request.terminal_session_id.is_some() {
            return self.identify(request.terminal_session_id.as_deref());
        }

        let binding = self.terminal_bindings.values().find(|binding| {
            request
                .workspace_id
                .as_ref()
                .is_none_or(|value| binding.workspace_id.as_deref() == Some(value.as_str()))
                && request
                    .pane_id
                    .as_ref()
                    .is_none_or(|value| binding.pane_id.as_deref() == Some(value.as_str()))
                && request
                    .surface_id
                    .as_ref()
                    .is_none_or(|value| binding.surface_id.as_deref() == Some(value.as_str()))
        })?;
        let latest_agent = self.latest_agent_for_binding(binding).map(|value| value.agent_session_id.clone());
        Some(ControlPlaneIdentifyResult {
            project_path: binding.project_path.clone(),
            workspace_id: binding.workspace_id.clone(),
            pane_id: binding.pane_id.clone(),
            surface_id: binding.surface_id.clone(),
            terminal_session_id: Some(binding.terminal_session_id.clone()),
            agent_session_id: latest_agent,
        })
    }

    pub fn tree(&self, project_path: &str, workspace_id: Option<&str>) -> Result<Option<ControlPlaneTree>, String> {
        let workspace_id = workspace_id
            .map(|value| value.to_string())
            .or_else(|| self.find_workspace_id_for_project(project_path));

        let has_any_record = self
            .terminal_bindings
            .values()
            .any(|binding| binding.project_path == project_path)
            || self
                .agent_sessions
                .values()
                .any(|agent| agent.project_path == project_path)
            || self
                .notifications
                .values()
                .any(|notification| notification.project_path == project_path);

        if !has_any_record {
            return Ok(None);
        }

        let workspace_id = workspace_id.unwrap_or_else(|| project_path.to_string());
        let mut surfaces: Vec<ControlPlaneSurfaceTreeNode> = self
            .surface_bindings_for_workspace(project_path, &workspace_id)
            .into_iter()
            .map(|binding| {
                let unread_count = self
                    .notifications
                    .values()
                    .filter(|notification| {
                        !notification.read && notification_matches_binding(notification, binding)
                    })
                    .count();
                let agent_session = self.latest_agent_for_binding(binding).cloned();
                ControlPlaneSurfaceTreeNode {
                    pane_id: binding.pane_id.clone().unwrap_or_else(|| binding.terminal_session_id.clone()),
                    surface_id: binding.surface_id.clone().unwrap_or_else(|| binding.terminal_session_id.clone()),
                    terminal_session_id: Some(binding.terminal_session_id.clone()),
                    unread_count,
                    agent_session,
                }
            })
            .collect();
        surfaces.sort_by(|left, right| left.pane_id.cmp(&right.pane_id));

        let mut notifications: Vec<NotificationRecord> = self
            .notifications
            .values()
            .filter(|notification| {
                notification.project_path == project_path
                    && notification.workspace_id.as_deref().unwrap_or(project_path) == workspace_id
            })
            .cloned()
            .collect();
        notifications.sort_by(|left, right| left.created_at.cmp(&right.created_at));

        Ok(Some(ControlPlaneTree {
            workspace_id,
            project_path: project_path.to_string(),
            panes: surfaces,
            notifications,
        }))
    }

    fn resolve_event_context(
        &self,
        terminal_session_id: Option<&str>,
        project_path: Option<String>,
        workspace_id: Option<String>,
        pane_id: Option<String>,
        surface_id: Option<String>,
        cwd: Option<String>,
        agent_session_id: Option<&str>,
    ) -> Result<ResolvedContext, String> {
        if let Some(agent_session_id) = agent_session_id {
            if let Some(agent) = self.agent_sessions.get(agent_session_id) {
                return Ok(self.normalize_context(ResolvedContext {
                    project_path: agent.project_path.clone(),
                    workspace_id: agent.workspace_id.clone(),
                    pane_id: pane_id.or_else(|| agent.pane_id.clone()),
                    surface_id: surface_id.or_else(|| agent.surface_id.clone()),
                    terminal_session_id: terminal_session_id
                        .map(|value| value.to_string())
                        .or_else(|| agent.terminal_session_id.clone()),
                    cwd: cwd.or_else(|| agent.cwd.clone()),
                }));
            }
        }

        if let Some(terminal_session_id) = terminal_session_id {
            if let Some(binding) = self.terminal_bindings.get(terminal_session_id) {
                return Ok(self.normalize_context(ResolvedContext {
                    project_path: project_path.unwrap_or_else(|| binding.project_path.clone()),
                    workspace_id: workspace_id.or_else(|| binding.workspace_id.clone()),
                    pane_id: pane_id.or_else(|| binding.pane_id.clone()),
                    surface_id: surface_id.or_else(|| binding.surface_id.clone()),
                    terminal_session_id: Some(terminal_session_id.to_string()),
                    cwd: cwd.or_else(|| Some(binding.cwd.clone())),
                }));
            }
        }

        let project_path = project_path.ok_or_else(|| "缺少 project_path / terminal_session_id 上下文".to_string())?;
        Ok(self.normalize_context(ResolvedContext {
            project_path,
            workspace_id,
            pane_id,
            surface_id,
            terminal_session_id: terminal_session_id.map(|value| value.to_string()),
            cwd,
        }))
    }

    fn normalize_context(&self, mut context: ResolvedContext) -> ResolvedContext {
        let has_matching_surface = self.terminal_bindings.values().any(|binding| {
            binding.project_path == context.project_path
                && binding.workspace_id == context.workspace_id
                && binding.pane_id == context.pane_id
                && binding.surface_id == context.surface_id
        });
        if context.pane_id.is_some() && context.surface_id.is_some() && !has_matching_surface {
            context.pane_id = None;
            context.surface_id = None;
        }
        context
    }

    fn latest_agent_for_binding(&self, binding: &TerminalBindingRecord) -> Option<&AgentSessionRecord> {
        self.agent_sessions
            .values()
            .filter(|agent| {
                agent.project_path == binding.project_path
                    && agent.workspace_id == binding.workspace_id
                    && (agent.terminal_session_id.as_deref() == Some(binding.terminal_session_id.as_str())
                        || (binding.surface_id.is_some() && agent.surface_id == binding.surface_id)
                        || (binding.pane_id.is_some() && agent.pane_id == binding.pane_id))
            })
            .max_by_key(|agent| agent.updated_at)
    }

    fn find_workspace_id_for_project(&self, project_path: &str) -> Option<String> {
        self.terminal_bindings
            .values()
            .find(|binding| binding.project_path == project_path)
            .and_then(|binding| binding.workspace_id.clone())
            .or_else(|| {
                self.agent_sessions
                    .values()
                    .find(|agent| agent.project_path == project_path)
                    .and_then(|agent| agent.workspace_id.clone())
            })
            .or_else(|| {
                self.notifications
                    .values()
                    .find(|notification| notification.project_path == project_path)
                    .and_then(|notification| notification.workspace_id.clone())
            })
    }

    fn find_project_path_for_workspace(&self, workspace_id: &str) -> Option<String> {
        self.terminal_bindings
            .values()
            .find(|binding| binding.workspace_id.as_deref() == Some(workspace_id))
            .map(|binding| binding.project_path.clone())
            .or_else(|| {
                self.agent_sessions
                    .values()
                    .find(|agent| agent.workspace_id.as_deref() == Some(workspace_id))
                    .map(|agent| agent.project_path.clone())
            })
            .or_else(|| {
                self.notifications
                    .values()
                    .find(|notification| notification.workspace_id.as_deref() == Some(workspace_id))
                    .map(|notification| notification.project_path.clone())
            })
    }

    fn surface_bindings_for_workspace(
        &self,
        project_path: &str,
        workspace_id: &str,
    ) -> Vec<&TerminalBindingRecord> {
        let mut bindings: Vec<&TerminalBindingRecord> = self
            .terminal_bindings
            .values()
            .filter(|binding| {
                !binding.exited
                    && binding.project_path == project_path
                    && binding.workspace_id.as_deref().unwrap_or(project_path) == workspace_id
            })
            .collect();
        bindings.sort_by_key(|binding| binding.updated_at);
        bindings
    }
}

fn notification_matches_binding(notification: &NotificationRecord, binding: &TerminalBindingRecord) -> bool {
    if notification.terminal_session_id.as_deref() == Some(binding.terminal_session_id.as_str()) {
        return true;
    }
    if binding.surface_id.is_some() && notification.surface_id == binding.surface_id {
        return true;
    }
    if binding.pane_id.is_some() && notification.pane_id == binding.pane_id {
        return true;
    }
    false
}

fn normalize_required_text(value: String, field: &str) -> Result<String, String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() {
        return Err(format!("{} 不能为空", field));
    }
    Ok(trimmed)
}

fn normalize_optional_text(value: Option<String>) -> Option<String> {
    value.and_then(|item| {
        let trimmed = item.trim().to_string();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    })
}

fn normalize_agent_status(raw: &str) -> Result<String, String> {
    let status = raw.trim().to_ascii_lowercase();
    let normalized = match status.as_str() {
        "started" => "running",
        "running" | "waiting" | "failed" | "completed" | "stopped" => status.as_str(),
        other => {
            return Err(format!("不支持的 agent status: {}", other));
        }
    };
    Ok(normalized.to_string())
}

pub fn emit_control_plane_changed(app: &AppHandle, payload: ControlPlaneChangedPayload) {
    if let Err(error) = app.emit(DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT, payload.clone()) {
        log::warn!("发送 {} 失败: {}", DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT, error);
    }
    web_event_bus::publish(DEVHAVEN_CONTROL_PLANE_CHANGED_EVENT, &payload);
}

pub fn now_millis() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

pub fn next_record_id() -> String {
    Uuid::new_v4().to_string()
}

pub fn build_terminal_control_env(binding: &TerminalBindingRecord) -> Vec<(String, String)> {
    let mut env = vec![
        (
            "DEVHAVEN_TERMINAL_SESSION_ID".to_string(),
            binding.terminal_session_id.clone(),
        ),
        ("DEVHAVEN_PROJECT_PATH".to_string(), binding.project_path.clone()),
        ("DEVHAVEN_CONTROL_MODE".to_string(), "command".to_string()),
    ];
    if let Some(workspace_id) = binding.workspace_id.as_ref() {
        env.push(("DEVHAVEN_WORKSPACE_ID".to_string(), workspace_id.clone()));
    }
    if let Some(pane_id) = binding.pane_id.as_ref() {
        env.push(("DEVHAVEN_PANE_ID".to_string(), pane_id.clone()));
    }
    if let Some(surface_id) = binding.surface_id.as_ref() {
        env.push(("DEVHAVEN_SURFACE_ID".to_string(), surface_id.clone()));
    }
    env
}

#[cfg(test)]
mod tests {
    use super::*;

    fn binding(session: &str) -> TerminalBindingRecord {
        TerminalBindingRecord {
            terminal_session_id: session.to_string(),
            project_path: "/repo".to_string(),
            workspace_id: Some("project-1".to_string()),
            pane_id: Some("pane-1".to_string()),
            surface_id: Some("pane-1".to_string()),
            cwd: "/repo".to_string(),
            window_label: Some("terminal-main".to_string()),
            updated_at: 10,
            exited: false,
        }
    }

    #[test]
    fn agent_control_registry_tracks_terminal_binding_and_agent_notifications() {
        let mut registry = ControlPlaneRegistry::default();
        registry.register_terminal_binding(binding("session-1"));

        let agent = registry
            .upsert_agent_session_event(AgentSessionEventInput {
                agent_session_id: Some("agent-1".to_string()),
                provider: "claude-code".to_string(),
                status: "waiting".to_string(),
                message: Some("等待输入".to_string()),
                terminal_session_id: Some("session-1".to_string()),
                project_path: None,
                workspace_id: None,
                pane_id: None,
                surface_id: None,
                cwd: None,
            })
            .expect("should upsert agent session");
        assert_eq!(agent.workspace_id.as_deref(), Some("project-1"));

        let notification = registry
            .push_notification(NotificationInput {
                message: "需要确认".to_string(),
                terminal_session_id: Some("session-1".to_string()),
                agent_session_id: Some(agent.agent_session_id.clone()),
                project_path: None,
                workspace_id: None,
                pane_id: None,
                surface_id: None,
            })
            .expect("should create notification");
        assert_eq!(notification.workspace_id.as_deref(), Some("project-1"));

        let tree = registry
            .tree("/repo", Some("project-1"))
            .expect("tree should build")
            .expect("tree should exist");
        assert_eq!(tree.workspace_id, "project-1");
        assert_eq!(tree.panes.len(), 1);
        assert_eq!(tree.panes[0].unread_count, 1);
        assert_eq!(
            tree.panes[0]
                .agent_session
                .as_ref()
                .and_then(|value| value.message.as_deref()),
            Some("等待输入")
        );
        assert_eq!(tree.notifications.len(), 1);

        let identify = registry.identify(Some("session-1")).expect("identify should exist");
        assert_eq!(identify.workspace_id.as_deref(), Some("project-1"));
        assert_eq!(identify.agent_session_id.as_deref(), Some(agent.agent_session_id.as_str()));
    }

    #[test]
    fn agent_control_registry_downgrades_orphan_notification_to_workspace_scope() {
        let mut registry = ControlPlaneRegistry::default();
        let notification = registry
            .push_notification(NotificationInput {
                message: "孤儿通知".to_string(),
                terminal_session_id: None,
                agent_session_id: None,
                project_path: Some("/repo".to_string()),
                workspace_id: Some("project-1".to_string()),
                pane_id: Some("pane-missing".to_string()),
                surface_id: Some("surface-missing".to_string()),
            })
            .expect("should create orphan notification");

        assert_eq!(notification.workspace_id.as_deref(), Some("project-1"));
        assert_eq!(notification.pane_id, None);
        assert_eq!(notification.surface_id, None);

        registry
            .mark_notification_read(&notification.id, true)
            .expect("mark read should work");
        let tree = registry
            .tree("/repo", Some("project-1"))
            .expect("tree should build")
            .expect("tree should exist");
        assert_eq!(tree.notifications[0].read, true);
    }

    #[test]
    fn build_terminal_control_env_exports_binding_ids() {
        let binding = binding("session-2");
        let env: HashMap<_, _> = build_terminal_control_env(&binding).into_iter().collect();
        assert_eq!(
            env.get("DEVHAVEN_TERMINAL_SESSION_ID").map(String::as_str),
            Some("session-2")
        );
        assert_eq!(
            env.get("DEVHAVEN_WORKSPACE_ID").map(String::as_str),
            Some("project-1")
        );
        assert_eq!(env.get("DEVHAVEN_PANE_ID").map(String::as_str), Some("pane-1"));
        assert_eq!(
            env.get("DEVHAVEN_SURFACE_ID").map(String::as_str),
            Some("pane-1")
        );
    }

    #[test]
    fn agent_control_state_round_trips_via_persisted_file() {
        let state = AgentControlState::default();
        state
            .register_terminal_binding(binding("session-1"))
            .expect("register binding should work");
        state
            .upsert_agent_session_event(AgentSessionEventInput {
                agent_session_id: Some("agent-1".to_string()),
                provider: "codex".to_string(),
                status: "running".to_string(),
                message: Some("执行中".to_string()),
                terminal_session_id: Some("session-1".to_string()),
                project_path: None,
                workspace_id: None,
                pane_id: None,
                surface_id: None,
                cwd: None,
            })
            .expect("upsert agent session should work");
        let notification = state
            .push_notification(NotificationInput {
                message: "需要确认".to_string(),
                terminal_session_id: Some("session-1".to_string()),
                agent_session_id: Some("agent-1".to_string()),
                project_path: None,
                workspace_id: None,
                pane_id: None,
                surface_id: None,
            })
            .expect("push notification should work");
        state
            .mark_notification_read(&notification.id, true)
            .expect("mark read should work");

        let persisted = state.export_control_plane_file().expect("export should work");

        let restored = AgentControlState::default();
        restored
            .replace_from_control_plane_file(persisted)
            .expect("import should work");

        let tree = restored
            .inner
            .lock()
            .expect("lock should work")
            .tree("/repo", Some("project-1"))
            .expect("tree should build")
            .expect("tree should exist");
        assert_eq!(tree.panes.len(), 1);
        assert_eq!(
            tree.panes[0]
                .agent_session
                .as_ref()
                .map(|session| session.provider.as_str()),
            Some("codex")
        );
        assert_eq!(tree.notifications.len(), 1);
        assert!(tree.notifications[0].read);
    }
}
