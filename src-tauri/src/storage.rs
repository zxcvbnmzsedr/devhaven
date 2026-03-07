use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};
use std::time::Duration;

use serde::Serialize;
use serde::de::DeserializeOwned;
use tauri::{AppHandle, Manager};

use crate::models::{
    AppStateFile, HeatmapCacheFile, Project, TerminalWorkspace, TerminalWorkspaceSummary,
    TerminalWorkspacesFile,
};

// 终端工作区的 read-modify-write 需要串行化，避免并发覆盖。
fn terminal_workspace_rmw_mutex() -> &'static Mutex<()> {
    static TERMINAL_WORKSPACE_RMW_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
    TERMINAL_WORKSPACE_RMW_MUTEX.get_or_init(|| Mutex::new(()))
}

const TERMINAL_WORKSPACE_FLUSH_DEBOUNCE_MS: u64 = 250;

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
    fn replace_loaded(&mut self, workspaces: TerminalWorkspacesFile) {
        self.loaded = true;
        self.workspaces = workspaces;
        self.dirty_revision = 0;
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
        self.replace_loaded(loader()?);
        Ok(())
    }

    fn upsert_workspace(&mut self, project_path: String, workspace: TerminalWorkspace) -> bool {
        let changed = self.workspaces.workspaces.get(&project_path) != Some(&workspace);
        if changed {
            self.workspaces.workspaces.insert(project_path, workspace);
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

    fn load_workspace(&self, project_path: &str) -> Option<TerminalWorkspace> {
        self.workspaces.workspaces.get(project_path).cloned()
    }

    #[cfg_attr(not(test), allow(dead_code))]
    fn list_summaries(&self) -> Vec<TerminalWorkspaceSummary> {
        build_terminal_workspace_summaries(&self.workspaces)
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

fn build_terminal_workspace_summaries(
    workspaces: &TerminalWorkspacesFile,
) -> Vec<TerminalWorkspaceSummary> {
    let mut summaries = Vec::with_capacity(workspaces.workspaces.len());

    for (project_path, workspace) in &workspaces.workspaces {
        let project_id = workspace
            .get("projectId")
            .and_then(|value| value.as_str())
            .map(|value| value.to_string());
        let updated_at = workspace.get("updatedAt").and_then(|value| {
            value
                .as_i64()
                .or_else(|| value.as_f64().map(|number| number as i64))
        });

        summaries.push(TerminalWorkspaceSummary {
            project_path: project_path.clone(),
            project_id,
            updated_at,
        });
    }

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

/// 读取终端工作空间集合。
pub fn load_terminal_workspaces(app: &AppHandle) -> Result<TerminalWorkspacesFile, String> {
    let mut store = terminal_workspace_store()
        .lock()
        .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
    store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
    Ok(store.workspaces.clone())
}

/// 保存终端工作空间集合。
#[allow(dead_code)]
pub fn save_terminal_workspaces(
    app: &AppHandle,
    workspaces: &TerminalWorkspacesFile,
) -> Result<(), String> {
    save_terminal_workspaces_to_disk(app, workspaces)?;
    let mut store = terminal_workspace_store()
        .lock()
        .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
    store.replace_loaded(workspaces.clone());
    Ok(())
}

/// 读取指定项目终端工作空间。
pub fn load_terminal_workspace(
    app: &AppHandle,
    project_path: &str,
) -> Result<Option<TerminalWorkspace>, String> {
    let mut store = terminal_workspace_store()
        .lock()
        .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
    store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
    Ok(store.load_workspace(project_path))
}

/// 保存指定项目终端工作空间。
pub fn save_terminal_workspace(
    app: &AppHandle,
    project_path: &str,
    workspace: TerminalWorkspace,
) -> Result<(), String> {
    let should_schedule = {
        let mut store = terminal_workspace_store()
            .lock()
            .map_err(|_| "终端工作区缓存锁已损坏".to_string())?;
        store.ensure_loaded_with(|| load_terminal_workspaces_from_disk(app))?;
        let changed = store.upsert_workspace(project_path.to_string(), workspace);
        changed && store.try_start_flush_worker()
    };
    if should_schedule {
        schedule_terminal_workspace_flush(app.clone());
    }
    Ok(())
}

/// 删除指定项目终端工作空间。
pub fn delete_terminal_workspace(app: &AppHandle, project_path: &str) -> Result<(), String> {
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

/// 列出已保存的终端工作空间摘要。
pub fn list_terminal_workspace_summaries(
    app: &AppHandle,
) -> Result<Vec<TerminalWorkspaceSummary>, String> {
    let workspaces = load_terminal_workspaces(app)?;
    Ok(build_terminal_workspace_summaries(&workspaces))
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::{TerminalWorkspaceStoreState, TerminalWorkspacesFile};

    #[test]
    fn terminal_workspace_store_batches_multiple_updates_before_flush() {
        let mut store = TerminalWorkspaceStoreState::default();
        store.replace_loaded(TerminalWorkspacesFile::default());

        let first_workspace = json!({
            "projectId": "project-1",
            "updatedAt": 100,
        });
        let second_workspace = json!({
            "projectId": "project-1",
            "updatedAt": 200,
        });

        assert!(store.upsert_workspace("/repo-a".to_string(), first_workspace));

        let first_snapshot = store
            .flush_snapshot()
            .expect("first update should produce a flush snapshot");
        assert_eq!(first_snapshot.revision, 1);

        assert!(store.upsert_workspace("/repo-a".to_string(), second_workspace));

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
        store.replace_loaded(TerminalWorkspacesFile::default());

        assert!(store.upsert_workspace(
            "/repo-a".to_string(),
            json!({
                "projectId": "project-a",
                "updatedAt": 100,
            }),
        ));
        assert!(store.upsert_workspace(
            "/repo-b".to_string(),
            json!({
                "projectId": "project-b",
                "updatedAt": 300,
            }),
        ));

        let summaries = store.list_summaries();
        assert_eq!(summaries.len(), 2);
        assert_eq!(summaries[0].project_path, "/repo-b");
        assert_eq!(summaries[0].updated_at, Some(300));
        assert_eq!(summaries[1].project_path, "/repo-a");

        assert!(store.delete_workspace("/repo-b"));
        assert!(store.load_workspace("/repo-b").is_none());

        let summaries = store.list_summaries();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].project_path, "/repo-a");
        assert_eq!(summaries[0].project_id.as_deref(), Some("project-a"));
    }
}
