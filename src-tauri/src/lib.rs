mod agent_control;
mod agent_launcher;
mod command_catalog;
mod filesystem;
mod git_daily;
mod git_ops;
mod interaction_lock;
mod markdown;
mod models;
mod notes;
mod project_loader;
mod quick_command_manager;
mod shared_scripts;
mod skills;
mod storage;
mod system;
mod terminal;
mod terminal_runtime;
mod time_utils;
mod web_event_bus;
mod web_server;
mod worktree_init;
mod worktree_setup;

use serde::Serialize;
use serde_json::{Value as JsonValue, json};
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::Duration;
use std::time::Instant;
use std::time::{SystemTime, UNIX_EPOCH};
use tauri::AppHandle;
use tauri::Emitter;
use tauri::Manager;
use tauri::State;
use tauri_plugin_log::{Target, TargetKind};

use crate::models::{
    AppStateFile, BranchListItem, FsListResponse, FsReadResponse, FsWriteResponse, GitDailyResult,
    GitDiffContents, GitIdentity, GitRepoStatus,
    GitWorktreeAddResult, GitWorktreeListItem, GlobalSkillInstallRequest, GlobalSkillInstallResult,
    GlobalSkillUninstallRequest, GlobalSkillsSnapshot, HeatmapCacheFile, InteractionLockPayload,
    MarkdownFileEntry, Project, ProjectNotesPreview, SharedScriptEntry, SharedScriptManifestScript,
    SharedScriptPresetRestoreResult, TerminalLayoutSnapshotSummary,
    WorktreeInitCancelResult, WorktreeInitCreateBlockingResult, WorktreeInitJobStatus,
    WorktreeInitRetryRequest, WorktreeInitStartRequest, WorktreeInitStartResult,
    WorktreeInitStatusQuery, WorktreeInitStep,
};
use crate::agent_control::{
    AgentControlState, AgentSessionStatus, ControlPlaneIdentifyResult, ControlPlaneTree,
    DevHavenAgentSessionEventRequest, DevHavenIdentifyRequest, DevHavenNotifyRequest,
    DevHavenNotifyTargetRequest, DevHavenSetAgentPidRequest, DevHavenSetStatusRequest,
    DevHavenTreeRequest, NotificationMutationRequest, PrimitiveKeyRequest,
};
use crate::agent_launcher::{AgentLauncherState, AgentRuntimeDiagnoseResult, AgentSpawnResult};
use crate::quick_command_manager::{
    QuickCommandManager, quick_command_finish, quick_command_list, quick_command_start,
    quick_command_stop,
};
use crate::system::{EditorOpenParams, SystemNotificationParams};
use crate::terminal::{
    TerminalState, terminal_create_session, terminal_kill, terminal_resize,
    terminal_set_replay_mode, terminal_write,
};

const INTERACTION_LOCK_REASON_WORKTREE_CREATE: &str = "worktree-create";
const TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT: &str = "terminal-window-layout-changed";
const TERMINAL_WORKSPACE_RESTORED_EVENT: &str = "terminal-workspace-restored";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TerminalWindowLayoutChangedPayload {
    project_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    project_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    window_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    revision: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    updated_at: Option<i64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    change_type: Option<String>,
    deleted: bool,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct TerminalWorkspaceRestoredPayload {
    project_path: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    project_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    window_id: Option<String>,
    restored_at: i64,
    imported_from_legacy: bool,
}

fn now_unix_millis() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(duration) => duration.as_millis() as i64,
        Err(_) => 0,
    }
}

fn terminal_layout_runtime_loaded_flag() -> &'static Mutex<bool> {
    static LOADED: OnceLock<Mutex<bool>> = OnceLock::new();
    LOADED.get_or_init(|| Mutex::new(false))
}

fn ensure_terminal_layout_runtime_loaded(app: &AppHandle) -> Result<(), String> {
    let mut loaded = terminal_layout_runtime_loaded_flag()
        .lock()
        .map_err(|_| "terminal runtime layout 初始化锁已损坏".to_string())?;
    if *loaded {
        return Ok(());
    }
    let snapshots = storage::load_all_terminal_layout_snapshots(app)?;
    crate::terminal_runtime::shared_runtime().import_layout_snapshots(snapshots)?;
    *loaded = true;
    Ok(())
}

fn emit_terminal_window_layout_changed_event(
    app: &AppHandle,
    project_path: String,
    project_id: Option<String>,
    window_id: Option<String>,
    revision: Option<i64>,
    updated_at: Option<i64>,
    change_type: Option<&str>,
    deleted: bool,
) {
    let payload = TerminalWindowLayoutChangedPayload {
        project_path,
        project_id,
        window_id,
        revision,
        updated_at,
        change_type: change_type.map(|value| value.to_string()),
        deleted,
    };

    if let Err(error) = app.emit(TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT, payload.clone()) {
        log::warn!("发送 {} 失败: {}", TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT, error);
    }
    web_event_bus::publish(TERMINAL_WINDOW_LAYOUT_CHANGED_EVENT, &payload);
}

fn emit_terminal_workspace_restored_event(
    app: &AppHandle,
    project_path: String,
    project_id: Option<String>,
    window_id: Option<String>,
    imported_from_legacy: bool,
) {
    let payload = TerminalWorkspaceRestoredPayload {
        project_path,
        project_id,
        window_id,
        restored_at: now_unix_millis(),
        imported_from_legacy,
    };

    if let Err(error) = app.emit(TERMINAL_WORKSPACE_RESTORED_EVENT, payload.clone()) {
        log::warn!("发送 {} 失败: {}", TERMINAL_WORKSPACE_RESTORED_EVENT, error);
    }
    web_event_bus::publish(TERMINAL_WORKSPACE_RESTORED_EVENT, &payload);
}

#[tauri::command]
/// 读取应用状态。
fn load_app_state(app: AppHandle) -> Result<AppStateFile, String> {
    log_command_result("load_app_state", || storage::load_app_state(&app))
}

#[tauri::command]
/// 保存应用状态。
fn save_app_state(app: AppHandle, state: AppStateFile) -> Result<(), String> {
    log_command_result("save_app_state", || storage::save_app_state(&app, &state))
}

#[tauri::command]
/// 读取项目缓存列表。
fn load_projects(app: AppHandle) -> Result<Vec<Project>, String> {
    log_command_result("load_projects", || storage::load_projects(&app))
}

#[tauri::command]
/// 扫描并返回全局可用的 Skills 列表。
fn list_global_skills() -> Result<GlobalSkillsSnapshot, String> {
    log_command_result("list_global_skills", skills::list_global_skills)
}

#[tauri::command]
/// 安装全局 Skill（参考开源 skills 的安装流程，在应用内执行）。
fn install_global_skill(
    request: GlobalSkillInstallRequest,
) -> Result<GlobalSkillInstallResult, String> {
    let source = request.source.clone();
    let skill_count = request.skill_names.len();
    let agent_count = request.agent_ids.len();
    log_command_result("install_global_skill", move || {
        log::info!(
            "install_global_skill source={} skills={} agents={}",
            source,
            skill_count,
            agent_count
        );
        skills::install_global_skill(request)
    })
}

#[tauri::command]
/// 从指定 Agent 卸载全局 Skill。
fn uninstall_global_skill(
    request: GlobalSkillUninstallRequest,
) -> Result<GlobalSkillInstallResult, String> {
    let agent_id = request.agent_id.clone();
    let skill_name = request.skill_name.clone();
    log_command_result("uninstall_global_skill", move || {
        log::info!(
            "uninstall_global_skill skill={} agent={}",
            skill_name,
            agent_id
        );
        skills::uninstall_global_skill(request)
    })
}

#[tauri::command]
/// 保存项目缓存列表。
fn save_projects(app: AppHandle, projects: Vec<Project>) -> Result<(), String> {
    log_command_result("save_projects", || storage::save_projects(&app, &projects))
}

#[tauri::command]
/// 扫描工作目录，发现项目路径。
fn discover_projects(directories: Vec<String>) -> Vec<String> {
    log_command("discover_projects", || {
        log::info!("discover_projects directories={}", directories.len());
        project_loader::discover_projects(&directories)
    })
}

#[tauri::command]
/// 构建项目列表并补齐元数据。
fn build_projects(paths: Vec<String>, existing: Vec<Project>) -> Vec<Project> {
    log_command("build_projects", || {
        log::info!(
            "build_projects paths={} existing={}",
            paths.len(),
            existing.len()
        );
        project_loader::build_projects(&paths, &existing)
    })
}

#[tauri::command]
/// 获取分支列表。
fn list_branches(base_path: String) -> Vec<BranchListItem> {
    log_command("list_branches", || {
        log::info!("list_branches base_path={}", base_path);
        git_ops::list_branches(&base_path)
    })
}

#[tauri::command]
/// 判断路径是否为 Git 仓库（以 `<path>/.git` 是否存在为准）。
fn git_is_repo(path: String) -> bool {
    log_command("git_is_repo", || {
        log::info!("git_is_repo path={}", path);
        git_ops::is_git_repo(&path)
    })
}

#[tauri::command]
/// 获取 Git 仓库状态（分支 + staged/unstaged/untracked）。
fn git_get_status(path: String) -> Result<GitRepoStatus, String> {
    log_command_result("git_get_status", || {
        log::info!("git_get_status path={}", path);
        git_ops::get_repo_status(&path)
    })
}

#[tauri::command]
/// 获取单文件对比内容（original/modified），用于 UI 渲染对比视图。
fn git_get_diff_contents(
    path: String,
    relative_path: String,
    staged: bool,
    old_relative_path: Option<String>,
) -> Result<GitDiffContents, String> {
    log_command_result("git_get_diff_contents", || {
        log::info!(
            "git_get_diff_contents path={} file={} staged={}",
            path,
            relative_path,
            staged
        );
        git_ops::get_diff_contents(&path, &relative_path, staged, old_relative_path.as_deref())
    })
}

#[tauri::command]
/// 暂存文件（git add）。
fn git_stage_files(path: String, relative_paths: Vec<String>) -> Result<(), String> {
    log_command_result("git_stage_files", || {
        log::info!(
            "git_stage_files path={} files={}",
            path,
            relative_paths.len()
        );
        git_ops::stage_files(&path, &relative_paths)
    })
}

#[tauri::command]
/// 取消暂存（git reset HEAD --）。
fn git_unstage_files(path: String, relative_paths: Vec<String>) -> Result<(), String> {
    log_command_result("git_unstage_files", || {
        log::info!(
            "git_unstage_files path={} files={}",
            path,
            relative_paths.len()
        );
        git_ops::unstage_files(&path, &relative_paths)
    })
}

#[tauri::command]
/// 丢弃未暂存修改（git checkout --）。
fn git_discard_files(path: String, relative_paths: Vec<String>) -> Result<(), String> {
    log_command_result("git_discard_files", || {
        log::info!(
            "git_discard_files path={} files={}",
            path,
            relative_paths.len()
        );
        git_ops::discard_files(&path, &relative_paths)
    })
}

#[tauri::command]
/// 提交已暂存改动。
fn git_commit(path: String, message: String) -> Result<(), String> {
    log_command_result("git_commit", || {
        log::info!("git_commit path={} message_size={}", path, message.len());
        git_ops::commit(&path, &message)
    })
}

#[tauri::command]
/// 切换分支（git checkout <branch>）。
fn git_checkout_branch(path: String, branch: String) -> Result<(), String> {
    log_command_result("git_checkout_branch", || {
        log::info!("git_checkout_branch path={} branch={}", path, branch);
        git_ops::checkout_branch(&path, &branch)
    })
}

#[tauri::command]
/// 删除本地分支（git branch -d/-D）。
fn git_delete_branch(path: String, branch: String, force: bool) -> Result<(), String> {
    log_command_result("git_delete_branch", || {
        log::info!(
            "git_delete_branch path={} branch={} force={}",
            path,
            branch,
            force
        );
        git_ops::delete_branch(&path, &branch, force)
    })
}

#[tauri::command]
/// 创建 Git worktree。
fn git_worktree_add(
    path: String,
    branch: String,
    create_branch: bool,
    target_path: Option<String>,
) -> Result<GitWorktreeAddResult, String> {
    log_command_result("git_worktree_add", || {
        log::info!(
            "git_worktree_add path={} target_path={} branch={} create_branch={}",
            path,
            target_path.as_deref().unwrap_or("<auto>"),
            branch,
            create_branch
        );
        git_ops::add_worktree(&path, target_path.as_deref(), &branch, create_branch, None)
    })
}

#[tauri::command]
/// 列出仓库下已有 worktree（不包含主仓库目录）。
fn git_worktree_list(path: String) -> Result<Vec<GitWorktreeListItem>, String> {
    log_command_result("git_worktree_list", || {
        log::info!("git_worktree_list path={}", path);
        git_ops::list_worktrees(&path)
    })
}

#[tauri::command]
/// 删除 Git worktree（git worktree remove）。
fn git_worktree_remove(path: String, worktree_path: String, force: bool) -> Result<(), String> {
    log_command_result("git_worktree_remove", || {
        log::info!(
            "git_worktree_remove path={} worktree_path={} force={}",
            path,
            worktree_path,
            force
        );
        git_ops::remove_worktree(&path, &worktree_path, force)
    })
}

#[tauri::command]
/// 查询当前全局交互锁状态。
fn get_interaction_lock_state(
    state: State<interaction_lock::InteractionLockState>,
) -> InteractionLockPayload {
    state.snapshot()
}

#[tauri::command]
/// 启动后台 worktree 初始化任务（快速返回 jobId）。
fn worktree_init_start(
    app: AppHandle,
    state: State<worktree_init::WorktreeInitState>,
    request: WorktreeInitStartRequest,
) -> Result<WorktreeInitStartResult, String> {
    log_command_result("worktree_init_start", || {
        log::info!(
            "worktree_init_start project_id={} path={} branch={} base_branch={} create_branch={}",
            request.project_id,
            request.project_path,
            request.branch,
            request.base_branch.as_deref().unwrap_or("<none>"),
            request.create_branch
        );
        state.start(&app, request)
    })
}

#[tauri::command]
/// 非阻塞式创建 worktree：快速返回 jobId，同时在后台持有全局交互锁直到任务结束。
fn worktree_init_create(
    app: AppHandle,
    state: State<worktree_init::WorktreeInitState>,
    interaction_lock: State<interaction_lock::InteractionLockState>,
    request: WorktreeInitStartRequest,
) -> Result<WorktreeInitStartResult, String> {
    log_command_result("worktree_init_create", || {
        log::info!(
            "worktree_init_create project_id={} path={} branch={} base_branch={} create_branch={}",
            request.project_id,
            request.project_path,
            request.branch,
            request.base_branch.as_deref().unwrap_or("<none>"),
            request.create_branch
        );

        let started = state.start(&app, request)?;
        let job_id = started.job_id.clone();
        let query = WorktreeInitStatusQuery {
            project_id: Some(started.project_id.clone()),
            project_path: Some(started.project_path.clone()),
        };

        let app_for_thread = app.clone();
        let state_for_thread = state.inner().clone();
        let lock_for_thread = interaction_lock.inner().clone();

        thread::spawn(move || {
            let _lock_guard = lock_for_thread.lock(
                &app_for_thread,
                Some(INTERACTION_LOCK_REASON_WORKTREE_CREATE.to_string()),
            );

            loop {
                match state_for_thread.query_status(query.clone()) {
                    Ok(statuses) => {
                        let is_terminal = statuses
                            .into_iter()
                            .find(|item| item.job_id == job_id)
                            .map(|item| {
                                matches!(
                                    item.step,
                                    WorktreeInitStep::Ready
                                        | WorktreeInitStep::Failed
                                        | WorktreeInitStep::Cancelled
                                )
                            })
                            .unwrap_or(false);
                        if is_terminal {
                            break;
                        }
                    }
                    Err(error) => {
                        log::warn!(
                            "查询 worktree_init_create 任务状态失败，job_id={}: {}",
                            job_id,
                            error
                        );
                    }
                }

                thread::sleep(Duration::from_millis(200));
            }
        });

        Ok(started)
    })
}

#[tauri::command]
/// 阻塞式创建 worktree：仅在创建成功或失败后返回。
///
/// 创建期间会启用全局交互锁，拦截所有窗口交互与关闭/退出请求。
fn worktree_init_create_blocking(
    app: AppHandle,
    state: State<worktree_init::WorktreeInitState>,
    interaction_lock: State<interaction_lock::InteractionLockState>,
    request: WorktreeInitStartRequest,
) -> Result<WorktreeInitCreateBlockingResult, String> {
    log_command_result("worktree_init_create_blocking", || {
        let _lock_guard = interaction_lock.lock(
            &app,
            Some(INTERACTION_LOCK_REASON_WORKTREE_CREATE.to_string()),
        );

        let started = state.start(&app, request)?;
        let job_id = started.job_id.clone();
        let query = WorktreeInitStatusQuery {
            project_id: Some(started.project_id.clone()),
            project_path: Some(started.project_path.clone()),
        };

        loop {
            let statuses = state.query_status(query.clone())?;
            let matched = statuses.into_iter().find(|item| item.job_id == job_id);
            let Some(status) = matched else {
                thread::sleep(Duration::from_millis(200));
                continue;
            };

            match status.step {
                WorktreeInitStep::Ready => {
                    return Ok(WorktreeInitCreateBlockingResult {
                        job_id: status.job_id,
                        project_id: status.project_id,
                        project_path: status.project_path,
                        worktree_path: status.worktree_path,
                        branch: status.branch,
                        base_branch: status.base_branch,
                        message: status.message,
                        warning: status.error,
                    });
                }
                WorktreeInitStep::Failed => {
                    return Err(status.error.unwrap_or_else(|| status.message));
                }
                WorktreeInitStep::Cancelled => {
                    return Err(status.message);
                }
                _ => {
                    thread::sleep(Duration::from_millis(200));
                }
            }
        }
    })
}

#[tauri::command]
/// 请求取消后台 worktree 初始化任务。
fn worktree_init_cancel(
    app: AppHandle,
    state: State<worktree_init::WorktreeInitState>,
    job_id: String,
) -> Result<WorktreeInitCancelResult, String> {
    log_command_result("worktree_init_cancel", || {
        log::info!("worktree_init_cancel job_id={}", job_id);
        state.cancel(&app, &job_id)
    })
}

#[tauri::command]
/// 重试失败/取消的 worktree 初始化任务。
fn worktree_init_retry(
    app: AppHandle,
    state: State<worktree_init::WorktreeInitState>,
    request: WorktreeInitRetryRequest,
) -> Result<WorktreeInitStartResult, String> {
    log_command_result("worktree_init_retry", || {
        log::info!("worktree_init_retry job_id={}", request.job_id);
        state.retry(&app, request)
    })
}

#[tauri::command]
/// 查询 worktree 初始化任务状态。
fn worktree_init_status(
    state: State<worktree_init::WorktreeInitState>,
    query: Option<WorktreeInitStatusQuery>,
) -> Result<Vec<WorktreeInitJobStatus>, String> {
    log_command_result("worktree_init_status", || {
        state.query_status(query.unwrap_or(WorktreeInitStatusQuery {
            project_id: None,
            project_path: None,
        }))
    })
}

#[tauri::command]
/// 在文件管理器中定位路径。
fn open_in_finder(path: String) -> Result<(), String> {
    log_command_result("open_in_finder", || {
        log::info!("open_in_finder path={}", path);
        system::open_in_finder(&path)
    })
}

#[tauri::command]
/// 使用外部编辑器打开路径。
fn open_in_editor(params: EditorOpenParams) -> Result<(), String> {
    log_command_result("open_in_editor", || {
        log::info!("open_in_editor path={}", params.path);
        system::open_in_editor(params)
    })
}

#[tauri::command]
/// 解析当前用户 Home 目录（用于 Web 端路径展开）。
fn resolve_home_dir(app: AppHandle) -> Result<String, String> {
    app.path()
        .home_dir()
        .map(|path| path.to_string_lossy().to_string())
        .map_err(|error| format!("解析用户目录失败: {error}"))
}

#[tauri::command]
/// 列出全局共享脚本（优先读取 manifest，否则回退目录扫描）。
fn list_shared_scripts(
    app: AppHandle,
    root: Option<String>,
) -> Result<Vec<SharedScriptEntry>, String> {
    log_command_result("list_shared_scripts", || {
        shared_scripts::list_shared_scripts(&app, root.as_deref())
    })
}

#[tauri::command]
/// 保存全局共享脚本清单（manifest.json）。
fn save_shared_scripts_manifest(
    app: AppHandle,
    root: Option<String>,
    scripts: Vec<SharedScriptManifestScript>,
) -> Result<(), String> {
    log_command_result("save_shared_scripts_manifest", || {
        shared_scripts::save_shared_scripts_manifest(&app, root.as_deref(), &scripts)
    })
}

#[tauri::command]
/// 恢复内置共享脚本预设（仅补齐缺失脚本，不覆盖已有条目）。
fn restore_shared_script_presets(
    app: AppHandle,
    root: Option<String>,
) -> Result<SharedScriptPresetRestoreResult, String> {
    log_command_result("restore_shared_script_presets", || {
        shared_scripts::restore_shared_script_presets(&app, root.as_deref())
    })
}

#[tauri::command]
/// 读取全局共享脚本文件内容。
fn read_shared_script_file(
    app: AppHandle,
    root: Option<String>,
    relative_path: String,
) -> Result<String, String> {
    log_command_result("read_shared_script_file", || {
        shared_scripts::read_shared_script_file(&app, root.as_deref(), &relative_path)
    })
}

#[tauri::command]
/// 写入全局共享脚本文件内容。
fn write_shared_script_file(
    app: AppHandle,
    root: Option<String>,
    relative_path: String,
    content: String,
) -> Result<(), String> {
    log_command_result("write_shared_script_file", || {
        shared_scripts::write_shared_script_file(&app, root.as_deref(), &relative_path, &content)
    })
}

#[tauri::command]
/// 复制文本到剪贴板。
fn copy_to_clipboard(app: AppHandle, content: String) -> Result<(), String> {
    log_command_result("copy_to_clipboard", || {
        log::info!("copy_to_clipboard size={}", content.len());
        system::copy_to_clipboard(&app, &content)
    })
}

#[tauri::command]
/// 发送系统通知。
fn send_system_notification(params: SystemNotificationParams) -> Result<(), String> {
    log_command_result("send_system_notification", || {
        log::info!("send_system_notification title={}", params.title);
        system::send_system_notification(params)
    })
}

#[tauri::command]
/// 读取项目备注内容。
fn read_project_notes(path: String) -> Result<Option<String>, String> {
    log_command_result("read_project_notes", || {
        log::info!("read_project_notes path={}", path);
        notes::read_notes(&path)
    })
}

#[tauri::command]
/// 批量读取项目备注预览（首行文本）。
fn read_project_notes_previews(paths: Vec<String>) -> Vec<ProjectNotesPreview> {
    log_command("read_project_notes_previews", || {
        log::info!("read_project_notes_previews paths={}", paths.len());
        notes::read_notes_previews(&paths)
    })
}

#[tauri::command]
/// 写入项目备注内容。
fn write_project_notes(path: String, notes: Option<String>) -> Result<(), String> {
    log_command_result("write_project_notes", || {
        let note_len = notes.as_ref().map(|value| value.len()).unwrap_or(0);
        log::info!("write_project_notes path={} size={}", path, note_len);
        notes::write_notes(&path, notes)
    })
}

#[tauri::command]
/// 读取项目 Todo 内容。
fn read_project_todo(path: String) -> Result<Option<String>, String> {
    log_command_result("read_project_todo", || {
        log::info!("read_project_todo path={}", path);
        notes::read_todo(&path)
    })
}

#[tauri::command]
/// 写入项目 Todo 内容。
fn write_project_todo(path: String, todo: Option<String>) -> Result<(), String> {
    log_command_result("write_project_todo", || {
        let todo_len = todo.as_ref().map(|value| value.len()).unwrap_or(0);
        log::info!("write_project_todo path={} size={}", path, todo_len);
        notes::write_todo(&path, todo)
    })
}

#[tauri::command]
/// 列出项目内的 Markdown 文件。
fn list_project_markdown_files(path: String) -> Result<Vec<MarkdownFileEntry>, String> {
    log_command_result("list_project_markdown_files", || {
        log::info!("list_project_markdown_files path={}", path);
        markdown::list_markdown_files(&path)
    })
}

#[tauri::command]
/// 读取项目内指定 Markdown 内容。
fn read_project_markdown_file(path: String, relative_path: String) -> Result<String, String> {
    log_command_result("read_project_markdown_file", || {
        log::info!(
            "read_project_markdown_file path={} file={}",
            path,
            relative_path
        );
        markdown::read_markdown_file(&path, &relative_path)
    })
}

#[tauri::command]
/// 列出项目内指定目录的直接子项（文件/文件夹）。
fn list_project_dir_entries(
    path: String,
    relative_path: String,
    show_hidden: bool,
) -> FsListResponse {
    log_command("list_project_dir_entries", || {
        log::info!(
            "list_project_dir_entries path={} dir={} show_hidden={}",
            path,
            relative_path,
            show_hidden
        );
        filesystem::list_dir_entries(&path, &relative_path, show_hidden)
    })
}

#[tauri::command]
/// 读取项目内指定文件内容（只读预览）。
fn read_project_file(path: String, relative_path: String) -> FsReadResponse {
    log_command("read_project_file", || {
        log::info!("read_project_file path={} file={}", path, relative_path);
        filesystem::read_file(&path, &relative_path)
    })
}

#[tauri::command]
/// 写入项目内指定文件内容（文本编辑保存）。
fn write_project_file(path: String, relative_path: String, content: String) -> FsWriteResponse {
    log_command("write_project_file", || {
        log::info!(
            "write_project_file path={} file={} size={}",
            path,
            relative_path,
            content.len()
        );
        filesystem::write_file(&path, &relative_path, &content)
    })
}

#[tauri::command]
fn collect_git_daily(paths: Vec<String>, identities: Vec<GitIdentity>) -> Vec<GitDailyResult> {
    log_command("collect_git_daily", || git_daily::collect_git_daily(&paths, &identities))
}

#[tauri::command]
fn load_heatmap_cache(app: AppHandle) -> Result<HeatmapCacheFile, String> {
    log_command_result("load_heatmap_cache", || storage::load_heatmap_cache(&app))
}

#[tauri::command]
fn save_heatmap_cache(app: AppHandle, cache: HeatmapCacheFile) -> Result<(), String> {
    log_command_result("save_heatmap_cache", || {
        storage::save_heatmap_cache(&app, &cache)
    })
}

#[tauri::command]
fn load_terminal_layout_snapshot(
    app: AppHandle,
    project_path: String,
) -> Result<Option<JsonValue>, String> {
    log_command_result("load_terminal_layout_snapshot", || {
        log::info!("load_terminal_layout_snapshot path={}", project_path);
        ensure_terminal_layout_runtime_loaded(&app)?;
        let snapshot = crate::terminal_runtime::shared_runtime()
            .load_layout_snapshot_by_project_path(&project_path)?;
        if let Some(snapshot_obj) = snapshot.as_ref().and_then(|value| value.as_object()) {
            emit_terminal_workspace_restored_event(
                &app,
                project_path.clone(),
                snapshot_obj.get("projectId").and_then(|value| value.as_str()).map(|value| value.to_string()),
                snapshot_obj.get("windowId").and_then(|value| value.as_str()).map(|value| value.to_string()),
                snapshot_obj
                    .get("importedFromLegacy")
                    .and_then(|value| value.as_bool())
                    .unwrap_or(false),
            );
        }
        Ok(snapshot)
    })
}

#[tauri::command]
fn save_terminal_layout_snapshot(
    app: AppHandle,
    project_path: String,
    snapshot: JsonValue,
    _source_client_id: Option<String>,
) -> Result<JsonValue, String> {
    log_command_result("save_terminal_layout_snapshot", || {
        log::info!("save_terminal_layout_snapshot path={}", project_path);
        ensure_terminal_layout_runtime_loaded(&app)?;
        let snapshot = storage::normalize_terminal_layout_snapshot_for_store(&project_path, snapshot);
        crate::terminal_runtime::shared_runtime()
            .upsert_layout_snapshot(project_path.clone(), snapshot.clone())?;
        let snapshot = storage::save_terminal_layout_snapshot(&app, &project_path, snapshot)?;
        let snapshot_obj = snapshot.as_object().cloned().unwrap_or_default();
        emit_terminal_window_layout_changed_event(
            &app,
            project_path.clone(),
            snapshot_obj.get("projectId").and_then(|value| value.as_str()).map(|value| value.to_string()),
            snapshot_obj.get("windowId").and_then(|value| value.as_str()).map(|value| value.to_string()),
            snapshot_obj.get("revision").and_then(|value| value.as_i64()),
            snapshot_obj.get("updatedAt").and_then(|value| value.as_i64()),
            Some("snapshotSaved"),
            false,
        );
        Ok(snapshot)
    })
}

#[tauri::command]
fn delete_terminal_layout_snapshot(
    app: AppHandle,
    project_path: String,
    _source_client_id: Option<String>,
) -> Result<(), String> {
    log_command_result("delete_terminal_layout_snapshot", || {
        log::info!("delete_terminal_layout_snapshot path={}", project_path);
        ensure_terminal_layout_runtime_loaded(&app)?;
        let _ = crate::terminal_runtime::shared_runtime()
            .delete_layout_snapshot(&project_path)?;
        storage::delete_terminal_layout_snapshot(&app, &project_path)?;
        emit_terminal_window_layout_changed_event(
            &app,
            project_path.clone(),
            None,
            None,
            None,
            Some(now_unix_millis()),
            Some("snapshotDeleted"),
            true,
        );
        Ok(())
    })
}

#[tauri::command]
fn list_terminal_layout_snapshot_summaries(
    app: AppHandle,
) -> Result<Vec<TerminalLayoutSnapshotSummary>, String> {
    log_command_result("list_terminal_layout_snapshot_summaries", || {
        storage::list_terminal_layout_snapshot_summaries(&app)
    })
}

#[tauri::command]
fn quick_command_runtime_snapshot(project_path: Option<String>) -> JsonValue {
    let jobs = crate::terminal_runtime::shared_runtime()
        .list_quick_commands(project_path.as_deref())
        .unwrap_or_default();
    let updated_at = jobs.iter().map(|job| job.updated_at).max().unwrap_or_default();
    json!({
        "projectPath": project_path.unwrap_or_default(),
        "jobs": jobs.into_iter().map(|job| {
            json!({
                "jobId": job.job_id.as_str(),
                "projectId": job.project_id,
                "projectPath": job.project_path,
                "scriptId": job.script_id,
                "command": job.command,
                "windowLabel": JsonValue::Null,
                "state": job.state,
                "createdAt": job.created_at,
                "updatedAt": job.updated_at,
                "exitCode": job.exit_code,
                "error": job.error,
            })
        }).collect::<Vec<_>>(),
        "updatedAt": updated_at,
    })
}

#[tauri::command]
fn devhaven_identify(
    state: State<AgentControlState>,
    terminal_session_id: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
) -> Result<ControlPlaneIdentifyResult, String> {
    log_command_result("devhaven_identify", || {
        agent_control::identify_control_plane(
            state,
            DevHavenIdentifyRequest {
                terminal_session_id,
                workspace_id,
                pane_id,
                surface_id,
            },
        )
    })
}

#[tauri::command]
fn devhaven_tree(
    state: State<AgentControlState>,
    project_path: Option<String>,
    workspace_id: Option<String>,
) -> Result<Option<ControlPlaneTree>, String> {
    log_command_result("devhaven_tree", || {
        agent_control::tree_control_plane(
            state,
            DevHavenTreeRequest {
                project_path,
                workspace_id,
            },
        )
    })
}

#[tauri::command]
fn devhaven_notify(
    app: AppHandle,
    state: State<AgentControlState>,
    terminal_session_id: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    agent_session_id: Option<String>,
    project_path: Option<String>,
    title: Option<String>,
    message: String,
    level: Option<String>,
) -> Result<agent_control::NotificationRecord, String> {
    log_command_result("devhaven_notify", || {
        let record = agent_control::notify_control_plane(
            &app,
            state.clone(),
            DevHavenNotifyRequest {
                terminal_session_id,
                workspace_id,
                pane_id,
                surface_id,
                agent_session_id,
                project_path,
                title,
                message,
                level,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(record)
    })
}

#[tauri::command]
fn devhaven_notify_target(
    app: AppHandle,
    state: State<AgentControlState>,
    terminal_session_id: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    agent_session_id: Option<String>,
    project_path: Option<String>,
    title: Option<String>,
    message: String,
    level: Option<String>,
) -> Result<agent_control::NotificationRecord, String> {
    log_command_result("devhaven_notify_target", || {
        let record = agent_control::notify_target_control_plane(
            &app,
            state.clone(),
            DevHavenNotifyTargetRequest {
                terminal_session_id,
                workspace_id,
                pane_id,
                surface_id,
                agent_session_id,
                project_path,
                title,
                message,
                level,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(record)
    })
}

#[tauri::command]
fn devhaven_agent_session_event(
    app: AppHandle,
    state: State<AgentControlState>,
    agent_session_id: Option<String>,
    terminal_session_id: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    provider: String,
    status: AgentSessionStatus,
    project_path: Option<String>,
    cwd: Option<String>,
    message: Option<String>,
) -> Result<agent_control::AgentSessionRecord, String> {
    log_command_result("devhaven_agent_session_event", || {
        let record = agent_control::upsert_agent_session_event(
            &app,
            state.clone(),
            DevHavenAgentSessionEventRequest {
                agent_session_id,
                terminal_session_id,
                workspace_id,
                pane_id,
                surface_id,
                provider,
                status,
                project_path,
                cwd,
                message,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(record)
    })
}

#[tauri::command]
fn devhaven_mark_notification_read(
    app: AppHandle,
    state: State<AgentControlState>,
    notification_id: String,
) -> Result<(), String> {
    log_command_result("devhaven_mark_notification_read", || {
        agent_control::mark_notification_read_state(
            &app,
            state.clone(),
            NotificationMutationRequest { notification_id },
            true,
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)
    })
}

#[tauri::command]
fn devhaven_mark_notification_unread(
    app: AppHandle,
    state: State<AgentControlState>,
    notification_id: String,
) -> Result<(), String> {
    log_command_result("devhaven_mark_notification_unread", || {
        agent_control::mark_notification_read_state(
            &app,
            state.clone(),
            NotificationMutationRequest { notification_id },
            false,
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)
    })
}

#[tauri::command]
fn devhaven_set_status(
    app: AppHandle,
    state: State<AgentControlState>,
    key: String,
    value: String,
    icon: Option<String>,
    color: Option<String>,
    terminal_session_id: Option<String>,
    project_path: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
) -> Result<agent_control::StatusPrimitiveRecord, String> {
    log_command_result("devhaven_set_status", || {
        let record = agent_control::set_status_control_plane(
            &app,
            state.clone(),
            DevHavenSetStatusRequest {
                key,
                value,
                icon,
                color,
                terminal_session_id,
                project_path,
                workspace_id,
                pane_id,
                surface_id,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(record)
    })
}

#[tauri::command]
fn devhaven_clear_status(
    app: AppHandle,
    state: State<AgentControlState>,
    key: String,
    terminal_session_id: Option<String>,
    project_path: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
) -> Result<bool, String> {
    log_command_result("devhaven_clear_status", || {
        let removed = agent_control::clear_status_control_plane(
            &app,
            state.clone(),
            PrimitiveKeyRequest {
                key,
                terminal_session_id,
                project_path,
                workspace_id,
                pane_id,
                surface_id,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(removed)
    })
}

#[tauri::command]
fn devhaven_set_agent_pid(
    app: AppHandle,
    state: State<AgentControlState>,
    key: String,
    pid: i32,
    terminal_session_id: Option<String>,
    project_path: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
) -> Result<agent_control::AgentPidPrimitiveRecord, String> {
    log_command_result("devhaven_set_agent_pid", || {
        let record = agent_control::set_agent_pid_control_plane(
            &app,
            state.clone(),
            DevHavenSetAgentPidRequest {
                key,
                pid,
                terminal_session_id,
                project_path,
                workspace_id,
                pane_id,
                surface_id,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(record)
    })
}

#[tauri::command]
fn devhaven_clear_agent_pid(
    app: AppHandle,
    state: State<AgentControlState>,
    key: String,
    terminal_session_id: Option<String>,
    project_path: Option<String>,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
) -> Result<bool, String> {
    log_command_result("devhaven_clear_agent_pid", || {
        let removed = agent_control::clear_agent_pid_control_plane(
            &app,
            state.clone(),
            PrimitiveKeyRequest {
                key,
                terminal_session_id,
                project_path,
                workspace_id,
                pane_id,
                surface_id,
            },
        )?;
        let snapshot = state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(removed)
    })
}

#[tauri::command]
fn agent_spawn(
    app: AppHandle,
    launcher: State<AgentLauncherState>,
    control_state: State<AgentControlState>,
    provider: String,
    project_path: String,
    workspace_id: Option<String>,
    pane_id: Option<String>,
    surface_id: Option<String>,
    terminal_session_id: Option<String>,
    cwd: Option<String>,
) -> Result<AgentSpawnResult, String> {
    log_command_result("agent_spawn", || {
        let result = crate::agent_launcher::spawn_agent_command(
            &app,
            &launcher,
            &control_state,
            crate::agent_launcher::AgentSpawnInput {
                provider,
                project_path,
                workspace_id,
                pane_id,
                surface_id,
                terminal_session_id,
                cwd,
            },
        )?;
        let snapshot = control_state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)?;
        Ok(result)
    })
}

#[tauri::command]
fn agent_stop(
    app: AppHandle,
    launcher: State<AgentLauncherState>,
    control_state: State<AgentControlState>,
    agent_session_id: String,
    force: Option<bool>,
) -> Result<(), String> {
    log_command_result("agent_stop", || {
        crate::agent_launcher::stop_agent_command(
            &app,
            &launcher,
            &control_state,
            agent_session_id,
            force.unwrap_or(false),
        )?;
        let snapshot = control_state.export_control_plane_file()?;
        storage::save_agent_control_plane_store(&app, snapshot)
    })
}

#[tauri::command]
fn agent_runtime_diagnose(
    launcher: State<AgentLauncherState>,
    control_state: State<AgentControlState>,
) -> Result<AgentRuntimeDiagnoseResult, String> {
    log_command_result("agent_runtime_diagnose", || {
        crate::agent_launcher::diagnose_agent_runtime_command(launcher, control_state)
    })
}

#[tauri::command]
fn apply_web_server_config(
    app: AppHandle,
    runtime: State<web_server::WebServerRuntime>,
) -> Result<(), String> {
    log_command_result("apply_web_server_config", || {
        web_server::apply_config(app, runtime.inner().clone())
    })
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
/// 启动 Tauri 应用。
pub fn run() {
    let app = tauri::Builder::default()
        .plugin(
            tauri_plugin_log::Builder::new()
                .targets([
                    Target::new(TargetKind::Stdout),
                    Target::new(TargetKind::LogDir { file_name: None }),
                ])
                .level(log::LevelFilter::Info)
                .build(),
        )
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .manage(AgentControlState::default())
        .manage(AgentLauncherState::default())
        .manage(TerminalState::default())
        .manage(QuickCommandManager::default())
        .manage(worktree_init::WorktreeInitState::default())
        .manage(interaction_lock::InteractionLockState::default())
        .manage(web_server::WebServerRuntime::default())
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                let locked = window
                    .app_handle()
                    .state::<interaction_lock::InteractionLockState>()
                    .is_locked();
                if locked {
                    api.prevent_close();
                }
            }
        })
        .setup(|app| {
            log::info!(
                "app start name={} version={}",
                app.package_info().name,
                app.package_info().version
            );
            if let Ok(path) = app.path().app_log_dir() {
                log::info!("log dir={}", path.display());
            }
            let app_handle = app.handle();
            let control_plane = storage::load_agent_control_plane_store(&app_handle)?;
            app_handle
                .state::<AgentControlState>()
                .replace_from_control_plane_file(control_plane)?;
            let web_runtime = app_handle
                .state::<web_server::WebServerRuntime>()
                .inner()
                .clone();
            web_server::ensure_started(app_handle.clone(), web_runtime);
            Ok(())
        })
        .invoke_handler(crate::devhaven_generate_tauri_handler!())
        .build(tauri::generate_context!())
        .expect("error while building tauri application");

    app.run(|app_handle, event| {
        if let tauri::RunEvent::ExitRequested { api, .. } = event {
            let locked = app_handle
                .state::<interaction_lock::InteractionLockState>()
                .is_locked();
            if locked {
                api.prevent_exit();
                return;
            }
            if let Err(error) = storage::flush_terminal_workspace_store(app_handle) {
                log::warn!("退出前刷盘终端工作区失败: {}", error);
            }
            let control_state = app_handle.state::<AgentControlState>();
            match control_state.export_control_plane_file() {
                Ok(snapshot) => {
                    if let Err(error) =
                        storage::save_agent_control_plane_store(app_handle, snapshot)
                    {
                        log::warn!("退出前同步 agent control plane 失败: {}", error);
                    }
                }
                Err(error) => {
                    log::warn!("退出前导出 agent control plane 失败: {}", error);
                }
            }
            if let Err(error) = storage::flush_agent_control_plane_store(app_handle) {
                log::warn!("退出前刷盘 agent control plane 失败: {}", error);
            }
        }
    });
}

fn log_command<T, F: FnOnce() -> T>(name: &str, action: F) -> T {
    let start = Instant::now();
    if should_log_command(name) {
        log::info!("command {} start", name);
    }
    let result = action();
    if should_log_command(name) {
        log::info!("command {} done {}ms", name, start.elapsed().as_millis());
    }
    result
}

fn log_command_result<T, E: std::fmt::Display, F: FnOnce() -> Result<T, E>>(
    name: &str,
    action: F,
) -> Result<T, E> {
    let start = Instant::now();
    if should_log_command(name) {
        log::info!("command {} start", name);
    }
    let result = action();
    match (&result, should_log_command(name)) {
        (Ok(_), true) => log::info!("command {} ok {}ms", name, start.elapsed().as_millis()),
        (Err(err), true) => log::error!(
            "command {} failed {}ms: {}",
            name,
            start.elapsed().as_millis(),
            err
        ),
        _ => {}
    }
    result
}

fn should_log_command(name: &str) -> bool {
    !matches!(name, "collect_git_daily")
}
