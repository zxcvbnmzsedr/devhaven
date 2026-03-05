use std::collections::{HashMap, VecDeque};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use tauri::{AppHandle, Emitter};
use uuid::Uuid;

use crate::git_ops;
use crate::models::{
    BranchListItem, WorktreeInitCancelResult, WorktreeInitJobStatus, WorktreeInitProgressPayload,
    WorktreeInitRetryRequest, WorktreeInitStartRequest, WorktreeInitStartResult,
    WorktreeInitStatusQuery, WorktreeInitStep,
};
use crate::web_event_bus;
use crate::worktree_setup;

pub const WORKTREE_INIT_PROGRESS_EVENT: &str = "worktree-init-progress";

#[derive(Clone, Default)]
pub struct WorktreeInitState {
    inner: Arc<Mutex<WorktreeInitRuntime>>,
}

#[derive(Default)]
struct WorktreeInitRuntime {
    jobs: HashMap<String, WorktreeInitJob>,
    project_queues: HashMap<String, VecDeque<String>>,
}

#[derive(Clone)]
struct WorktreeInitJob {
    job_id: String,
    project_id: String,
    project_path: String,
    project_key: String,
    worktree_path: String,
    branch: String,
    base_branch: Option<String>,
    create_branch: bool,
    step: WorktreeInitStep,
    message: String,
    error: Option<String>,
    updated_at: i64,
    is_running: bool,
    cancel_requested: bool,
}

enum JobRunOutcome {
    Ready(Option<String>),
    Failed(String),
    Cancelled(String),
}

impl WorktreeInitState {
    pub fn start(
        &self,
        app: &AppHandle,
        request: WorktreeInitStartRequest,
    ) -> Result<WorktreeInitStartResult, String> {
        let project_path = request.project_path.trim().to_string();
        if project_path.is_empty() {
            return Err("项目路径不能为空".to_string());
        }

        if !git_ops::is_git_repo(&project_path) {
            return Err("不是 Git 仓库".to_string());
        }

        let branch = request.branch.trim().to_string();
        if branch.is_empty() {
            return Err("分支名不能为空".to_string());
        }

        let base_branch = if request.create_branch {
            Some(resolve_request_base_branch(
                &project_path,
                request.base_branch.as_deref(),
            )?)
        } else {
            None
        };

        let worktree_path = git_ops::resolve_worktree_target_path(
            &project_path,
            &branch,
            request.target_path.as_deref(),
        )?;

        let project_key = normalize_path_for_compare(&project_path);
        let now = now_millis();
        let job_id = Uuid::new_v4().to_string();

        let job = WorktreeInitJob {
            job_id: job_id.clone(),
            project_id: request.project_id.clone(),
            project_path: project_path.clone(),
            project_key: project_key.clone(),
            worktree_path: worktree_path.clone(),
            branch: branch.clone(),
            base_branch: base_branch.clone(),
            create_branch: request.create_branch,
            step: WorktreeInitStep::Pending,
            message: String::new(),
            error: None,
            updated_at: now,
            is_running: false,
            cancel_requested: false,
        };

        let (queue_message, should_start) = {
            let mut runtime = self
                .inner
                .lock()
                .map_err(|_| "worktree 初始化状态锁定失败".to_string())?;

            runtime.jobs.insert(job_id.clone(), job);
            let ahead = enqueue_project_job(&mut runtime.project_queues, &project_key, &job_id);
            let message = build_queue_message(ahead);

            if let Some(stored) = runtime.jobs.get_mut(&job_id) {
                stored.message = message.clone();
                stored.is_running = ahead == 0;
            }

            (message, ahead == 0)
        };

        self.emit_progress(
            app,
            &job_id,
            WorktreeInitStep::Pending,
            queue_message.clone(),
            None,
        );

        if should_start {
            self.spawn_job(app.clone(), job_id.clone());
        }

        Ok(WorktreeInitStartResult {
            job_id,
            project_id: request.project_id,
            project_path,
            worktree_path,
            branch,
            base_branch,
            step: WorktreeInitStep::Pending,
            message: queue_message,
        })
    }

    pub fn cancel(
        &self,
        app: &AppHandle,
        job_id: &str,
    ) -> Result<WorktreeInitCancelResult, String> {
        let is_running = {
            let mut runtime = self
                .inner
                .lock()
                .map_err(|_| "worktree 初始化状态锁定失败".to_string())?;

            let Some(job) = runtime.jobs.get_mut(job_id) else {
                return Err("创建任务不存在".to_string());
            };

            job.cancel_requested = true;
            job.updated_at = now_millis();
            job.is_running
        };

        if is_running {
            let payload = {
                let runtime = self
                    .inner
                    .lock()
                    .map_err(|_| "worktree 初始化状态锁定失败".to_string())?;
                let Some(job) = runtime.jobs.get(job_id) else {
                    return Err("创建任务不存在".to_string());
                };
                WorktreeInitProgressPayload {
                    job_id: job.job_id.clone(),
                    project_id: job.project_id.clone(),
                    project_path: job.project_path.clone(),
                    worktree_path: job.worktree_path.clone(),
                    branch: job.branch.clone(),
                    base_branch: job.base_branch.clone(),
                    step: job.step.clone(),
                    message: "已收到取消请求，等待当前步骤结束".to_string(),
                    error: None,
                }
            };
            if let Err(error) = app.emit(WORKTREE_INIT_PROGRESS_EVENT, payload.clone()) {
                log::warn!("发送 worktree-init-progress 失败: {}", error);
            }
            web_event_bus::publish(WORKTREE_INIT_PROGRESS_EVENT, &payload);
        } else {
            self.finish_cancelled(app, job_id, "已取消（已从队列移除）".to_string());
        }

        Ok(WorktreeInitCancelResult {
            job_id: job_id.to_string(),
            cancelled: true,
        })
    }

    pub fn retry(
        &self,
        app: &AppHandle,
        request: WorktreeInitRetryRequest,
    ) -> Result<WorktreeInitStartResult, String> {
        let runtime = self
            .inner
            .lock()
            .map_err(|_| "worktree 初始化状态锁定失败".to_string())?;

        let Some(job) = runtime.jobs.get(&request.job_id) else {
            return Err("创建任务不存在".to_string());
        };

        if job.is_running {
            return Err("创建任务仍在进行中，暂不可重试".to_string());
        }

        let start_request = WorktreeInitStartRequest {
            project_id: job.project_id.clone(),
            project_path: job.project_path.clone(),
            branch: job.branch.clone(),
            create_branch: job.create_branch,
            base_branch: job.base_branch.clone(),
            target_path: Some(job.worktree_path.clone()),
        };

        drop(runtime);
        self.start(app, start_request)
    }

    pub fn query_status(
        &self,
        query: WorktreeInitStatusQuery,
    ) -> Result<Vec<WorktreeInitJobStatus>, String> {
        let runtime = self
            .inner
            .lock()
            .map_err(|_| "worktree 初始化状态锁定失败".to_string())?;

        let query_project_id = query.project_id.map(|value| value.trim().to_string());
        let query_project_key = query
            .project_path
            .map(|value| normalize_path_for_compare(&value));

        let mut jobs: Vec<WorktreeInitJobStatus> = runtime
            .jobs
            .values()
            .filter(|job| {
                if let Some(project_id) = query_project_id.as_ref() {
                    if &job.project_id != project_id {
                        return false;
                    }
                }
                if let Some(project_key) = query_project_key.as_ref() {
                    if &job.project_key != project_key {
                        return false;
                    }
                }
                true
            })
            .map(|job| WorktreeInitJobStatus {
                job_id: job.job_id.clone(),
                project_id: job.project_id.clone(),
                project_path: job.project_path.clone(),
                worktree_path: job.worktree_path.clone(),
                branch: job.branch.clone(),
                base_branch: job.base_branch.clone(),
                create_branch: job.create_branch,
                step: job.step.clone(),
                message: job.message.clone(),
                error: job.error.clone(),
                updated_at: job.updated_at,
                is_running: job.is_running,
                cancel_requested: job.cancel_requested,
            })
            .collect();

        jobs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        Ok(jobs)
    }

    fn spawn_job(&self, app: AppHandle, job_id: String) {
        let state = self.clone();
        thread::spawn(move || {
            state.run_job(app, job_id);
        });
    }

    fn run_job(&self, app: AppHandle, job_id: String) {
        let Some(job_snapshot) = self.snapshot_job(&job_id) else {
            return;
        };

        match self.run_job_flow(&app, &job_id, &job_snapshot) {
            JobRunOutcome::Ready(warning) => self.finish_ready(&app, &job_id, warning),
            JobRunOutcome::Failed(error) => self.finish_failed(&app, &job_id, error),
            JobRunOutcome::Cancelled(message) => self.finish_cancelled(&app, &job_id, message),
        }
    }

    fn run_job_flow(
        &self,
        app: &AppHandle,
        job_id: &str,
        job_snapshot: &WorktreeInitJob,
    ) -> JobRunOutcome {
        self.emit_running_step(
            app,
            job_id,
            WorktreeInitStep::Validating,
            "执行中：校验仓库状态...",
        );

        if self.is_cancel_requested(job_id) {
            return JobRunOutcome::Cancelled("已取消".to_string());
        }

        let checking_message = if job_snapshot.create_branch {
            "执行中：校验分支与基线可用性..."
        } else {
            "执行中：校验分支可用性..."
        };
        self.emit_running_step(
            app,
            job_id,
            WorktreeInitStep::CheckingBranch,
            checking_message,
        );

        if let Err(error) = validate_branch(
            &job_snapshot.project_path,
            &job_snapshot.branch,
            job_snapshot.create_branch,
        ) {
            return JobRunOutcome::Failed(error);
        }

        let start_point = match resolve_create_start_point(job_snapshot) {
            Ok(value) => value,
            Err(error) => return JobRunOutcome::Failed(error),
        };

        if self.is_cancel_requested(job_id) {
            return JobRunOutcome::Cancelled("已取消".to_string());
        }

        self.emit_running_step(
            app,
            job_id,
            WorktreeInitStep::CreatingWorktree,
            "执行中：正在创建 Git worktree...",
        );

        let created_path = match git_ops::add_worktree(
            &job_snapshot.project_path,
            Some(&job_snapshot.worktree_path),
            &job_snapshot.branch,
            job_snapshot.create_branch,
            start_point.as_deref(),
        ) {
            Ok(result) => result.path,
            Err(error) => return JobRunOutcome::Failed(error),
        };

        if self.is_cancel_requested(job_id) {
            return self.rollback_created_worktree(job_snapshot, &created_path);
        }

        self.emit_running_step(
            app,
            job_id,
            WorktreeInitStep::PreparingEnvironment,
            "执行中：准备工作区环境...",
        );

        let setup_warning = worktree_setup::prepare_worktree_environment(
            &job_snapshot.project_path,
            &created_path,
            &job_snapshot.branch,
        );

        if let Some(warning) = setup_warning.as_ref() {
            log::warn!(
                "worktree 环境初始化存在告警，job_id={} path={}: {}",
                job_id,
                created_path,
                warning
            );
        }

        self.emit_running_step(
            app,
            job_id,
            WorktreeInitStep::Syncing,
            "执行中：同步工作区状态...",
        );

        if let Err(error) = git_ops::list_worktrees(&job_snapshot.project_path) {
            log::warn!("同步 worktree 列表失败: {}", error);
        }

        JobRunOutcome::Ready(setup_warning)
    }

    fn emit_running_step(
        &self,
        app: &AppHandle,
        job_id: &str,
        step: WorktreeInitStep,
        message: &str,
    ) {
        self.emit_progress(app, job_id, step, message.to_string(), None);
    }

    fn rollback_created_worktree(
        &self,
        job_snapshot: &WorktreeInitJob,
        created_path: &str,
    ) -> JobRunOutcome {
        match git_ops::remove_worktree(&job_snapshot.project_path, created_path, true) {
            Ok(_) => JobRunOutcome::Cancelled("创建任务已取消，已回滚新建 worktree".to_string()),
            Err(error) => JobRunOutcome::Failed(format!(
                "创建任务已取消，但回滚失败：{}。请手动清理目录 {}",
                error, created_path
            )),
        }
    }

    fn snapshot_job(&self, job_id: &str) -> Option<WorktreeInitJob> {
        let runtime = self.inner.lock().ok()?;
        runtime.jobs.get(job_id).cloned()
    }

    fn is_cancel_requested(&self, job_id: &str) -> bool {
        let Ok(runtime) = self.inner.lock() else {
            return false;
        };
        runtime
            .jobs
            .get(job_id)
            .map(|job| job.cancel_requested)
            .unwrap_or(false)
    }

    fn finish_ready(&self, app: &AppHandle, job_id: &str, warning: Option<String>) {
        self.emit_progress(
            app,
            job_id,
            WorktreeInitStep::Ready,
            if warning.is_some() {
                "创建完成（环境初始化存在告警）".to_string()
            } else {
                "创建完成".to_string()
            },
            warning,
        );
        self.finalize_job(app, job_id);
    }

    fn finish_failed(&self, app: &AppHandle, job_id: &str, error: String) {
        self.emit_progress(
            app,
            job_id,
            WorktreeInitStep::Failed,
            "创建失败".to_string(),
            Some(error),
        );
        self.finalize_job(app, job_id);
    }

    fn finish_cancelled(&self, app: &AppHandle, job_id: &str, message: String) {
        self.emit_progress(app, job_id, WorktreeInitStep::Cancelled, message, None);
        self.finalize_job(app, job_id);
    }

    fn emit_progress(
        &self,
        app: &AppHandle,
        job_id: &str,
        step: WorktreeInitStep,
        message: String,
        error: Option<String>,
    ) {
        let payload = {
            let Ok(mut runtime) = self.inner.lock() else {
                return;
            };
            let Some(job) = runtime.jobs.get_mut(job_id) else {
                return;
            };

            job.step = step.clone();
            job.message = message.clone();
            job.error = error.clone();
            job.updated_at = now_millis();

            WorktreeInitProgressPayload {
                job_id: job.job_id.clone(),
                project_id: job.project_id.clone(),
                project_path: job.project_path.clone(),
                worktree_path: job.worktree_path.clone(),
                branch: job.branch.clone(),
                base_branch: job.base_branch.clone(),
                step,
                message,
                error,
            }
        };

        if let Err(error) = app.emit(WORKTREE_INIT_PROGRESS_EVENT, payload.clone()) {
            log::warn!("发送 worktree-init-progress 失败: {}", error);
        }
        web_event_bus::publish(WORKTREE_INIT_PROGRESS_EVENT, &payload);
    }

    fn finalize_job(&self, app: &AppHandle, job_id: &str) {
        let mut next_job_to_start: Option<String> = None;

        {
            let Ok(mut runtime) = self.inner.lock() else {
                return;
            };

            let Some(project_key) = runtime.jobs.get(job_id).map(|job| job.project_key.clone())
            else {
                return;
            };

            if let Some(job) = runtime.jobs.get_mut(job_id) {
                job.is_running = false;
            }

            let next_candidate =
                dequeue_project_job(&mut runtime.project_queues, &project_key, job_id);

            if let Some(next_job_id) = next_candidate {
                let Some(next_job) = runtime.jobs.get_mut(&next_job_id) else {
                    return;
                };
                if next_job.is_running || is_terminal_step(&next_job.step) {
                    return;
                }
                next_job.is_running = true;
                next_job.updated_at = now_millis();
                next_job_to_start = Some(next_job_id);
            }
        }

        if let Some(next_job_id) = next_job_to_start {
            if self.is_cancel_requested(&next_job_id) {
                self.finish_cancelled(app, &next_job_id, "已取消（已从队列移除）".to_string());
                return;
            }
            self.spawn_job(app.clone(), next_job_id);
        }
    }
}

fn validate_branch(project_path: &str, branch: &str, create_branch: bool) -> Result<(), String> {
    let branches = git_ops::list_branches(project_path);

    if create_branch {
        if branches.iter().any(|item| item.name == branch) {
            return Err("分支已存在，请改用“已有分支”模式或更换分支名".to_string());
        }
        return Ok(());
    }

    if branches.iter().any(|item| item.name == branch) {
        return Ok(());
    }

    Err("分支不存在或不可用，请检查分支名称".to_string())
}

fn resolve_create_start_point(job: &WorktreeInitJob) -> Result<Option<String>, String> {
    if !job.create_branch {
        return Ok(None);
    }

    let Some(base_branch) = job.base_branch.as_ref() else {
        return Err("基线分支不可用：未提供基线分支".to_string());
    };

    git_ops::resolve_create_branch_start_point(&job.project_path, base_branch).map(Some)
}

fn resolve_request_base_branch(
    project_path: &str,
    requested: Option<&str>,
) -> Result<String, String> {
    if let Some(base) = requested
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
    {
        return Ok(base);
    }

    let branches = git_ops::list_branches(project_path);
    choose_default_base_branch(&branches)
        .ok_or_else(|| "基线分支不可用：无法确定默认基线分支，请手动选择".to_string())
}

fn choose_default_base_branch(branches: &[BranchListItem]) -> Option<String> {
    if let Some(item) = branches.iter().find(|item| item.name == "develop") {
        return Some(item.name.clone());
    }
    if let Some(item) = branches.iter().find(|item| item.is_main) {
        return Some(item.name.clone());
    }
    branches.first().map(|item| item.name.clone())
}

fn is_terminal_step(step: &WorktreeInitStep) -> bool {
    matches!(
        step,
        WorktreeInitStep::Ready | WorktreeInitStep::Failed | WorktreeInitStep::Cancelled
    )
}

fn build_queue_message(ahead: usize) -> String {
    if ahead == 0 {
        return "排队中（即将开始）".to_string();
    }
    format!("排队中（前方还有 {} 个任务）", ahead)
}

fn enqueue_project_job(
    queues: &mut HashMap<String, VecDeque<String>>,
    project_key: &str,
    job_id: &str,
) -> usize {
    let queue = queues.entry(project_key.to_string()).or_default();
    queue.push_back(job_id.to_string());
    queue.len().saturating_sub(1)
}

fn dequeue_project_job(
    queues: &mut HashMap<String, VecDeque<String>>,
    project_key: &str,
    finished_job_id: &str,
) -> Option<String> {
    let mut next: Option<String> = None;
    let mut should_remove = false;

    if let Some(queue) = queues.get_mut(project_key) {
        if let Some(index) = queue.iter().position(|item| item == finished_job_id) {
            queue.remove(index);
        }
        next = queue.front().cloned();
        should_remove = queue.is_empty();
    }

    if should_remove {
        queues.remove(project_key);
    }

    next
}

fn normalize_path_for_compare(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    let normalized = trimmed.replace("\\", "/").trim_end_matches("/").to_string();
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
    use super::{
        build_queue_message, choose_default_base_branch, dequeue_project_job, enqueue_project_job,
    };
    use crate::models::BranchListItem;
    use std::collections::{HashMap, VecDeque};

    #[test]
    fn queue_should_follow_fifo_order() {
        let mut queues: HashMap<String, VecDeque<String>> = HashMap::new();
        let project_key = "repo";

        assert_eq!(enqueue_project_job(&mut queues, project_key, "job-1"), 0);
        assert_eq!(enqueue_project_job(&mut queues, project_key, "job-2"), 1);
        assert_eq!(enqueue_project_job(&mut queues, project_key, "job-3"), 2);

        assert_eq!(
            dequeue_project_job(&mut queues, project_key, "job-1"),
            Some("job-2".to_string())
        );
        assert_eq!(
            dequeue_project_job(&mut queues, project_key, "job-2"),
            Some("job-3".to_string())
        );
        assert_eq!(dequeue_project_job(&mut queues, project_key, "job-3"), None);
        assert!(!queues.contains_key(project_key));
    }

    #[test]
    fn queue_cancelled_pending_job_should_not_block_following_jobs() {
        let mut queues: HashMap<String, VecDeque<String>> = HashMap::new();
        let project_key = "repo";

        enqueue_project_job(&mut queues, project_key, "job-1");
        enqueue_project_job(&mut queues, project_key, "job-2");
        enqueue_project_job(&mut queues, project_key, "job-3");

        assert_eq!(
            dequeue_project_job(&mut queues, project_key, "job-2"),
            Some("job-1".to_string())
        );
        assert_eq!(
            dequeue_project_job(&mut queues, project_key, "job-1"),
            Some("job-3".to_string())
        );
    }

    #[test]
    fn default_base_branch_should_prefer_develop_then_main_branch() {
        let branches = vec![
            BranchListItem {
                name: "main".to_string(),
                is_main: true,
            },
            BranchListItem {
                name: "develop".to_string(),
                is_main: false,
            },
        ];
        assert_eq!(
            choose_default_base_branch(&branches),
            Some("develop".to_string())
        );

        let fallback = vec![
            BranchListItem {
                name: "main".to_string(),
                is_main: true,
            },
            BranchListItem {
                name: "feature/x".to_string(),
                is_main: false,
            },
        ];
        assert_eq!(
            choose_default_base_branch(&fallback),
            Some("main".to_string())
        );
    }

    #[test]
    fn queue_message_should_reflect_waiting_count() {
        assert_eq!(build_queue_message(0), "排队中（即将开始）");
        assert_eq!(build_queue_message(2), "排队中（前方还有 2 个任务）");
    }
}
