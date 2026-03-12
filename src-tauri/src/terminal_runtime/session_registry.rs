use std::collections::HashMap;

use super::types::{SessionId, SessionRecord, SessionStatus, now_millis};

#[derive(Debug, Default)]
pub struct SessionRegistry {
    sessions: HashMap<SessionId, SessionRecord>,
}

impl SessionRegistry {
    pub fn register_session(
        &mut self,
        session_id: SessionId,
        project_path: String,
        cwd: String,
        launch_command: Option<String>,
        shell: Option<String>,
    ) -> SessionRecord {
        let now = now_millis();
        if let Some(existing) = self.sessions.get_mut(&session_id) {
            existing.project_path = project_path;
            existing.cwd = cwd;
            if launch_command.is_some() {
                existing.launch_command = launch_command;
            }
            if shell.is_some() {
                existing.shell = shell;
            }
            existing.updated_at = now;
            return existing.clone();
        }
        let record = SessionRecord {
            session_id: session_id.clone(),
            project_path,
            cwd,
            launch_command,
            env_hash: None,
            shell,
            pty_id: None,
            client_ids: Vec::new(),
            output_seq: 0,
            status: SessionStatus::Created,
            created_at: now,
            updated_at: now,
            exit_code: None,
        };
        self.sessions.insert(session_id, record.clone());
        record
    }

    pub fn bind_pty(&mut self, session_id: &SessionId, pty_id: String) -> Option<SessionRecord> {
        let session = self.sessions.get_mut(session_id)?;
        session.pty_id = Some(pty_id);
        session.status = SessionStatus::Running;
        session.updated_at = now_millis();
        Some(session.clone())
    }

    pub fn attach_client(&mut self, session_id: &SessionId, client_id: String) -> Option<SessionRecord> {
        let session = self.sessions.get_mut(session_id)?;
        if !session.client_ids.iter().any(|value| value == &client_id) {
            session.client_ids.push(client_id);
        }
        session.updated_at = now_millis();
        Some(session.clone())
    }

    pub fn detach_client(&mut self, session_id: &SessionId, client_id: &str) -> Option<SessionRecord> {
        let session = self.sessions.get_mut(session_id)?;
        session.client_ids.retain(|value| value != client_id);
        session.updated_at = now_millis();
        Some(session.clone())
    }

    pub fn note_output(&mut self, session_id: &SessionId) -> Option<u64> {
        let session = self.sessions.get_mut(session_id)?;
        session.output_seq = session.output_seq.saturating_add(1);
        session.updated_at = now_millis();
        Some(session.output_seq)
    }

    pub fn mark_exited(&mut self, session_id: &SessionId, exit_code: Option<i32>) -> Option<SessionRecord> {
        let session = self.sessions.get_mut(session_id)?;
        session.status = SessionStatus::Exited;
        session.exit_code = exit_code;
        session.updated_at = now_millis();
        Some(session.clone())
    }

    #[cfg(test)]
    pub fn get(&self, session_id: &SessionId) -> Option<&SessionRecord> {
        self.sessions.get(session_id)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_registry_tracks_lifecycle() {
        let mut registry = SessionRegistry::default();
        let session_id = SessionId::new();

        registry.register_session(
            session_id.clone(),
            "/tmp/project".to_string(),
            "/tmp/project".to_string(),
            Some("npm run dev".to_string()),
            Some("/bin/zsh".to_string()),
        );
        registry.bind_pty(&session_id, "pty-1".to_string());
        let seq = registry.note_output(&session_id).unwrap();
        assert_eq!(seq, 1);
        let exited = registry.mark_exited(&session_id, Some(0)).unwrap();
        assert_eq!(exited.status, SessionStatus::Exited);
        assert_eq!(exited.exit_code, Some(0));
    }
}
