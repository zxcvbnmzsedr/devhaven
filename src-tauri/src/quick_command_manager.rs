use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

use crate::terminal_runtime::types::QuickCommandRecord as RuntimeQuickCommandRecord;
use crate::terminal_runtime::{
    JobId as RuntimeJobId, QUICK_COMMAND_STATE_CHANGED_EVENT,
    QuickCommandState as RuntimeQuickCommandState, QuickCommandStateChangedPayload, shared_runtime,
};
use crate::web_event_bus;

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

    state.upsert_job(job.clone());
    let _ = sync_runtime_job_start(&job);

    emit_quick_command_state_changed(
        &app,
        QuickCommandStateChangedPayload {
            job_id: job.job_id.clone(),
            script_id: job.script_id.clone(),
            project_id: job.project_id.clone(),
            project_path: job.project_path.clone(),
            state: RuntimeQuickCommandState::Running,
            updated_at: job.updated_at,
            exit_code: job.exit_code,
            error: job.error.clone(),
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

    let (stopping_job, _stopping_snapshot, changed) = state.request_stop(&job_id, is_force)?;

    if changed {
        let runtime_state = if is_force {
            RuntimeQuickCommandState::StoppingHard
        } else {
            RuntimeQuickCommandState::StoppingSoft
        };
        let _ = shared_runtime().update_quick_command_state(
            &RuntimeJobId::from_string(job_id.clone()),
            runtime_state.clone(),
        );
        emit_quick_command_state_changed(
            &app,
            QuickCommandStateChangedPayload {
                job_id: stopping_job.job_id.clone(),
                script_id: stopping_job.script_id.clone(),
                project_id: stopping_job.project_id.clone(),
                project_path: stopping_job.project_path.clone(),
                state: runtime_state,
                updated_at: stopping_job.updated_at,
                exit_code: stopping_job.exit_code,
                error: stopping_job.error.clone(),
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

    let (finished_job, _finished_snapshot, changed) =
        state.finish_job(&job_id, final_state.clone(), resolved_code, error.clone())?;

    if changed {
        let runtime_state = if final_state == QuickCommandState::Exited {
            RuntimeQuickCommandState::Exited
        } else {
            RuntimeQuickCommandState::Failed
        };
        let _ = shared_runtime().finish_quick_command(
            &RuntimeJobId::from_string(job_id.clone()),
            runtime_state.clone(),
            Some(resolved_code),
            error.clone(),
        );
        emit_quick_command_state_changed(
            &app,
            QuickCommandStateChangedPayload {
                job_id: finished_job.job_id.clone(),
                script_id: finished_job.script_id.clone(),
                project_id: finished_job.project_id.clone(),
                project_path: finished_job.project_path.clone(),
                state: runtime_state,
                updated_at: finished_job.updated_at,
                exit_code: finished_job.exit_code,
                error: finished_job.error.clone(),
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

fn emit_quick_command_state_changed(
    app_handle: &AppHandle,
    payload: QuickCommandStateChangedPayload,
) {
    if let Err(error) = app_handle.emit(QUICK_COMMAND_STATE_CHANGED_EVENT, payload.clone()) {
        log::warn!("发送 {} 失败: {}", QUICK_COMMAND_STATE_CHANGED_EVENT, error);
    }
    web_event_bus::publish(QUICK_COMMAND_STATE_CHANGED_EVENT, &payload);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terminal_runtime::{QuickCommandState as RuntimeQuickCommandState, shared_runtime};
    use uuid::Uuid;

    #[test]
    fn sync_runtime_job_start_keeps_runtime_job_id_in_sync() {
        let project_path = format!("/tmp/devhaven-quick-command-sync-{}", Uuid::new_v4());
        let script_id = format!("script-{}", Uuid::new_v4());
        let command = "echo hello".to_string();
        let now = now_millis();
        let job = QuickCommandJob {
            job_id: format!("job-{}", Uuid::new_v4()),
            project_id: "project-1".to_string(),
            project_path: project_path.clone(),
            script_id: script_id.clone(),
            command: command.clone(),
            window_label: None,
            state: QuickCommandState::Running,
            created_at: now,
            updated_at: now,
            exit_code: None,
            error: None,
        };

        sync_runtime_job_start(&job).expect("runtime start should succeed");

        let runtime_jobs = shared_runtime()
            .list_quick_commands(Some(&project_path))
            .expect("runtime quick commands should be queryable");
        assert_eq!(runtime_jobs.len(), 1);
        assert_eq!(runtime_jobs[0].job_id.as_str(), job.job_id);
        assert_eq!(runtime_jobs[0].script_id, script_id);
        assert_eq!(runtime_jobs[0].command, command);

        let finished = shared_runtime()
            .finish_quick_command(
                &RuntimeJobId::from_string(job.job_id.clone()),
                RuntimeQuickCommandState::Exited,
                Some(0),
                None,
            )
            .expect("runtime finish should succeed");
        let finished = finished.expect("runtime job should exist by the manager job id");
        assert_eq!(finished.job_id.as_str(), job.job_id);
        assert_eq!(finished.state, RuntimeQuickCommandState::Exited);

        let runtime_jobs = shared_runtime()
            .list_quick_commands(Some(&project_path))
            .expect("runtime quick commands should still be queryable after finish");
        assert_eq!(runtime_jobs.len(), 1);
        assert_eq!(runtime_jobs[0].job_id.as_str(), job.job_id);
        assert_eq!(runtime_jobs[0].state, RuntimeQuickCommandState::Exited);
        assert_eq!(runtime_jobs[0].exit_code, Some(0));
    }
}

fn sync_runtime_job_start(job: &QuickCommandJob) -> Result<(), String> {
    shared_runtime()
        .start_quick_command(RuntimeQuickCommandRecord {
            job_id: RuntimeJobId::from_string(job.job_id.clone()),
            project_id: job.project_id.clone(),
            project_path: job.project_path.clone(),
            script_id: job.script_id.clone(),
            command: job.command.clone(),
            state: RuntimeQuickCommandState::Running,
            created_at: job.created_at,
            updated_at: job.updated_at,
            exit_code: job.exit_code,
            error: job.error.clone(),
        })
        .map(|_| ())
}
