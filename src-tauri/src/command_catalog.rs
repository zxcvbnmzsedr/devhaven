use std::collections::BTreeSet;
use std::path::{Component, Path, PathBuf};

use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Manager};

use crate::interaction_lock::InteractionLockState;
use crate::models::{
    AppStateFile, GitIdentity, GlobalSkillInstallRequest, GlobalSkillUninstallRequest,
    SharedScriptManifestScript, WorktreeInitRetryRequest, WorktreeInitStartRequest,
    WorktreeInitStatusQuery,
};
use crate::agent_control::AgentControlState;
use crate::agent_launcher::AgentLauncherState;
use crate::quick_command_manager::QuickCommandManager;
use crate::terminal::TerminalState;
use crate::web_server::WebServerRuntime;
use crate::worktree_init::WorktreeInitState;

#[macro_export]
macro_rules! devhaven_for_each_command {
    ($callback:ident) => {
        $callback! {
            { load_app_state, web_load_app_state }
            { save_app_state, web_save_app_state }
            { load_projects, web_load_projects }
            { list_global_skills, web_list_global_skills }
            { install_global_skill, web_install_global_skill }
            { uninstall_global_skill, web_uninstall_global_skill }
            { save_projects, web_save_projects }
            { discover_projects, web_discover_projects }
            { build_projects, web_build_projects }
            { list_branches, web_list_branches }
            { git_is_repo, web_git_is_repo }
            { git_get_status, web_git_get_status }
            { git_get_diff_contents, web_git_get_diff_contents }
            { git_stage_files, web_git_stage_files }
            { git_unstage_files, web_git_unstage_files }
            { git_discard_files, web_git_discard_files }
            { git_commit, web_git_commit }
            { git_checkout_branch, web_git_checkout_branch }
            { git_delete_branch, web_git_delete_branch }
            { git_worktree_add, web_git_worktree_add }
            { git_worktree_list, web_git_worktree_list }
            { git_worktree_remove, web_git_worktree_remove }
            { get_interaction_lock_state, web_get_interaction_lock_state }
            { worktree_init_start, web_worktree_init_start }
            { worktree_init_create, web_worktree_init_create }
            { worktree_init_create_blocking, web_worktree_init_create_blocking }
            { worktree_init_cancel, web_worktree_init_cancel }
            { worktree_init_retry, web_worktree_init_retry }
            { worktree_init_status, web_worktree_init_status }
            { open_in_finder, web_open_in_finder }
            { open_in_editor, none }
            { resolve_home_dir, web_resolve_home_dir }
            { list_shared_scripts, web_list_shared_scripts }
            { save_shared_scripts_manifest, web_save_shared_scripts_manifest }
            { restore_shared_script_presets, web_restore_shared_script_presets }
            { read_shared_script_file, web_read_shared_script_file }
            { write_shared_script_file, web_write_shared_script_file }
            { copy_to_clipboard, web_copy_to_clipboard }
            { send_system_notification, none }
            { read_project_notes, web_read_project_notes }
            { read_project_notes_previews, web_read_project_notes_previews }
            { write_project_notes, web_write_project_notes }
            { read_project_todo, web_read_project_todo }
            { write_project_todo, web_write_project_todo }
            { list_project_markdown_files, web_list_project_markdown_files }
            { read_project_markdown_file, web_read_project_markdown_file }
            { list_project_dir_entries, web_list_project_dir_entries }
            { read_project_file, web_read_project_file }
            { write_project_file, web_write_project_file }
            { collect_git_daily, web_collect_git_daily }
            { load_heatmap_cache, web_load_heatmap_cache }
            { save_heatmap_cache, web_save_heatmap_cache }
            { load_terminal_layout_snapshot, web_load_terminal_layout_snapshot }
            { save_terminal_layout_snapshot, web_save_terminal_layout_snapshot }
            { delete_terminal_layout_snapshot, web_delete_terminal_layout_snapshot }
            { list_terminal_layout_snapshot_summaries, web_list_terminal_layout_snapshot_summaries }
            { apply_web_server_config, web_apply_web_server_config }
            { quick_command_start, web_quick_command_start }
            { quick_command_stop, web_quick_command_stop }
            { quick_command_finish, web_quick_command_finish }
            { quick_command_list, web_quick_command_list }
            { quick_command_runtime_snapshot, web_quick_command_runtime_snapshot }
            { devhaven_identify, web_devhaven_identify }
            { devhaven_tree, web_devhaven_tree }
            { devhaven_notify, web_devhaven_notify }
            { devhaven_notify_target, web_devhaven_notify_target }
            { devhaven_agent_session_event, web_devhaven_agent_session_event }
            { devhaven_set_status, web_devhaven_set_status }
            { devhaven_clear_status, web_devhaven_clear_status }
            { devhaven_set_agent_pid, web_devhaven_set_agent_pid }
            { devhaven_clear_agent_pid, web_devhaven_clear_agent_pid }
            { devhaven_mark_notification_read, web_devhaven_mark_notification_read }
            { devhaven_mark_notification_unread, web_devhaven_mark_notification_unread }
            { agent_spawn, web_agent_spawn }
            { agent_stop, web_agent_stop }
            { agent_runtime_diagnose, web_agent_runtime_diagnose }
            { terminal_create_session, web_terminal_create_session }
            { terminal_write, web_terminal_write }
            { terminal_resize, web_terminal_resize }
            { terminal_set_replay_mode, web_terminal_set_replay_mode }
            { terminal_kill, web_terminal_kill }
        }
    };
}

#[macro_export]
macro_rules! __devhaven_as_tauri_handler {
    ($({ $command:ident, $web:ident })*) => {
        tauri::generate_handler![$($command),*]
    };
}

#[macro_export]
macro_rules! devhaven_generate_tauri_handler {
    () => {
        $crate::devhaven_for_each_command!(__devhaven_as_tauri_handler)
    };
}

macro_rules! dispatch_web_entry {
    ($name:expr, none, $app:expr, $guard:expr, $payload:expr) => {
        Err(WebApiError::not_found(
            "command_not_available",
            format!("命令不支持 Web 运行时: {}", $name),
        ))
    };
    ($name:expr, $handler:ident, $app:expr, $guard:expr, $payload:expr) => {
        $handler($app, $guard, $payload)
    };
}

#[cfg(test)]
macro_rules! push_web_name {
    ($names:ident, $command:ident, none) => {};
    ($names:ident, $command:ident, $handler:ident) => {
        $names.push(stringify!($command));
    };
}

type WebCommandResult = Result<Value, WebApiError>;
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct WebApiErrorBody {
    code: &'static str,
    message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<Value>,
}

#[derive(Debug)]
pub struct WebApiError {
    status: StatusCode,
    code: &'static str,
    message: String,
    details: Option<Value>,
}

impl WebApiError {
    pub fn bad_request(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::BAD_REQUEST,
            code,
            message: message.into(),
            details: None,
        }
    }

    pub fn forbidden(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::FORBIDDEN,
            code,
            message: message.into(),
            details: None,
        }
    }

    pub fn not_found(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::NOT_FOUND,
            code,
            message: message.into(),
            details: None,
        }
    }

    pub fn internal(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status: StatusCode::INTERNAL_SERVER_ERROR,
            code,
            message: message.into(),
            details: None,
        }
    }
}

impl IntoResponse for WebApiError {
    fn into_response(self) -> Response {
        (
            self.status,
            Json(WebApiErrorBody {
                code: self.code,
                message: self.message,
                details: self.details,
            }),
        )
            .into_response()
    }
}

#[derive(Debug, Clone)]
pub struct PathGuard {
    home_dir: PathBuf,
    allowed_roots: Vec<PathBuf>,
}

impl PathGuard {
    pub fn from_app(app: &AppHandle) -> Result<Self, WebApiError> {
        let home_dir = app
            .path()
            .home_dir()
            .map_err(|error| WebApiError::internal("resolve_home_dir_failed", format!("解析用户目录失败: {error}")))?;
        let app_state = crate::load_app_state(app.clone()).unwrap_or_else(|error| {
            log::warn!("加载 app_state 失败，路径校验将使用默认空配置: {}", error);
            AppStateFile::default()
        });
        let mut roots = BTreeSet::new();
        for directory in app_state.directories {
            if let Some(path) = normalize_absolute_path(&directory, &home_dir) {
                roots.insert(canonical_or_normalized(path));
            }
        }
        for project_path in app_state.direct_project_paths {
            if let Some(path) = normalize_absolute_path(&project_path, &home_dir) {
                roots.insert(canonical_or_normalized(path));
            }
        }
        roots.insert(canonical_or_normalized(home_dir.join(".devhaven")));

        Ok(Self {
            home_dir,
            allowed_roots: roots.into_iter().collect(),
        })
    }

    pub fn ensure_allowed_path(&self, raw: &str, field: &str) -> Result<(), WebApiError> {
        let candidate = normalize_absolute_path(raw, &self.home_dir).ok_or_else(|| {
            WebApiError::bad_request("invalid_path", format!("参数 {field} 非法：路径必须是绝对路径"))
        })?;
        let candidate = canonical_or_normalized(candidate);
        let is_allowed = self.allowed_roots.iter().any(|root| candidate.starts_with(root));
        if is_allowed {
            return Ok(());
        }
        Err(WebApiError::forbidden(
            "path_out_of_scope",
            format!(
                "参数 {field} 越权：路径不在受管目录范围内 ({})",
                candidate.display()
            ),
        ))
    }

    pub fn ensure_under_home_path(&self, raw: &str, field: &str) -> Result<(), WebApiError> {
        let candidate = normalize_absolute_path(raw, &self.home_dir).ok_or_else(|| {
            WebApiError::bad_request("invalid_path", format!("参数 {field} 非法：路径必须是绝对路径"))
        })?;
        let candidate = canonical_or_normalized(candidate);
        if candidate == self.home_dir {
            return Err(WebApiError::bad_request(
                "invalid_home_path",
                format!(
                    "参数 {field} 非法：不允许直接使用用户目录根路径 ({})",
                    candidate.display()
                ),
            ));
        }
        if candidate.starts_with(&self.home_dir) {
            return Ok(());
        }
        Err(WebApiError::bad_request(
            "path_outside_home",
            format!(
                "参数 {field} 非法：仅允许访问当前用户目录下的路径 ({})",
                candidate.display()
            ),
        ))
    }
}

#[cfg(test)]
pub(crate) fn all_command_names() -> &'static [&'static str] {
    macro_rules! collect_all_names {
        ($({ $command:ident, $web:ident })*) => {
            &[$(stringify!($command)),*]
        };
    }
    crate::devhaven_for_each_command!(collect_all_names)
}

#[cfg(test)]
pub(crate) fn web_command_names() -> Vec<&'static str> {
    let mut names = Vec::new();
    macro_rules! collect_web_names {
        ($({ $command:ident, $web:ident })*) => {
            $(push_web_name!(names, $command, $web);)*
        };
    }
    crate::devhaven_for_each_command!(collect_web_names);
    names
}

pub(crate) fn dispatch_web_command(app: &AppHandle, command: &str, payload: Value) -> WebCommandResult {
    let guard = PathGuard::from_app(app)?;
    macro_rules! dispatch_command_match {
        ($({ $command:ident, $web:ident })*) => {
            match command {
                $(stringify!($command) => dispatch_web_entry!(stringify!($command), $web, app, &guard, &payload),)*
                _ => Err(WebApiError::not_found(
                    "unknown_command",
                    format!("未知命令: {}", command),
                )),
            }
        };
    }
    crate::devhaven_for_each_command!(dispatch_command_match)
}

fn payload_object(payload: &Value) -> Result<&serde_json::Map<String, Value>, WebApiError> {
    payload
        .as_object()
        .ok_or_else(|| WebApiError::bad_request("invalid_payload", "请求体必须是 JSON 对象"))
}

fn required<T: DeserializeOwned>(payload: &Value, keys: &[&str]) -> Result<T, WebApiError> {
    let object = payload_object(payload)?;
    let value = keys
        .iter()
        .find_map(|key| object.get(*key))
        .ok_or_else(|| {
            if keys.is_empty() {
                WebApiError::bad_request("missing_parameter", "缺少参数")
            } else {
                WebApiError::bad_request("missing_parameter", format!("缺少参数: {}", keys[0]))
            }
        })?;
    serde_json::from_value(value.clone())
        .map_err(|error| WebApiError::bad_request("invalid_parameter", format!("参数解析失败 {}: {}", keys[0], error)))
}

fn optional<T: DeserializeOwned>(payload: &Value, keys: &[&str]) -> Result<Option<T>, WebApiError> {
    let object = payload_object(payload)?;
    let Some(value) = keys.iter().find_map(|key| object.get(*key)) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    serde_json::from_value(value.clone())
        .map(Some)
        .map_err(|error| WebApiError::bad_request("invalid_parameter", format!("参数解析失败 {}: {}", keys[0], error)))
}

fn serialize_value<T: Serialize>(value: T) -> WebCommandResult {
    serde_json::to_value(value)
        .map_err(|error| WebApiError::internal("serialize_response_failed", format!("序列化返回值失败: {}", error)))
}

fn serialize_result<T: Serialize>(result: Result<T, String>) -> WebCommandResult {
    result
        .map_err(|error| WebApiError::internal("command_failed", error))
        .and_then(serialize_value)
}

fn ensure_allowed_paths(guard: &PathGuard, paths: &[String], field: &str) -> Result<(), WebApiError> {
    for path in paths {
        guard.ensure_allowed_path(path, field)?;
    }
    Ok(())
}

fn ensure_home_paths(guard: &PathGuard, paths: &[String], field: &str) -> Result<(), WebApiError> {
    for path in paths {
        guard.ensure_under_home_path(path, field)?;
    }
    Ok(())
}

fn normalize_absolute_path(raw: &str, home_dir: &Path) -> Option<PathBuf> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    let expanded = if trimmed == "~" {
        home_dir.to_path_buf()
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home_dir.join(rest)
    } else {
        PathBuf::from(trimmed)
    };

    if !expanded.is_absolute() {
        return None;
    }

    Some(normalize_path_components(expanded))
}

fn normalize_path_components(path: PathBuf) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    normalized
}

fn canonical_or_normalized(path: PathBuf) -> PathBuf {
    std::fs::canonicalize(&path).unwrap_or(path)
}

fn web_load_app_state(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::load_app_state(app.clone()))
}

fn web_save_app_state(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = required::<AppStateFile>(payload, &["state"])?;
    ensure_home_paths(guard, &state.directories, "state.directories[]")?;
    ensure_home_paths(guard, &state.direct_project_paths, "state.directProjectPaths[]")?;
    serialize_result(crate::save_app_state(app.clone(), state))
}

fn web_load_projects(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::load_projects(app.clone()))
}

fn web_list_global_skills(_app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::list_global_skills())
}

fn web_install_global_skill(_app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let request = required::<GlobalSkillInstallRequest>(payload, &["request"])?;
    serialize_result(crate::install_global_skill(request))
}

fn web_uninstall_global_skill(_app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let request = required::<GlobalSkillUninstallRequest>(payload, &["request"])?;
    serialize_result(crate::uninstall_global_skill(request))
}

fn web_save_projects(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let projects = required::<Vec<crate::models::Project>>(payload, &["projects"])?;
    serialize_result(crate::save_projects(app.clone(), projects))
}

fn web_discover_projects(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let directories = required::<Vec<String>>(payload, &["directories"])?;
    ensure_home_paths(guard, &directories, "directories[]")?;
    serialize_value(crate::discover_projects(directories))
}

fn web_build_projects(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let paths = required::<Vec<String>>(payload, &["paths"])?;
    ensure_home_paths(guard, &paths, "paths[]")?;
    let existing = required::<Vec<crate::models::Project>>(payload, &["existing"])?;
    serialize_value(crate::build_projects(paths, existing))
}

fn web_list_branches(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let base_path = required::<String>(payload, &["basePath", "base_path"])?;
    guard.ensure_allowed_path(&base_path, "basePath")?;
    serialize_value(crate::list_branches(base_path))
}

fn web_git_is_repo(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_value(crate::git_is_repo(path))
}

fn web_git_get_status(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::git_get_status(path))
}

fn web_git_get_diff_contents(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    let staged = required::<bool>(payload, &["staged"])?;
    let old_relative_path = optional::<String>(payload, &["oldRelativePath", "old_relative_path"])?;
    serialize_result(crate::git_get_diff_contents(path, relative_path, staged, old_relative_path))
}

fn web_git_stage_files(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_paths = required::<Vec<String>>(payload, &["relativePaths", "relative_paths"])?;
    serialize_result(crate::git_stage_files(path, relative_paths))
}

fn web_git_unstage_files(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_paths = required::<Vec<String>>(payload, &["relativePaths", "relative_paths"])?;
    serialize_result(crate::git_unstage_files(path, relative_paths))
}

fn web_git_discard_files(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_paths = required::<Vec<String>>(payload, &["relativePaths", "relative_paths"])?;
    serialize_result(crate::git_discard_files(path, relative_paths))
}

fn web_git_commit(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let message = required::<String>(payload, &["message"])?;
    serialize_result(crate::git_commit(path, message))
}

fn web_git_checkout_branch(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let branch = required::<String>(payload, &["branch"])?;
    serialize_result(crate::git_checkout_branch(path, branch))
}

fn web_git_delete_branch(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let branch = required::<String>(payload, &["branch"])?;
    let force = required::<bool>(payload, &["force"])?;
    serialize_result(crate::git_delete_branch(path, branch, force))
}

fn web_git_worktree_add(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let branch = required::<String>(payload, &["branch"])?;
    let create_branch = required::<bool>(payload, &["createBranch", "create_branch"])?;
    let target_path = optional::<String>(payload, &["targetPath", "target_path"])?;
    if let Some(target_path) = target_path.as_deref() {
        guard.ensure_allowed_path(target_path, "targetPath")?;
    }
    serialize_result(crate::git_worktree_add(path, branch, create_branch, target_path))
}

fn web_git_worktree_list(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::git_worktree_list(path))
}

fn web_git_worktree_remove(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    let worktree_path = required::<String>(payload, &["worktreePath", "worktree_path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    guard.ensure_allowed_path(&worktree_path, "worktreePath")?;
    let force = required::<bool>(payload, &["force"])?;
    serialize_result(crate::git_worktree_remove(path, worktree_path, force))
}

fn web_get_interaction_lock_state(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    let lock_state = app.state::<InteractionLockState>();
    serialize_value(crate::get_interaction_lock_state(lock_state))
}

fn web_worktree_init_start(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let request = required::<WorktreeInitStartRequest>(payload, &["request"])?;
    guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
    serialize_result(crate::worktree_init_start(app.clone(), state, request))
}

fn web_worktree_init_create(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let interaction_lock = app.state::<InteractionLockState>();
    let request = required::<WorktreeInitStartRequest>(payload, &["request"])?;
    guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
    serialize_result(crate::worktree_init_create(app.clone(), state, interaction_lock, request))
}

fn web_worktree_init_create_blocking(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let interaction_lock = app.state::<InteractionLockState>();
    let request = required::<WorktreeInitStartRequest>(payload, &["request"])?;
    guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
    serialize_result(crate::worktree_init_create_blocking(app.clone(), state, interaction_lock, request))
}

fn web_worktree_init_cancel(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let job_id = required::<String>(payload, &["jobId", "job_id"])?;
    serialize_result(crate::worktree_init_cancel(app.clone(), state, job_id))
}

fn web_worktree_init_retry(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let request = required::<WorktreeInitRetryRequest>(payload, &["request"])?;
    serialize_result(crate::worktree_init_retry(app.clone(), state, request))
}

fn web_worktree_init_status(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<WorktreeInitState>();
    let query = optional::<WorktreeInitStatusQuery>(payload, &["query"])?;
    if let Some(project_path) = query.as_ref().and_then(|item| item.project_path.as_ref()) {
        guard.ensure_allowed_path(project_path, "query.projectPath")?;
    }
    serialize_result(crate::worktree_init_status(state, query))
}

fn web_open_in_finder(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::open_in_finder(path))
}

fn web_resolve_home_dir(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::resolve_home_dir(app.clone()))
}

fn web_list_shared_scripts(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let root = optional::<String>(payload, &["root"])?;
    if let Some(root) = root.as_deref() {
        guard.ensure_allowed_path(root, "root")?;
    }
    serialize_result(crate::list_shared_scripts(app.clone(), root))
}

fn web_save_shared_scripts_manifest(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let root = optional::<String>(payload, &["root"])?;
    if let Some(root) = root.as_deref() {
        guard.ensure_allowed_path(root, "root")?;
    }
    let scripts = required::<Vec<SharedScriptManifestScript>>(payload, &["scripts"])?;
    serialize_result(crate::save_shared_scripts_manifest(app.clone(), root, scripts))
}

fn web_restore_shared_script_presets(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let root = optional::<String>(payload, &["root"])?;
    if let Some(root) = root.as_deref() {
        guard.ensure_allowed_path(root, "root")?;
    }
    serialize_result(crate::restore_shared_script_presets(app.clone(), root))
}

fn web_read_shared_script_file(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let root = optional::<String>(payload, &["root"])?;
    if let Some(root) = root.as_deref() {
        guard.ensure_allowed_path(root, "root")?;
    }
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    serialize_result(crate::read_shared_script_file(app.clone(), root, relative_path))
}

fn web_write_shared_script_file(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let root = optional::<String>(payload, &["root"])?;
    if let Some(root) = root.as_deref() {
        guard.ensure_allowed_path(root, "root")?;
    }
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    let content = required::<String>(payload, &["content"])?;
    serialize_result(crate::write_shared_script_file(app.clone(), root, relative_path, content))
}

fn web_copy_to_clipboard(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let content = required::<String>(payload, &["content"])?;
    serialize_result(crate::copy_to_clipboard(app.clone(), content))
}

fn web_read_project_notes(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::read_project_notes(path))
}

fn web_read_project_notes_previews(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let paths = required::<Vec<String>>(payload, &["paths"])?;
    ensure_allowed_paths(guard, &paths, "paths[]")?;
    serialize_value(crate::read_project_notes_previews(paths))
}

fn web_write_project_notes(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let notes = optional::<String>(payload, &["notes"])?;
    serialize_result(crate::write_project_notes(path, notes))
}

fn web_read_project_todo(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::read_project_todo(path))
}

fn web_write_project_todo(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let todo = optional::<String>(payload, &["todo"])?;
    serialize_result(crate::write_project_todo(path, todo))
}

fn web_list_project_markdown_files(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    serialize_result(crate::list_project_markdown_files(path))
}

fn web_read_project_markdown_file(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    serialize_result(crate::read_project_markdown_file(path, relative_path))
}

fn web_list_project_dir_entries(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    let show_hidden = required::<bool>(payload, &["showHidden", "show_hidden"])?;
    serialize_value(crate::list_project_dir_entries(path, relative_path, show_hidden))
}

fn web_read_project_file(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    serialize_value(crate::read_project_file(path, relative_path))
}

fn web_write_project_file(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let path = required::<String>(payload, &["path"])?;
    guard.ensure_allowed_path(&path, "path")?;
    let relative_path = required::<String>(payload, &["relativePath", "relative_path"])?;
    let content = required::<String>(payload, &["content"])?;
    serialize_value(crate::write_project_file(path, relative_path, content))
}

fn web_collect_git_daily(_app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let paths = required::<Vec<String>>(payload, &["paths"])?;
    ensure_allowed_paths(guard, &paths, "paths[]")?;
    let identities = optional::<Vec<GitIdentity>>(payload, &["identities"])?.unwrap_or_default();
    serialize_value(crate::collect_git_daily(paths, identities))
}

fn web_load_heatmap_cache(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::load_heatmap_cache(app.clone()))
}

fn web_save_heatmap_cache(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let cache = required::<crate::models::HeatmapCacheFile>(payload, &["cache"])?;
    serialize_result(crate::save_heatmap_cache(app.clone(), cache))
}

fn web_load_terminal_layout_snapshot(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    serialize_result(crate::load_terminal_layout_snapshot(app.clone(), project_path))
}

fn web_save_terminal_layout_snapshot(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    let snapshot = required::<Value>(payload, &["snapshot"])?;
    let source_client_id = optional::<String>(payload, &["sourceClientId", "source_client_id"])?;
    serialize_result(crate::save_terminal_layout_snapshot(
        app.clone(),
        project_path,
        snapshot,
        source_client_id,
    ))
}

fn web_delete_terminal_layout_snapshot(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    let source_client_id = optional::<String>(payload, &["sourceClientId", "source_client_id"])?;
    serialize_result(crate::delete_terminal_layout_snapshot(
        app.clone(),
        project_path,
        source_client_id,
    ))
}

fn web_list_terminal_layout_snapshot_summaries(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    serialize_result(crate::list_terminal_layout_snapshot_summaries(app.clone()))
}

fn web_apply_web_server_config(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    let runtime = app.state::<WebServerRuntime>();
    serialize_result(crate::apply_web_server_config(app.clone(), runtime))
}

fn web_quick_command_start(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<QuickCommandManager>();
    let project_id = required::<String>(payload, &["projectId", "project_id"])?;
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    let script_id = required::<String>(payload, &["scriptId", "script_id"])?;
    let command = required::<String>(payload, &["command"])?;
    let window_label = optional::<String>(payload, &["windowLabel", "window_label"])?;
    serialize_value(crate::quick_command_manager::quick_command_start(
        app.clone(),
        state,
        project_id,
        project_path,
        script_id,
        command,
        window_label,
    ))
}

fn web_quick_command_stop(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<QuickCommandManager>();
    let job_id = required::<String>(payload, &["jobId", "job_id"])?;
    let force = optional::<bool>(payload, &["force"])?;
    serialize_result(crate::quick_command_manager::quick_command_stop(app.clone(), state, job_id, force))
}

fn web_quick_command_finish(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<QuickCommandManager>();
    let job_id = required::<String>(payload, &["jobId", "job_id"])?;
    let exit_code = optional::<i32>(payload, &["exitCode", "exit_code"])?;
    let error = optional::<String>(payload, &["error"])?;
    serialize_result(crate::quick_command_manager::quick_command_finish(app.clone(), state, job_id, exit_code, error))
}

fn web_quick_command_list(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<QuickCommandManager>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_value(crate::quick_command_manager::quick_command_list(state, project_path))
}

fn web_quick_command_runtime_snapshot(_app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    serialize_value(crate::quick_command_runtime_snapshot(project_path))
}

fn web_devhaven_identify(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    serialize_result(crate::devhaven_identify(
        state,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
    ))
}

fn web_devhaven_tree(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_tree(
        state,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
    ))
}

fn web_devhaven_notify(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_notify(
        app.clone(),
        state,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
        optional::<String>(payload, &["agentSessionId", "agent_session_id"])?,
        project_path,
        optional::<String>(payload, &["title"])?,
        required::<String>(payload, &["message"])?,
        optional::<String>(payload, &["level"])?,
    ))
}

fn web_devhaven_notify_target(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_notify_target(
        app.clone(),
        state,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
        optional::<String>(payload, &["agentSessionId", "agent_session_id"])?,
        project_path,
        optional::<String>(payload, &["title"])?,
        required::<String>(payload, &["message"])?,
        optional::<String>(payload, &["level"])?,
    ))
}

fn web_devhaven_agent_session_event(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_agent_session_event(
        app.clone(),
        state,
        optional::<String>(payload, &["agentSessionId", "agent_session_id"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
        required::<String>(payload, &["provider"])?,
        required::<crate::agent_control::AgentSessionStatus>(payload, &["status"])?,
        project_path,
        optional::<String>(payload, &["cwd"])?,
        optional::<String>(payload, &["message"])?,
    ))
}

fn web_devhaven_mark_notification_read(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    serialize_result(crate::devhaven_mark_notification_read(
        app.clone(),
        state,
        required::<String>(payload, &["notificationId", "notification_id"])?,
    ))
}

fn web_devhaven_mark_notification_unread(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    serialize_result(crate::devhaven_mark_notification_unread(
        app.clone(),
        state,
        required::<String>(payload, &["notificationId", "notification_id"])?,
    ))
}

fn web_devhaven_set_status(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_set_status(
        app.clone(),
        state,
        required::<String>(payload, &["key"])?,
        required::<String>(payload, &["value"])?,
        optional::<String>(payload, &["icon"])?,
        optional::<String>(payload, &["color"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
    ))
}

fn web_devhaven_clear_status(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_clear_status(
        app.clone(),
        state,
        required::<String>(payload, &["key"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
    ))
}

fn web_devhaven_set_agent_pid(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_set_agent_pid(
        app.clone(),
        state,
        required::<String>(payload, &["key"])?,
        required::<i32>(payload, &["pid"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
    ))
}

fn web_devhaven_clear_agent_pid(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<AgentControlState>();
    let project_path = optional::<String>(payload, &["projectPath", "project_path"])?;
    if let Some(project_path) = project_path.as_deref() {
        guard.ensure_allowed_path(project_path, "projectPath")?;
    }
    serialize_result(crate::devhaven_clear_agent_pid(
        app.clone(),
        state,
        required::<String>(payload, &["key"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
    ))
}

fn web_agent_spawn(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let launcher = app.state::<AgentLauncherState>();
    let control_state = app.state::<AgentControlState>();
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    serialize_result(crate::agent_spawn(
        app.clone(),
        launcher,
        control_state,
        required::<String>(payload, &["provider"])?,
        project_path,
        optional::<String>(payload, &["workspaceId", "workspace_id"])?,
        optional::<String>(payload, &["paneId", "pane_id"])?,
        optional::<String>(payload, &["surfaceId", "surface_id"])?,
        optional::<String>(payload, &["terminalSessionId", "terminal_session_id"])?,
        optional::<String>(payload, &["cwd"])?,
    ))
}

fn web_agent_stop(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let launcher = app.state::<AgentLauncherState>();
    let control_state = app.state::<AgentControlState>();
    serialize_result(crate::agent_stop(
        app.clone(),
        launcher,
        control_state,
        required::<String>(payload, &["agentSessionId", "agent_session_id"])?,
        optional::<bool>(payload, &["force"])?,
    ))
}

fn web_agent_runtime_diagnose(app: &AppHandle, _guard: &PathGuard, _payload: &Value) -> WebCommandResult {
    let launcher = app.state::<AgentLauncherState>();
    let control_state = app.state::<AgentControlState>();
    serialize_result(crate::agent_runtime_diagnose(launcher, control_state))
}

fn web_terminal_create_session(app: &AppHandle, guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<TerminalState>();
    let control_state = app.state::<AgentControlState>();
    let project_path = required::<String>(payload, &["projectPath", "project_path"])?;
    guard.ensure_allowed_path(&project_path, "projectPath")?;
    let cols = required::<u16>(payload, &["cols"])?;
    let rows = required::<u16>(payload, &["rows"])?;
    let window_label = required::<String>(payload, &["windowLabel", "window_label"])?;
    let session_id = optional::<String>(payload, &["sessionId", "session_id"])?;
    let client_id = optional::<String>(payload, &["clientId", "client_id"])?;
    let workspace_id = optional::<String>(payload, &["workspaceId", "workspace_id"])?;
    let pane_id = optional::<String>(payload, &["paneId", "pane_id"])?;
    let surface_id = optional::<String>(payload, &["surfaceId", "surface_id"])?;
    serialize_result(crate::terminal::terminal_create_session(
        app.clone(),
        state,
        control_state,
        project_path,
        cols,
        rows,
        window_label,
        session_id,
        client_id,
        workspace_id,
        pane_id,
        surface_id,
    ))
}

fn web_terminal_write(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<TerminalState>();
    let pty_id = required::<String>(payload, &["ptyId", "pty_id"])?;
    let data = required::<String>(payload, &["data"])?;
    serialize_result(crate::terminal::terminal_write(state, pty_id, data))
}

fn web_terminal_resize(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<TerminalState>();
    let pty_id = required::<String>(payload, &["ptyId", "pty_id"])?;
    let cols = required::<u16>(payload, &["cols"])?;
    let rows = required::<u16>(payload, &["rows"])?;
    serialize_result(crate::terminal::terminal_resize(state, pty_id, cols, rows))
}

fn web_terminal_set_replay_mode(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<TerminalState>();
    let pty_id = required::<String>(payload, &["ptyId", "pty_id"])?;
    let mode = required::<crate::terminal::TerminalReplayMode>(payload, &["mode"])?;
    serialize_result(crate::terminal::terminal_set_replay_mode(state, pty_id, mode))
}

fn web_terminal_kill(app: &AppHandle, _guard: &PathGuard, payload: &Value) -> WebCommandResult {
    let state = app.state::<TerminalState>();
    let pty_id = required::<String>(payload, &["ptyId", "pty_id"])?;
    let client_id = optional::<String>(payload, &["clientId", "client_id"])?;
    let force = optional::<bool>(payload, &["force"])?;
    serialize_result(crate::terminal::terminal_kill(state, pty_id, client_id, force))
}

#[cfg(test)]
mod tests {
    use super::{all_command_names, optional, required, web_command_names, WebApiError};
    use axum::body::to_bytes;
    use axum::http::StatusCode;
    use axum::response::IntoResponse;
    use serde_json::json;
    use std::collections::HashSet;

    #[test]
    fn command_catalog_keeps_web_subset_of_tauri() {
        let all = all_command_names();
        let web = web_command_names();
        let all_set: HashSet<&str> = all.iter().copied().collect();
        let web_set: HashSet<&str> = web.iter().copied().collect();

        assert_eq!(all.len(), all_set.len(), "Tauri 命令列表不应重复");
        assert_eq!(web.len(), web_set.len(), "Web 命令列表不应重复");
        assert!(all_set.contains("open_in_editor"));
        assert!(!web_set.contains("open_in_editor"));
        assert!(all_set.contains("devhaven_identify"));
        assert!(all_set.contains("devhaven_tree"));
        assert!(all_set.contains("devhaven_notify"));
        assert!(all_set.contains("devhaven_notify_target"));
        assert!(all_set.contains("devhaven_agent_session_event"));
        assert!(all_set.contains("devhaven_set_status"));
        assert!(all_set.contains("devhaven_clear_status"));
        assert!(all_set.contains("devhaven_set_agent_pid"));
        assert!(all_set.contains("devhaven_clear_agent_pid"));
        assert!(all_set.contains("devhaven_mark_notification_read"));
        assert!(all_set.contains("devhaven_mark_notification_unread"));
        assert!(all_set.contains("agent_spawn"));
        assert!(all_set.contains("agent_stop"));
        assert!(all_set.contains("agent_runtime_diagnose"));
        assert!(web_set.contains("devhaven_identify"));
        assert!(web_set.contains("devhaven_tree"));
        assert!(web_set.contains("devhaven_notify"));
        assert!(web_set.contains("devhaven_notify_target"));
        assert!(web_set.contains("devhaven_set_status"));
        assert!(web_set.contains("devhaven_clear_status"));
        assert!(web_set.contains("devhaven_set_agent_pid"));
        assert!(web_set.contains("devhaven_clear_agent_pid"));
        assert!(web_set.contains("agent_spawn"));
        assert!(web_set.contains("agent_stop"));
        assert!(web_set.contains("agent_runtime_diagnose"));
        assert!(!all_set.contains("get_codex_monitor_snapshot"));
        assert!(!web_set.contains("get_codex_monitor_snapshot"));
        assert!(web_set.is_subset(&all_set));
    }

    #[test]
    fn payload_helpers_support_aliases_and_null_optional() {
        let payload = json!({
            "projectPath": "/tmp/demo",
            "force": null,
        });

        let project_path = required::<String>(&payload, &["projectPath", "project_path"])
            .expect("should parse camelCase alias");
        let force = optional::<bool>(&payload, &["force"]).expect("optional null should parse");

        assert_eq!(project_path, "/tmp/demo");
        assert_eq!(force, None);
    }

    #[tokio::test]
    async fn web_api_error_response_uses_structured_body() {
        let response = WebApiError::bad_request("missing_parameter", "缺少参数: path").into_response();
        assert_eq!(response.status(), StatusCode::BAD_REQUEST);

        let body = to_bytes(response.into_body(), usize::MAX)
            .await
            .expect("should read error body");
        let value: serde_json::Value = serde_json::from_slice(&body).expect("should parse json body");
        assert_eq!(value["code"], "missing_parameter");
        assert_eq!(value["message"], "缺少参数: path");
    }
}
