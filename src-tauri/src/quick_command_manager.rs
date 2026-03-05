use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

use crate::web_event_bus;

pub const QUICK_COMMAND_EVENT: &str = "quick-command-event";

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum QuickCommandState {
    Queued,
    Starting,
    Running,
    StoppingSoft,
    StoppingHard,
    Exited,
    Failed,
    Cancelled,
}

impl QuickCommandState {
    fn is_terminal(&self) -> bool {
        matches!(
            self,
            QuickCommandState::Exited | QuickCommandState::Failed | QuickCommandState::Cancelled
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickCommandJob {
    pub job_id: String,
    pub project_id: String,
    pub project_path: String,
    pub script_id: String,
    pub command: String,
    #[serde(default)]
    pub window_label: Option<String>,
    pub state: QuickCommandState,
    pub created_at: i64,
    pub updated_at: i64,
    #[serde(default)]
    pub exit_code: Option<i32>,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickCommandSnapshot {
    pub jobs: Vec<QuickCommandJob>,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum QuickCommandEventType {
    Started,
    StateChanged,
    Exited,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QuickCommandEvent {
    #[serde(rename = "type")]
    pub event_type: QuickCommandEventType,
    pub job: QuickCommandJob,
    pub snapshot: QuickCommandSnapshot,
}

#[derive(Clone, Default)]
pub struct QuickCommandManager {
    inner: Arc<Mutex<QuickCommandRuntime>>,
}

#[derive(Default)]
struct QuickCommandRuntime {
    jobs: HashMap<String, QuickCommandJob>,
    updated_at: i64,
}

#[tauri::command]
/// 创建并启动一个快捷命令任务（当前阶段仅落状态，不启动真实子进程）。
pub fn quick_command_start(
    app: AppHandle,
    state: State<QuickCommandManager>,
    project_id: String,
    project_path: String,
    script_id: String,
    command: String,
    window_label: Option<String>,
) -> QuickCommandJob {
    let now = now_millis();
    let job = QuickCommandJob {
        job_id: Uuid::new_v4().to_string(),
        project_id,
        project_path,
        script_id,
        command,
        window_label,
        state: QuickCommandState::Running,
        created_at: now,
        updated_at: now,
        exit_code: None,
        error: None,
    };

    let snapshot = state.upsert_job(job.clone());

    emit_quick_command_event(
        &app,
        QuickCommandEvent {
            event_type: QuickCommandEventType::Started,
            job: job.clone(),
            snapshot,
        },
    );

    job
}

#[tauri::command]
/// 请求停止一个快捷命令任务（进入 stopping 状态，最终状态由 finish 回传）。
pub fn quick_command_stop(
    app: AppHandle,
    state: State<QuickCommandManager>,
    job_id: String,
    force: Option<bool>,
) -> Result<QuickCommandJob, String> {
    let is_force = force.unwrap_or(false);

    let (stopping_job, stopping_snapshot, changed) = state.request_stop(&job_id, is_force)?;

    if changed {
        emit_quick_command_event(
            &app,
            QuickCommandEvent {
                event_type: QuickCommandEventType::StateChanged,
                job: stopping_job.clone(),
                snapshot: stopping_snapshot,
            },
        );
    }

    Ok(stopping_job)
}

#[tauri::command]
/// 标记快捷命令任务完成（由前端在会话退出时回传退出码）。
pub fn quick_command_finish(
    app: AppHandle,
    state: State<QuickCommandManager>,
    job_id: String,
    exit_code: Option<i32>,
    error: Option<String>,
) -> Result<QuickCommandJob, String> {
    let resolved_code = exit_code.unwrap_or_default();
    let final_state = if error.as_deref().is_some() || resolved_code != 0 {
        QuickCommandState::Failed
    } else {
        QuickCommandState::Exited
    };

    let (finished_job, finished_snapshot, changed) =
        state.finish_job(&job_id, final_state, resolved_code, error)?;

    if changed {
        emit_quick_command_event(
            &app,
            QuickCommandEvent {
                event_type: QuickCommandEventType::Exited,
                job: finished_job.clone(),
                snapshot: finished_snapshot,
            },
        );
    }

    Ok(finished_job)
}

#[tauri::command]
/// 查询任务列表，可按 projectPath 过滤。
pub fn quick_command_list(
    state: State<QuickCommandManager>,
    project_path: Option<String>,
) -> Vec<QuickCommandJob> {
    state.list_jobs(project_path.as_deref())
}

#[tauri::command]
/// 获取任务快照。
pub fn quick_command_snapshot(state: State<QuickCommandManager>) -> QuickCommandSnapshot {
    state.snapshot()
}

/// 向前端广播 quick command 事件。
pub fn emit_quick_command_event(app_handle: &AppHandle, event: QuickCommandEvent) {
    if let Err(error) = app_handle.emit(QUICK_COMMAND_EVENT, event.clone()) {
        log::warn!("发送 quick-command-event 失败: {}", error);
    }
    web_event_bus::publish(QUICK_COMMAND_EVENT, &event);
}

impl QuickCommandManager {
    fn upsert_job(&self, job: QuickCommandJob) -> QuickCommandSnapshot {
        let mut runtime = lock_runtime(&self.inner);
        runtime.updated_at = now_millis();
        runtime.jobs.insert(job.job_id.clone(), job);
        runtime.snapshot()
    }

    fn request_stop(
        &self,
        job_id: &str,
        force: bool,
    ) -> Result<(QuickCommandJob, QuickCommandSnapshot, bool), String> {
        let mut runtime = lock_runtime(&self.inner);
        let now = now_millis();

        let mut changed = false;
        let updated = if let Some(job) = runtime.jobs.get_mut(job_id) {
            let next_state = if job.state.is_terminal() {
                job.state.clone()
            } else if matches!(job.state, QuickCommandState::StoppingHard) {
                QuickCommandState::StoppingHard
            } else if force {
                QuickCommandState::StoppingHard
            } else {
                QuickCommandState::StoppingSoft
            };

            if next_state != job.state {
                job.state = next_state;
                job.updated_at = now;
                changed = true;
            }
            job.clone()
        } else {
            return Err("任务不存在或已被清理".to_string());
        };

        if changed {
            runtime.updated_at = now;
        }
        let snapshot = runtime.snapshot();
        Ok((updated, snapshot, changed))
    }

    fn finish_job(
        &self,
        job_id: &str,
        next_state: QuickCommandState,
        exit_code: i32,
        error: Option<String>,
    ) -> Result<(QuickCommandJob, QuickCommandSnapshot, bool), String> {
        let mut runtime = lock_runtime(&self.inner);
        let now = now_millis();

        let mut changed = false;
        let updated = if let Some(job) = runtime.jobs.get_mut(job_id) {
            if !job.state.is_terminal() {
                job.state = next_state;
                job.updated_at = now;
                job.exit_code = Some(exit_code);
                job.error = error;
                changed = true;
            }
            job.clone()
        } else {
            return Err("任务不存在或已被清理".to_string());
        };

        if changed {
            runtime.updated_at = now;
        }
        let snapshot = runtime.snapshot();
        Ok((updated, snapshot, changed))
    }

    fn list_jobs(&self, project_path: Option<&str>) -> Vec<QuickCommandJob> {
        let runtime = lock_runtime(&self.inner);
        let filter_key = project_path.map(normalize_path_for_compare);

        let mut jobs: Vec<QuickCommandJob> = runtime
            .jobs
            .values()
            .filter(|job| {
                if let Some(project_key) = filter_key.as_ref() {
                    return normalize_path_for_compare(&job.project_path) == *project_key;
                }
                true
            })
            .cloned()
            .collect();

        jobs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        jobs
    }

    fn snapshot(&self) -> QuickCommandSnapshot {
        let runtime = lock_runtime(&self.inner);
        runtime.snapshot()
    }
}

impl QuickCommandRuntime {
    fn snapshot(&self) -> QuickCommandSnapshot {
        let mut jobs: Vec<QuickCommandJob> = self.jobs.values().cloned().collect();
        jobs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));

        QuickCommandSnapshot {
            jobs,
            updated_at: self.updated_at,
        }
    }
}

fn lock_runtime(
    runtime: &Arc<Mutex<QuickCommandRuntime>>,
) -> std::sync::MutexGuard<'_, QuickCommandRuntime> {
    match runtime.lock() {
        Ok(guard) => guard,
        Err(poisoned) => {
            log::warn!("quick command 状态锁已污染，继续使用污染前数据");
            poisoned.into_inner()
        }
    }
}

fn normalize_path_for_compare(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    let normalized = trimmed.replace('\\', "/").trim_end_matches('/').to_string();
    if cfg!(windows) {
        normalized.to_ascii_lowercase()
    } else {
        normalized
    }
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}
