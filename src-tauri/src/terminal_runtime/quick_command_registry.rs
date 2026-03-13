use std::collections::HashMap;

use super::types::{JobId, QuickCommandRecord, QuickCommandState, now_millis};

const MAX_QUICK_COMMAND_RECORDS: usize = 256;
const QUICK_COMMAND_PRUNE_TARGET: usize = 192;

#[derive(Debug, Default)]
pub struct QuickCommandRegistry {
    jobs: HashMap<JobId, QuickCommandRecord>,
}

impl QuickCommandRegistry {
    pub fn upsert_job(&mut self, record: QuickCommandRecord) -> QuickCommandRecord {
        self.jobs.insert(record.job_id.clone(), record.clone());
        self.prune_finished_jobs();
        record
    }

    #[cfg(test)]
    pub fn start_job(
        &mut self,
        project_id: String,
        project_path: String,
        script_id: String,
        command: String,
    ) -> QuickCommandRecord {
        let now = now_millis();
        self.upsert_job(QuickCommandRecord {
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
        })
    }

    pub fn set_state(
        &mut self,
        job_id: &JobId,
        state: QuickCommandState,
    ) -> Option<QuickCommandRecord> {
        let job = self.jobs.get_mut(job_id)?;
        job.state = state;
        job.updated_at = now_millis();
        let job = job.clone();
        self.prune_finished_jobs();
        Some(job)
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
        let job = job.clone();
        self.prune_finished_jobs();
        Some(job)
    }

    pub fn list_by_project_path(&self, project_path: Option<&str>) -> Vec<QuickCommandRecord> {
        let mut jobs: Vec<_> = self
            .jobs
            .values()
            .filter(|job| {
                project_path
                    .map(|value| job.project_path == value)
                    .unwrap_or(true)
            })
            .cloned()
            .collect();
        jobs.sort_by(|left, right| right.updated_at.cmp(&left.updated_at));
        jobs
    }

    fn prune_finished_jobs(&mut self) {
        if self.jobs.len() <= MAX_QUICK_COMMAND_RECORDS {
            return;
        }

        let removable_count = self.jobs.len().saturating_sub(QUICK_COMMAND_PRUNE_TARGET);
        let mut removable: Vec<(JobId, i64)> = self
            .jobs
            .iter()
            .filter(|(_, job)| {
                matches!(
                    job.state,
                    QuickCommandState::Exited
                        | QuickCommandState::Failed
                        | QuickCommandState::Cancelled
                )
            })
            .map(|(job_id, job)| (job_id.clone(), job.updated_at))
            .collect();
        removable.sort_by_key(|(_, updated_at)| *updated_at);

        for job_id in removable
            .into_iter()
            .map(|(job_id, _)| job_id)
            .take(removable_count)
        {
            self.jobs.remove(&job_id);
        }
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
            .finish_job(&job.job_id, QuickCommandState::Exited, Some(0), None)
            .unwrap();
        assert_eq!(finished.exit_code, Some(0));
    }

    #[test]
    fn quick_command_registry_prunes_finished_jobs_when_over_capacity() {
        let mut registry = QuickCommandRegistry::default();

        for index in 0..(MAX_QUICK_COMMAND_RECORDS + 24) {
            let job = registry.start_job(
                "project-1".to_string(),
                "/tmp/project".to_string(),
                format!("script-{index}"),
                "npm test".to_string(),
            );
            registry.finish_job(&job.job_id, QuickCommandState::Exited, Some(0), None);
        }

        let running = registry.start_job(
            "project-1".to_string(),
            "/tmp/project".to_string(),
            "script-running".to_string(),
            "npm run dev".to_string(),
        );

        assert!(registry.jobs.len() <= MAX_QUICK_COMMAND_RECORDS);
        assert!(registry.jobs.contains_key(&running.job_id));
    }
}
