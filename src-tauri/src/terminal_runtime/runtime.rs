use super::quick_command_registry::QuickCommandRegistry;
use super::session_registry::SessionRegistry;
use super::types::{JobId, QuickCommandRecord, QuickCommandState, SessionId, SessionRecord};
use crate::models::TerminalLayoutSnapshot;
#[cfg(test)]
use crate::models::TerminalLayoutSnapshotSummary;
use std::collections::HashMap;
use std::sync::{Arc, Mutex, OnceLock};

static TERMINAL_RUNTIME: OnceLock<TerminalRuntime> = OnceLock::new();

pub fn shared_runtime() -> &'static TerminalRuntime {
    TERMINAL_RUNTIME.get_or_init(TerminalRuntime::default)
}

#[derive(Debug, Default)]
pub struct TerminalRuntime {
    sessions: Arc<Mutex<SessionRegistry>>,
    quick_commands: Arc<Mutex<QuickCommandRegistry>>,
    layout_snapshots: Arc<Mutex<HashMap<String, TerminalLayoutSnapshot>>>,
}

#[cfg(test)]
fn build_layout_snapshot_summary(
    project_path: &str,
    snapshot: &TerminalLayoutSnapshot,
) -> TerminalLayoutSnapshotSummary {
    let snapshot_obj = snapshot.as_object();
    TerminalLayoutSnapshotSummary {
        project_path: project_path.to_string(),
        project_id: snapshot_obj
            .and_then(|value| value.get("projectId"))
            .and_then(|value| value.as_str())
            .map(|value| value.to_string()),
        updated_at: snapshot_obj
            .and_then(|value| value.get("updatedAt"))
            .and_then(|value| value.as_i64()),
        revision: snapshot_obj
            .and_then(|value| value.get("revision"))
            .and_then(|value| value.as_i64()),
    }
}

impl TerminalRuntime {
    pub fn register_session(
        &self,
        session_id: SessionId,
        project_path: String,
        cwd: String,
        launch_command: Option<String>,
        shell: Option<String>,
    ) -> Result<SessionRecord, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.register_session(session_id, project_path, cwd, launch_command, shell))
    }

    pub fn attach_session_client(
        &self,
        session_id: &SessionId,
        client_id: String,
    ) -> Result<Option<SessionRecord>, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.attach_client(session_id, client_id))
    }

    pub fn detach_session_client(
        &self,
        session_id: &SessionId,
        client_id: &str,
    ) -> Result<Option<SessionRecord>, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.detach_client(session_id, client_id))
    }

    pub fn bind_session_pty(
        &self,
        session_id: &SessionId,
        pty_id: String,
    ) -> Result<Option<SessionRecord>, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.bind_pty(session_id, pty_id))
    }

    pub fn note_session_output(&self, session_id: &SessionId) -> Result<Option<u64>, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.note_output(session_id))
    }

    pub fn mark_session_exited(
        &self,
        session_id: &SessionId,
        exit_code: Option<i32>,
    ) -> Result<Option<SessionRecord>, String> {
        let mut sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.mark_exited(session_id, exit_code))
    }

    pub fn start_quick_command(
        &self,
        record: QuickCommandRecord,
    ) -> Result<QuickCommandRecord, String> {
        let mut jobs = self
            .quick_commands
            .lock()
            .map_err(|_| "terminal runtime quick-command 锁已损坏".to_string())?;
        Ok(jobs.upsert_job(record))
    }

    pub fn update_quick_command_state(
        &self,
        job_id: &JobId,
        state: QuickCommandState,
    ) -> Result<Option<QuickCommandRecord>, String> {
        let mut jobs = self
            .quick_commands
            .lock()
            .map_err(|_| "terminal runtime quick-command 锁已损坏".to_string())?;
        Ok(jobs.set_state(job_id, state))
    }

    pub fn finish_quick_command(
        &self,
        job_id: &JobId,
        state: QuickCommandState,
        exit_code: Option<i32>,
        error: Option<String>,
    ) -> Result<Option<QuickCommandRecord>, String> {
        let mut jobs = self
            .quick_commands
            .lock()
            .map_err(|_| "terminal runtime quick-command 锁已损坏".to_string())?;
        Ok(jobs.finish_job(job_id, state, exit_code, error))
    }

    #[cfg(test)]
    pub fn load_session(&self, session_id: &SessionId) -> Result<Option<SessionRecord>, String> {
        let sessions = self
            .sessions
            .lock()
            .map_err(|_| "terminal runtime session 锁已损坏".to_string())?;
        Ok(sessions.get(session_id).cloned())
    }

    pub fn list_quick_commands(
        &self,
        project_path: Option<&str>,
    ) -> Result<Vec<QuickCommandRecord>, String> {
        let jobs = self
            .quick_commands
            .lock()
            .map_err(|_| "terminal runtime quick-command 锁已损坏".to_string())?;
        Ok(jobs.list_by_project_path(project_path))
    }

    pub fn import_layout_snapshots(
        &self,
        snapshots: Vec<(String, TerminalLayoutSnapshot)>,
    ) -> Result<(), String> {
        let mut layout_snapshots = self
            .layout_snapshots
            .lock()
            .map_err(|_| "terminal runtime layout snapshot 锁已损坏".to_string())?;
        layout_snapshots.clear();
        layout_snapshots.extend(snapshots);
        Ok(())
    }

    pub fn upsert_layout_snapshot(
        &self,
        project_path: String,
        snapshot: TerminalLayoutSnapshot,
    ) -> Result<(), String> {
        let mut layout_snapshots = self
            .layout_snapshots
            .lock()
            .map_err(|_| "terminal runtime layout snapshot 锁已损坏".to_string())?;
        layout_snapshots.insert(project_path, snapshot);
        Ok(())
    }

    pub fn load_layout_snapshot_by_project_path(
        &self,
        project_path: &str,
    ) -> Result<Option<TerminalLayoutSnapshot>, String> {
        let layout_snapshots = self
            .layout_snapshots
            .lock()
            .map_err(|_| "terminal runtime layout snapshot 锁已损坏".to_string())?;
        Ok(layout_snapshots.get(project_path).cloned())
    }

    pub fn delete_layout_snapshot(
        &self,
        project_path: &str,
    ) -> Result<Option<TerminalLayoutSnapshot>, String> {
        let mut layout_snapshots = self
            .layout_snapshots
            .lock()
            .map_err(|_| "terminal runtime layout snapshot 锁已损坏".to_string())?;
        Ok(layout_snapshots.remove(project_path))
    }

    #[cfg(test)]
    pub fn list_layout_snapshot_summaries(
        &self,
    ) -> Result<Vec<TerminalLayoutSnapshotSummary>, String> {
        let layout_snapshots = self
            .layout_snapshots
            .lock()
            .map_err(|_| "terminal runtime layout snapshot 锁已损坏".to_string())?;
        let mut summaries: Vec<_> = layout_snapshots
            .iter()
            .map(|(project_path, snapshot)| build_layout_snapshot_summary(project_path, snapshot))
            .collect();
        summaries.sort_by(|left, right| {
            let right_sort = right.updated_at.or(right.revision).unwrap_or_default();
            let left_sort = left.updated_at.or(left.revision).unwrap_or_default();
            right_sort.cmp(&left_sort)
        });
        Ok(summaries)
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[test]
    fn shared_runtime_preserves_session_state() {
        let runtime = shared_runtime();
        let session_id = SessionId::from_string("test-session-runtime");
        runtime
            .register_session(
                session_id.clone(),
                "/tmp/project-a".to_string(),
                "/tmp/project-a".to_string(),
                None,
                Some("/bin/zsh".to_string()),
            )
            .unwrap();
        runtime
            .attach_session_client(&session_id, "client-1".to_string())
            .unwrap();
        let loaded = runtime.load_session(&session_id).unwrap().unwrap();
        assert_eq!(loaded.client_ids, vec!["client-1".to_string()]);
        runtime
            .detach_session_client(&session_id, "client-1")
            .unwrap();
    }

    #[test]
    fn runtime_layout_snapshot_registry_round_trips_json_snapshots() {
        let runtime = TerminalRuntime::default();
        let snapshot = json!({
            "version": 2,
            "projectId": "project-1",
            "projectPath": "/tmp/project-a",
            "windowId": "window-1",
            "tabs": [],
            "panes": {},
            "activeTabId": "tab-1",
            "updatedAt": 42,
            "revision": 42,
        });

        runtime
            .import_layout_snapshots(vec![("/tmp/project-a".to_string(), snapshot.clone())])
            .unwrap();

        let loaded = runtime
            .load_layout_snapshot_by_project_path("/tmp/project-a")
            .unwrap();
        assert_eq!(loaded, Some(snapshot.clone()));

        let summaries = runtime.list_layout_snapshot_summaries().unwrap();
        assert_eq!(summaries.len(), 1);
        assert_eq!(summaries[0].project_path, "/tmp/project-a");
        assert_eq!(summaries[0].project_id.as_deref(), Some("project-1"));
        assert_eq!(summaries[0].updated_at, Some(42));
        assert_eq!(summaries[0].revision, Some(42));

        let deleted = runtime.delete_layout_snapshot("/tmp/project-a").unwrap();
        assert_eq!(deleted, Some(snapshot));
        assert!(
            runtime
                .load_layout_snapshot_by_project_path("/tmp/project-a")
                .unwrap()
                .is_none()
        );
    }
}
