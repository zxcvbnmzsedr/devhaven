use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};
use std::time::Duration;

use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::{Map, Value as JsonValue, json};
use tauri::{AppHandle, Manager};

use crate::models::{
    AppStateFile, HeatmapCacheFile, Project, TerminalLayoutSnapshot,
    TerminalLayoutSnapshotSummary, TerminalWorkspacesFile,
};

// 终端工作区的 read-modify-write 需要串行化，避免并发覆盖。
fn terminal_workspace_rmw_mutex() -> &'static Mutex<()> {
    static TERMINAL_WORKSPACE_RMW_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
    TERMINAL_WORKSPACE_RMW_MUTEX.get_or_init(|| Mutex::new(()))
}

const TERMINAL_WORKSPACE_FLUSH_DEBOUNCE_MS: u64 = 250;

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

fn terminal_workspace_store() -> &'static Mutex<TerminalWorkspaceStoreState> {
    static TERMINAL_WORKSPACE_STORE: OnceLock<Mutex<TerminalWorkspaceStoreState>> =
        OnceLock::new();
    TERMINAL_WORKSPACE_STORE.get_or_init(|| Mutex::new(TerminalWorkspaceStoreState::default()))
}

#[derive(Debug, Clone)]
struct TerminalWorkspaceFlushSnapshot {
    revision: u64,
    workspaces: TerminalWorkspacesFile,
}

#[derive(Debug, Clone)]
struct TerminalWorkspaceStoreState {
    loaded: bool,
    workspaces: TerminalWorkspacesFile,
    dirty_revision: u64,
    flushed_revision: u64,
    flush_worker_running: bool,
}

impl Default for TerminalWorkspaceStoreState {
    fn default() -> Self {
        Self {
            loaded: false,
            workspaces: TerminalWorkspacesFile::default(),
            dirty_revision: 0,
            flushed_revision: 0,
            flush_worker_running: false,
        }
    }
}

impl TerminalWorkspaceStoreState {
    fn replace_loaded(&mut self, workspaces: TerminalWorkspacesFile, dirty: bool) {
        self.loaded = true;
        self.workspaces = workspaces;
        self.dirty_revision = if dirty { 1 } else { 0 };
        self.flushed_revision = 0;
        self.flush_worker_running = false;
    }

    fn ensure_loaded_with<F>(&mut self, loader: F) -> Result<(), String>
    where
        F: FnOnce() -> Result<TerminalWorkspacesFile, String>,
    {
        if self.loaded {
            return Ok(());
        }
        let (workspaces, dirty) = normalize_terminal_workspaces_file(loader()?)?;
        self.replace_loaded(workspaces, dirty);
        Ok(())
    }

    fn upsert_layout_snapshot(
        &mut self,
        project_path: String,
        snapshot: TerminalLayoutSnapshot,
    ) -> bool {
        let normalized = normalize_layout_snapshot_for_store(&project_path, snapshot);
        let changed = self.workspaces.workspaces.get(&project_path) != Some(&normalized);
        if changed {
            self.workspaces.workspaces.insert(project_path, normalized);
            self.dirty_revision += 1;
        }
        changed
    }

    fn delete_workspace(&mut self, project_path: &str) -> bool {
        let removed = self.workspaces.workspaces.remove(project_path).is_some();
        if removed {
            self.dirty_revision += 1;
        }
        removed
    }

    fn load_layout_snapshot(
        &mut self,
        project_path: &str,
    ) -> Result<Option<TerminalLayoutSnapshot>, String> {
        let current = match self.workspaces.workspaces.get(project_path) {
            Some(current) => current.clone(),
            None => return Ok(None),
        };
        if !is_layout_snapshot(&current) {
            return Err(format!(
                "缓存中存在未归一化的旧版 terminal workspace: {}",
                project_path
            ));
        }
        let normalized = normalize_layout_snapshot_for_store(project_path, current);
        if self.workspaces.workspaces.get(project_path) != Some(&normalized) {
            self.workspaces
                .workspaces
                .insert(project_path.to_string(), normalized.clone());
            self.dirty_revision += 1;
        }
        Ok(Some(normalized))
    }

    fn list_layout_summaries(&mut self) -> Result<Vec<TerminalLayoutSnapshotSummary>, String> {
        let keys: Vec<String> = self.workspaces.workspaces.keys().cloned().collect();
        let mut snapshots = Vec::new();
        for project_path in keys {
            if let Some(snapshot) = self.load_layout_snapshot(&project_path)? {
                snapshots.push((project_path, snapshot));
            }
        }
        Ok(build_terminal_layout_snapshot_summaries(&snapshots))
    }

    fn flush_snapshot(&self) -> Option<TerminalWorkspaceFlushSnapshot> {
        if self.dirty_revision <= self.flushed_revision {
            return None;
        }
        Some(TerminalWorkspaceFlushSnapshot {
            revision: self.dirty_revision,
            workspaces: self.workspaces.clone(),
        })
    }

    fn try_start_flush_worker(&mut self) -> bool {
        if self.flush_worker_running {
            return false;
        }
        self.flush_worker_running = true;
        true
    }

    fn try_start_flush_worker_if_dirty(&mut self) -> bool {
        self.flush_snapshot().is_some() && self.try_start_flush_worker()
    }

    fn mark_flush_complete(&mut self, revision: u64) -> bool {
        self.flushed_revision = self.flushed_revision.max(revision);
        if self.flushed_revision >= self.dirty_revision {
            self.flush_worker_running = false;
            return false;
        }
        true
    }

    fn mark_flush_failed(&mut self) {
        self.flush_worker_running = false;
    }
}

// 获取应用数据目录。
fn app_support_dir(app: &AppHandle) -> Result<PathBuf, String> {
    let home_dir = app
        .path()
        .home_dir()
        .map_err(|err| format!("无法获取用户目录: {err}"))?;
    Ok(home_dir.join(".devhaven"))
}

// 确保目录存在。
fn ensure_dir(path: &PathBuf) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|err| format!("无法创建目录: {err}"))
}

// 读取并反序列化 JSON 文件。
fn read_json<T: DeserializeOwned>(path: &PathBuf) -> Result<T, String> {
    let data = fs::read(path).map_err(|err| format!("无法读取文件: {err}"))?;
    serde_json::from_slice(&data).map_err(|err| format!("解析 JSON 失败: {err}"))
}

// 原子写入文件：先写临时文件，再 rename 覆盖目标文件。
fn write_file_atomic(path: &PathBuf, data: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("目标文件缺少父目录: {}", path.display()))?;
    let file_name = path
        .file_name()
        .ok_or_else(|| format!("目标文件缺少文件名: {}", path.display()))?
        .to_string_lossy()
        .to_string();
    let pid = std::process::id();
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or_default();

    for attempt in 0..8 {
        let temp_path = parent.join(format!(".{file_name}.tmp-{pid}-{timestamp}-{attempt}"));
        let mut file = match OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&temp_path)
        {
            Ok(file) => file,
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(err) => return Err(format!("创建临时文件失败: {err}")),
        };

        if let Err(err) = file.write_all(data).and_then(|_| file.sync_all()) {
            let _ = fs::remove_file(&temp_path);
            return Err(format!("写入临时文件失败: {err}"));
        }

        drop(file);
        fs::rename(&temp_path, path).map_err(|err| {
            let _ = fs::remove_file(&temp_path);
            format!("原子替换目标文件失败: {err}")
        })?;

        return Ok(());
    }

    Err("创建临时文件失败: 临时文件名冲突".to_string())
}

// 以易读格式写入 JSON。
fn write_json_pretty<T: Serialize>(path: &PathBuf, value: &T) -> Result<(), String> {
    let data =
        serde_json::to_vec_pretty(value).map_err(|err| format!("序列化 JSON 失败: {err}"))?;
    write_file_atomic(path, &data)
}

// 以紧凑格式写入 JSON。
fn write_json_compact<T: Serialize + ?Sized>(path: &PathBuf, value: &T) -> Result<(), String> {
    let data = serde_json::to_vec(value).map_err(|err| format!("序列化 JSON 失败: {err}"))?;
    write_file_atomic(path, &data)
}

fn load_terminal_workspaces_from_disk(app: &AppHandle) -> Result<TerminalWorkspacesFile, String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("terminal_workspaces.json");
    if !file_path.exists() {
        return Ok(TerminalWorkspacesFile::default());
    }
    read_json(&file_path)
}

fn save_terminal_workspaces_to_disk(
    app: &AppHandle,
    workspaces: &TerminalWorkspacesFile,
) -> Result<(), String> {
    let _guard = terminal_workspace_rmw_mutex()
        .lock()
        .map_err(|_| "终端工作区写入锁已损坏".to_string())?;
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("terminal_workspaces.json");
    write_json_pretty(&file_path, workspaces)
}

fn json_i64(value: Option<&JsonValue>) -> Option<i64> {
    value.and_then(|value| value.as_i64().or_else(|| value.as_f64().map(|number| number as i64)))
}

fn is_layout_snapshot(value: &JsonValue) -> bool {
    value.get("panes").is_some()
        && value.get("tabs").map(|tabs| tabs.is_array()).unwrap_or(false)
        && value.get("projectPath").and_then(|value| value.as_str()).is_some()
}

fn normalize_layout_snapshot_for_store(project_path: &str, snapshot: TerminalLayoutSnapshot) -> TerminalLayoutSnapshot {
    let mut snapshot = snapshot;
    let now = now_millis();
    let object = match &mut snapshot {
        JsonValue::Object(object) => object,
        _ => return json!({
            "version": 2,
            "projectPath": project_path,
            "tabs": [],
            "panes": {},
            "activeTabId": "",
            "updatedAt": now,
            "revision": now,
        }),
    };

    object.insert("version".to_string(), json!(2));
    object.insert("projectPath".to_string(), json!(project_path));

    let updated_at = json_i64(object.get("updatedAt")).unwrap_or(now);
    object.insert("updatedAt".to_string(), json!(updated_at));

    let revision = json_i64(object.get("revision")).unwrap_or(updated_at);
    object.insert("revision".to_string(), json!(revision));

    snapshot
}

fn normalize_terminal_workspaces_file(
    workspaces: TerminalWorkspacesFile,
) -> Result<(TerminalWorkspacesFile, bool), String> {
    let mut normalized_workspaces = TerminalWorkspacesFile {
        version: 2,
        workspaces: std::collections::HashMap::new(),
    };
    let mut changed = workspaces.version != 2;

    for (project_path, workspace) in workspaces.workspaces {
        let normalized = if is_layout_snapshot(&workspace) {
            normalize_layout_snapshot_for_store(&project_path, workspace.clone())
        } else {
            changed = true;
            normalize_layout_snapshot_for_store(
                &project_path,
                legacy_workspace_to_layout_snapshot(&workspace)?,
            )
        };
        if normalized != workspace {
            changed = true;
        }
        normalized_workspaces
            .workspaces
            .insert(project_path, normalized);
    }

    Ok((normalized_workspaces, changed))
}

fn build_terminal_layout_snapshot_summaries(
    snapshots: &[(String, TerminalLayoutSnapshot)],
) -> Vec<TerminalLayoutSnapshotSummary> {
    let mut summaries: Vec<TerminalLayoutSnapshotSummary> = snapshots
        .iter()
        .map(|(project_path, snapshot)| TerminalLayoutSnapshotSummary {
            project_path: project_path.clone(),
            project_id: snapshot
                .get("projectId")
                .and_then(|value| value.as_str())
                .map(|value| value.to_string()),
            updated_at: json_i64(snapshot.get("updatedAt")),
            revision: json_i64(snapshot.get("revision")),
        })
        .collect();

    summaries.sort_by(|left, right| {
        right
            .updated_at
            .unwrap_or_default()
            .cmp(&left.updated_at.unwrap_or_default())
            .then_with(|| left.project_path.cmp(&right.project_path))
    });

    summaries
}

fn schedule_terminal_workspace_flush(app: AppHandle) {
    thread::spawn(move || {
        loop {
            thread::sleep(Duration::from_millis(
                TERMINAL_WORKSPACE_FLUSH_DEBOUNCE_MS,
            ));

            let snapshot = {
                let store = terminal_workspace_store()
                    .lock()
                    .map_err(|_| "终端工作区缓存锁已损坏".to_string());
                let Ok(store) = store else {
                    log::warn!("终端工作区缓存锁已损坏，跳过异步刷盘");
                    return;
                };
                store.flush_snapshot()
            };

            let Some(snapshot) = snapshot else {
                let mut store = match terminal_workspace_store().lock() {
                    Ok(store) => store,
                    Err(_) => {
                        log::warn!("终端工作区缓存锁已损坏，无法结束刷盘线程");
                        return;
                    }
                };
                store.flush_worker_running = false;
                return;
            };

            if let Err(error) = save_terminal_workspaces_to_disk(&app, &snapshot.workspaces) {
                log::warn!("终端工作区异步刷盘失败: {}", error);
                if let Ok(mut store) = terminal_workspace_store().lock() {
                    store.mark_flush_failed();
                }
                return;
            }

            let should_continue = match terminal_workspace_store().lock() {
                Ok(mut store) => store.mark_flush_complete(snapshot.revision),
                Err(_) => {
                    log::warn!("终端工作区缓存锁已损坏，无法更新刷盘状态");
                    return;
                }
            };
            if !should_continue {
                return;
            }
        }
    });
}

pub fn flush_terminal_workspace_store(app: &AppHandle) -> Result<(), String> {
    loop {
        let snapshot = {
            let mut store = terminal_workspace_store()
                .lock()
                .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
            store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
            store.flush_snapshot()
        };

        let Some(snapshot) = snapshot else {
            return Ok(());
        };

        save_terminal_workspaces_to_disk(app, &snapshot.workspaces)?;

        let should_continue = {
            let mut store = terminal_workspace_store()
                .lock()
                .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
            store.mark_flush_complete(snapshot.revision)
        };
        if !should_continue {
            return Ok(());
        }
    }
}

/// 读取应用状态文件。
pub fn load_app_state(app: &AppHandle) -> Result<AppStateFile, String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("app_state.json");
    if !file_path.exists() {
        return Ok(AppStateFile::default());
    }
    read_json(&file_path)
}

/// 保存应用状态文件。
pub fn save_app_state(app: &AppHandle, state: &AppStateFile) -> Result<(), String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("app_state.json");
    write_json_pretty(&file_path, state)
}

/// 读取项目缓存列表。
pub fn load_projects(app: &AppHandle) -> Result<Vec<Project>, String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("projects.json");
    if !file_path.exists() {
        return Ok(Vec::new());
    }
    read_json(&file_path)
}

/// 保存项目缓存列表。
pub fn save_projects(app: &AppHandle, projects: &[Project]) -> Result<(), String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("projects.json");
    write_json_compact(&file_path, projects)
}

/// 读取热力图缓存。
pub fn load_heatmap_cache(app: &AppHandle) -> Result<HeatmapCacheFile, String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("heatmap_cache.json");
    if !file_path.exists() {
        return Ok(HeatmapCacheFile::default());
    }
    read_json(&file_path)
}

/// 保存热力图缓存。
pub fn save_heatmap_cache(app: &AppHandle, cache: &HeatmapCacheFile) -> Result<(), String> {
    let dir = app_support_dir(app)?;
    ensure_dir(&dir)?;
    let file_path = dir.join("heatmap_cache.json");
    write_json_pretty(&file_path, cache)
}

fn as_object<'a>(value: &'a JsonValue, context: &str) -> Result<&'a Map<String, JsonValue>, String> {
    value
        .as_object()
        .ok_or_else(|| format!("{context} 必须是 JSON 对象"))
}

fn get_string(map: &Map<String, JsonValue>, key: &str) -> Option<String> {
    map.get(key)
        .and_then(|value| value.as_str())
        .map(|value| value.to_string())
}

fn get_i64(map: &Map<String, JsonValue>, key: &str) -> Option<i64> {
    map.get(key).and_then(|value| {
        value
            .as_i64()
            .or_else(|| value.as_f64().map(|number| number as i64))
    })
}

fn legacy_workspace_to_layout_snapshot(workspace: &JsonValue) -> Result<JsonValue, String> {
    let workspace_obj = as_object(workspace, "旧版 terminal workspace")?;
    let project_path = get_string(workspace_obj, "projectPath")
        .ok_or_else(|| "旧版 terminal workspace 缺少 projectPath".to_string())?;
    let project_id = workspace_obj.get("projectId").cloned().unwrap_or(JsonValue::Null);
    let active_tab_id = get_string(workspace_obj, "activeTabId")
        .ok_or_else(|| "旧版 terminal workspace 缺少 activeTabId".to_string())?;
    let updated_at = get_i64(workspace_obj, "updatedAt").unwrap_or_default();
    let ui = workspace_obj.get("ui").cloned().unwrap_or_else(|| json!({}));
    let tabs = workspace_obj
        .get("tabs")
        .and_then(|value| value.as_array())
        .ok_or_else(|| "旧版 terminal workspace 缺少 tabs".to_string())?;
    let sessions = workspace_obj
        .get("sessions")
        .and_then(|value| value.as_object())
        .ok_or_else(|| "旧版 terminal workspace 缺少 sessions".to_string())?;

    let mut panes = Map::new();
    let mut session_to_pane: std::collections::HashMap<String, String> = std::collections::HashMap::new();

    fn convert_split_node(
        node: &JsonValue,
        sessions: &Map<String, JsonValue>,
        panes: &mut Map<String, JsonValue>,
        session_to_pane: &mut std::collections::HashMap<String, String>,
        project_path: &str,
    ) -> Result<JsonValue, String> {
        let node_obj = as_object(node, "split node")?;
        let node_type = get_string(node_obj, "type").unwrap_or_default();
        if node_type == "pane" {
            let session_id = get_string(node_obj, "sessionId")
                .ok_or_else(|| "pane 节点缺少 sessionId".to_string())?;
            let pane_id = session_to_pane
                .entry(session_id.clone())
                .or_insert_with(|| format!("pane:{session_id}"))
                .clone();
            if !panes.contains_key(&pane_id) {
                let session = sessions
                    .get(&session_id)
                    .and_then(|value| value.as_object());
                let cwd = session
                    .and_then(|session_obj| get_string(session_obj, "cwd"))
                    .unwrap_or_else(|| project_path.to_string());
                let saved_state = session
                    .and_then(|session_obj| session_obj.get("savedState"))
                    .cloned()
                    .unwrap_or(JsonValue::Null);
                panes.insert(
                    pane_id.clone(),
                    json!({
                        "id": pane_id,
                        "kind": "terminal",
                        "placement": "tree",
                        "sessionId": session_id,
                        "cwd": cwd.clone(),
                        "restoreAnchor": {
                            "cwd": cwd,
                            "savedState": saved_state,
                        }
                    }),
                );
            }
            return Ok(json!({
                "type": "leaf",
                "paneId": pane_id,
            }));
        }

        let orientation = get_string(node_obj, "orientation")
            .ok_or_else(|| "split 节点缺少 orientation".to_string())?;
        let ratios = node_obj.get("ratios").cloned().unwrap_or_else(|| json!([]));
        let children = node_obj
            .get("children")
            .and_then(|value| value.as_array())
            .ok_or_else(|| "split 节点缺少 children".to_string())?;
        let converted_children: Result<Vec<_>, _> = children
            .iter()
            .map(|child| convert_split_node(child, sessions, panes, session_to_pane, project_path))
            .collect();
        Ok(json!({
            "type": "split",
            "orientation": orientation,
            "ratios": ratios,
            "children": converted_children?,
        }))
    }

    let converted_tabs: Result<Vec<_>, _> = tabs
        .iter()
        .map(|tab| -> Result<JsonValue, String> {
            let tab_obj = as_object(tab, "tab")?;
            let tab_id = get_string(tab_obj, "id").ok_or_else(|| "tab 缺少 id".to_string())?;
            let title = get_string(tab_obj, "title").unwrap_or_else(|| "终端".to_string());
            let root = tab_obj
                .get("root")
                .ok_or_else(|| "tab 缺少 root".to_string())?;
            let converted_root = convert_split_node(root, sessions, &mut panes, &mut session_to_pane, &project_path)?;
            let active_session_id =
                get_string(tab_obj, "activeSessionId").ok_or_else(|| "tab 缺少 activeSessionId".to_string())?;
            let active_pane_id = session_to_pane
                .get(&active_session_id)
                .cloned()
                .unwrap_or_else(|| format!("pane:{active_session_id}"));
            Ok(json!({
                "id": tab_id,
                "title": title,
                "root": converted_root,
                "activePaneId": active_pane_id,
                "zoomedPaneId": JsonValue::Null,
            }))
        })
        .collect();

    if let Some(run_panel_tabs) = ui
        .as_object()
        .and_then(|ui_obj| ui_obj.get("runPanel"))
        .and_then(|value| value.as_object())
        .and_then(|run_panel| run_panel.get("tabs"))
        .and_then(|value| value.as_array())
    {
        for tab in run_panel_tabs {
            let tab_obj = as_object(tab, "run panel tab")?;
            let tab_id = get_string(tab_obj, "id").ok_or_else(|| "run panel tab 缺少 id".to_string())?;
            let session_id =
                get_string(tab_obj, "sessionId").ok_or_else(|| "run panel tab 缺少 sessionId".to_string())?;
            let script_id =
                get_string(tab_obj, "scriptId").ok_or_else(|| "run panel tab 缺少 scriptId".to_string())?;
            let title = get_string(tab_obj, "title").unwrap_or_else(|| "运行".to_string());
            let session = sessions
                .get(&session_id)
                .and_then(|value| value.as_object());
            let cwd = session
                .and_then(|session_obj| get_string(session_obj, "cwd"))
                .unwrap_or_else(|| project_path.to_string());
            let saved_state = session
                .and_then(|session_obj| session_obj.get("savedState"))
                .cloned()
                .unwrap_or(JsonValue::Null);
            let run_pane_id = format!("run:{tab_id}");
            panes.insert(
                run_pane_id.clone(),
                json!({
                    "id": run_pane_id,
                    "kind": "run",
                    "placement": "runPanel",
                    "title": title,
                    "sessionId": session_id,
                    "scriptId": script_id,
                    "restoreAnchor": {
                        "cwd": cwd,
                        "savedState": saved_state,
                    }
                }),
            );
        }
    }

    Ok(json!({
        "version": 2,
        "projectId": project_id,
        "projectPath": project_path,
        "windowId": JsonValue::Null,
        "tabs": converted_tabs?,
        "panes": JsonValue::Object(panes),
        "activeTabId": active_tab_id,
        "ui": ui,
        "updatedAt": updated_at,
        "revision": updated_at,
        "importedFromLegacy": true,
    }))
}

pub fn load_all_terminal_layout_snapshots(
    app: &AppHandle,
) -> Result<Vec<(String, TerminalLayoutSnapshot)>, String> {
    let (snapshots, should_schedule) = {
        let mut store = terminal_workspace_store()
            .lock()
            .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
        store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
        let keys: Vec<String> = store.workspaces.workspaces.keys().cloned().collect();
        let mut snapshots = Vec::new();
        for project_path in keys {
            if let Some(snapshot) = store.load_layout_snapshot(&project_path)? {
                snapshots.push((project_path, snapshot));
            }
        }
        let should_schedule = store.try_start_flush_worker_if_dirty();
        (snapshots, should_schedule)
    };
    if should_schedule {
        schedule_terminal_workspace_flush(app.clone());
    }
    Ok(snapshots)
}

pub fn list_terminal_layout_snapshot_summaries(
    app: &AppHandle,
) -> Result<Vec<TerminalLayoutSnapshotSummary>, String> {
    let (summaries, should_schedule) = {
        let mut store = terminal_workspace_store()
            .lock()
            .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
        store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
        let summaries = store.list_layout_summaries()?;
        let should_schedule = store.try_start_flush_worker_if_dirty();
        (summaries, should_schedule)
    };
    if should_schedule {
        schedule_terminal_workspace_flush(app.clone());
    }
    Ok(summaries)
}

pub fn normalize_terminal_layout_snapshot_for_store(
    project_path: &str,
    snapshot: JsonValue,
) -> JsonValue {
    normalize_layout_snapshot_for_store(project_path, snapshot)
}

pub fn save_terminal_layout_snapshot(
    app: &AppHandle,
    project_path: &str,
    snapshot: JsonValue,
) -> Result<JsonValue, String> {
    let normalized = normalize_layout_snapshot_for_store(project_path, snapshot);
    let should_schedule = {
        let mut store = terminal_workspace_store()
            .lock()
            .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
        store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
        let changed = store.upsert_layout_snapshot(project_path.to_string(), normalized.clone());
        changed && store.try_start_flush_worker()
    };
    if should_schedule {
        schedule_terminal_workspace_flush(app.clone());
    }
    Ok(normalized)
}

pub fn delete_terminal_layout_snapshot(app: &AppHandle, project_path: &str) -> Result<(), String> {
    let should_schedule = {
        let mut store = terminal_workspace_store()
            .lock()
            .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
        store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
        let changed = store.delete_workspace(project_path);
        changed && store.try_start_flush_worker()
    };
    if should_schedule {
        schedule_terminal_workspace_flush(app.clone());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{
        legacy_workspace_to_layout_snapshot, TerminalWorkspaceStoreState, TerminalWorkspacesFile,
    };

    #[test]
    fn terminal_workspace_store_batches_multiple_updates_before_flush() {
        let mut store = TerminalWorkspaceStoreState::default();
        store.replace_loaded(TerminalWorkspacesFile::default(), false);

        let first_workspace = json!({
            "version": 2,
            "projectId": "project-1",
            "projectPath": "/repo-a",
            "tabs": [],
            "panes": {},
            "activeTabId": "",
            "updatedAt": 100,
            "revision": 100,
        });
        let second_workspace = json!({
            "version": 2,
            "projectId": "project-1",
            "projectPath": "/repo-a",
            "tabs": [],
            "panes": {},
            "activeTabId": "",
            "updatedAt": 200,
            "revision": 200,
        });

        assert!(store.upsert_layout_snapshot("/repo-a".to_string(), first_workspace));

        let first_snapshot = store
            .flush_snapshot()
            .expect("first update should produce a flush snapshot");
        assert_eq!(first_snapshot.revision, 1);

        assert!(store.upsert_layout_snapshot("/repo-a".to_string(), second_workspace));

        let second_snapshot = store
            .flush_snapshot()
            .expect("second update should still be pending");
        assert_eq!(second_snapshot.revision, 2);
        assert_eq!(
            second_snapshot.workspaces.workspaces["/repo-a"]["updatedAt"],
            json!(200)
        );

        assert!(store.mark_flush_complete(first_snapshot.revision));

        let latest_snapshot = store
            .flush_snapshot()
            .expect("latest update should remain pending after stale flush");
        assert_eq!(latest_snapshot.revision, 2);

        assert!(!store.mark_flush_complete(latest_snapshot.revision));
        assert!(store.flush_snapshot().is_none());
    }

    #[test]
    fn terminal_workspace_store_summaries_follow_cached_updates_and_deletes() {
        let mut store = TerminalWorkspaceStoreState::default();
        store.replace_loaded(TerminalWorkspacesFile::default(), false);

        assert!(store.upsert_layout_snapshot(
            "/repo-a".to_string(),
            json!({
                "version": 2,
                "projectId": "project-a",
                "projectPath": "/repo-a",
                "tabs": [],
                "panes": {},
                "activeTabId": "",
                "updatedAt": 100,
                "revision": 100,
            }),
        ));
        assert!(store.upsert_layout_snapshot(
            "/repo-b".to_string(),
            json!({
                "version": 2,
                "projectId": "project-b",
                "projectPath": "/repo-b",
                "tabs": [],
                "panes": {},
                "activeTabId": "",
                "updatedAt": 300,
                "revision": 300,
            }),
        ));

        let summaries = store.list_layout_summaries().unwrap();
        assert_eq!(summaries.len(), 2);
        assert_eq!(summaries[0].project_path, "/repo-b");
        assert_eq!(summaries[0].updated_at, Some(300));
        assert_eq!(summaries[1].project_path, "/repo-a");

        assert!(store.delete_workspace("/repo-b"));
        assert!(store.load_layout_snapshot("/repo-b").unwrap().is_none());

        let summaries = store.list_layout_summaries().unwrap();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].project_path, "/repo-a");
        assert_eq!(summaries[0].project_id.as_deref(), Some("project-a"));
    }
    #[test]
    fn legacy_workspace_upgrades_to_layout_snapshot() {
        let legacy = json!({
            "version": 1,
            "projectId": "project-1",
            "projectPath": "/repo-a",
            "tabs": [
                {
                    "id": "tab-1",
                    "title": "终端 1",
                    "root": { "type": "pane", "sessionId": "session-1" },
                    "activeSessionId": "session-1"
                }
            ],
            "activeTabId": "tab-1",
            "sessions": {
                "session-1": {
                    "id": "session-1",
                    "cwd": "/repo-a",
                    "savedState": "hello"
                }
            },
            "ui": {
                "runPanel": {
                    "open": true,
                    "height": 240,
                    "activeTabId": "run-1",
                    "tabs": [
                        {
                            "id": "run-1",
                            "title": "运行",
                            "sessionId": "session-1",
                            "scriptId": "script-1",
                            "createdAt": 100
                        }
                    ]
                }
            },
            "updatedAt": 100
        });

        let snapshot = legacy_workspace_to_layout_snapshot(&legacy).unwrap();
        assert_eq!(snapshot["projectPath"], json!("/repo-a"));
        assert_eq!(snapshot["activeTabId"], json!("tab-1"));
        assert!(snapshot["panes"].get("pane:session-1").is_some());
        assert_eq!(snapshot["importedFromLegacy"], json!(true));
        assert_eq!(
            snapshot["panes"]["pane:session-1"]["restoreAnchor"]["savedState"],
            json!("hello")
        );
    }

    #[test]
    fn store_load_layout_snapshot_rejects_unexpected_legacy_cache_record() {
        let mut store = TerminalWorkspaceStoreState::default();
        store.replace_loaded(TerminalWorkspacesFile::default(), false);
        store.workspaces.workspaces.insert(
            "/repo-a".to_string(),
            json!({
                "version": 1,
                "projectId": "project-a",
                "projectPath": "/repo-a",
                "tabs": [],
                "activeTabId": "",
                "sessions": {},
                "updatedAt": 42
            }),
        );

        let error = store.load_layout_snapshot("/repo-a").unwrap_err();
        assert!(error.contains("缓存中存在未归一化的旧版 terminal workspace"));
    }

    #[test]
    fn terminal_workspace_store_normalizes_legacy_entries_when_loading() {
        let mut store = TerminalWorkspaceStoreState::default();
        store
            .ensure_loaded_with(|| {
                let mut file = TerminalWorkspacesFile::default();
                file.workspaces.insert(
                    "/repo-a".to_string(),
                    json!({
                        "version": 1,
                        "projectId": "project-a",
                        "projectPath": "/repo-a",
                        "tabs": [],
                        "activeTabId": "",
                        "sessions": {},
                        "updatedAt": 42
                    }),
                );
                Ok(file)
            })
            .unwrap();

        assert_eq!(store.workspaces.workspaces["/repo-a"]["version"], json!(2));
        assert_eq!(
            store.workspaces.workspaces["/repo-a"]["importedFromLegacy"],
            json!(true)
        );
        assert!(store.flush_snapshot().is_some());
    }

}
