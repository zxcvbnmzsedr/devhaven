use std::collections::HashMap;

use super::types::{JobId, QuickCommandRecord, QuickCommandState, now_millis};

#[derive(Debug, Default)]
pub struct QuickCommandRegistry {
    jobs: HashMap<JobId, QuickCommandRecord>,
}

impl QuickCommandRegistry {
    pub fn start_job(
        &mut self,
        project_id: String,
        project_path: String,
        script_id: String,
        command: String,
    ) -> QuickCommandRecord {
        let now = now_millis();
        let record = QuickCommandRecord {
            job_id: JobId::new(),
            project_id,
            project_path,
            script_id,
            command,
            state: QuickCommandState::Running,
            created_at: now,
            updated_at: now,
            exit_code: None,
            error: None,
        };
        self.jobs.insert(record.job_id.clone(), record.clone());
        record
    }

    pub fn set_state(
        &mut self,
        job_id: &JobId,
        state: QuickCommandState,
    ) -> Option<QuickCommandRecord> {
        let job = self.jobs.get_mut(job_id)?;
        job.state = state;
        job.updated_at = now_millis();
        Some(job.clone())
    }

    pub fn finish_job(
        &mut self,
        job_id: &JobId,
        state: QuickCommandState,
        exit_code: Option<i32>,
        error: Option<String>,
    ) -> Option<QuickCommandRecord> {
        let job = self.jobs.get_mut(job_id)?;
        job.state = state;
        job.exit_code = exit_code;
        job.error = error;
        job.updated_at = now_millis();
        Some(job.clone())
    }

    pub fn list_by_project_path(&self, project_path: Option<&str>) -> Vec<QuickCommandRecord> {
        let mut jobs: Vec<_> = self
            .jobs
            .values()
            .filter(|job| project_path.map(|value| job.project_path == value).unwrap_or(true))
            .cloned()
            .collect();
        jobs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        jobs
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quick_command_registry_tracks_state_transitions() {
        let mut registry = QuickCommandRegistry::default();
        let job = registry.start_job(
            "project-1".to_string(),
            "/tmp/project".to_string(),
            "script-1".to_string(),
            "npm test".to_string(),
        );
        assert_eq!(job.state, QuickCommandState::Running);

        let stopping = registry
            .set_state(&job.job_id, QuickCommandState::StoppingSoft)
            .unwrap();
        assert_eq!(stopping.state, QuickCommandState::StoppingSoft);

        let finished = registry
            .finish_job(
                &job.job_id,
                QuickCommandState::Exited,
                Some(0),
                None,
            )
            .unwrap();
        assert_eq!(finished.exit_code, Some(0));
    }
}
