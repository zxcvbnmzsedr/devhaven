use serde::{Deserialize, Serialize};
use uuid::Uuid;

pub fn now_millis() -> i64 {
    chrono::Utc::now().timestamp_millis()
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(transparent)]
pub struct SessionId(pub String);

impl SessionId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_string(value: impl Into<String>) -> Self {
        Self(value.into())
    }
}

impl Default for SessionId {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, PartialOrd, Ord)]
#[serde(transparent)]
pub struct JobId(pub String);

impl JobId {
    pub fn new() -> Self {
        Self(Uuid::new_v4().to_string())
    }

    pub fn from_string(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl Default for JobId {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum SessionStatus {
    Created,
    Running,
    Exited,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct SessionRecord {
    pub session_id: SessionId,
    pub project_path: String,
    pub cwd: String,
    #[serde(default)]
    pub launch_command: Option<String>,
    #[serde(default)]
    pub env_hash: Option<String>,
    #[serde(default)]
    pub shell: Option<String>,
    #[serde(default)]
    pub pty_id: Option<String>,
    #[serde(default)]
    pub client_ids: Vec<String>,
    #[serde(default)]
    pub output_seq: u64,
    pub status: SessionStatus,
    #[serde(default)]
    pub created_at: i64,
    #[serde(default)]
    pub updated_at: i64,
    #[serde(default)]
    pub exit_code: Option<i32>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct QuickCommandRecord {
    pub job_id: JobId,
    pub project_id: String,
    pub project_path: String,
    pub script_id: String,
    pub command: String,
    pub state: QuickCommandState,
    pub created_at: i64,
    pub updated_at: i64,
    #[serde(default)]
    pub exit_code: Option<i32>,
    #[serde(default)]
    pub error: Option<String>,
}
