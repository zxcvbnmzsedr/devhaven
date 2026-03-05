use std::collections::HashMap;

use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;

pub type SwiftDate = f64;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppStateFile {
    pub version: i32,
    pub tags: Vec<TagData>,
    pub directories: Vec<String>,
    #[serde(default, rename = "directProjectPaths")]
    pub direct_project_paths: Vec<String>,
    #[serde(default, rename = "recycleBin")]
    pub recycle_bin: Vec<String>,
    #[serde(default, rename = "favoriteProjectPaths")]
    pub favorite_project_paths: Vec<String>,
    #[serde(default)]
    pub settings: AppSettings,
}

pub type TerminalWorkspace = JsonValue;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalWorkspaceSummary {
    pub project_path: String,
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TerminalWorkspacesFile {
    pub version: i32,
    #[serde(default)]
    pub workspaces: HashMap<String, TerminalWorkspace>,
}

impl Default for TerminalWorkspacesFile {
    fn default() -> Self {
        Self {
            version: 1,
            workspaces: HashMap::new(),
        }
    }
}

impl Default for AppStateFile {
    /// 默认应用状态结构。
    fn default() -> Self {
        Self {
            version: 4,
            tags: Vec::new(),
            directories: Vec::new(),
            direct_project_paths: Vec::new(),
            recycle_bin: Vec::new(),
            favorite_project_paths: Vec::new(),
            settings: AppSettings::default(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AppSettings {
    #[serde(default)]
    pub editor_open_tool: OpenToolSettings,
    #[serde(default)]
    pub terminal_open_tool: OpenToolSettings,
    #[serde(default = "default_terminal_use_webgl_renderer")]
    pub terminal_use_webgl_renderer: bool,
    #[serde(default = "default_terminal_theme")]
    pub terminal_theme: String,
    #[serde(default)]
    pub git_identities: Vec<GitIdentity>,
    #[serde(default = "default_project_list_view_mode")]
    pub project_list_view_mode: ProjectListViewMode,
    #[serde(default = "default_shared_scripts_root")]
    pub shared_scripts_root: String,
    #[serde(default = "default_vite_dev_port")]
    pub vite_dev_port: u16,
    #[serde(default = "default_web_enabled")]
    pub web_enabled: bool,
    #[serde(default = "default_web_bind_host")]
    pub web_bind_host: String,
    #[serde(default = "default_web_bind_port")]
    pub web_bind_port: u16,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            editor_open_tool: OpenToolSettings::default(),
            terminal_open_tool: OpenToolSettings::default(),
            terminal_use_webgl_renderer: true,
            terminal_theme: default_terminal_theme(),
            git_identities: Vec::new(),
            project_list_view_mode: default_project_list_view_mode(),
            shared_scripts_root: default_shared_scripts_root(),
            vite_dev_port: default_vite_dev_port(),
            web_enabled: default_web_enabled(),
            web_bind_host: default_web_bind_host(),
            web_bind_port: default_web_bind_port(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProjectListViewMode {
    Card,
    List,
}

fn default_project_list_view_mode() -> ProjectListViewMode {
    ProjectListViewMode::Card
}

fn default_terminal_use_webgl_renderer() -> bool {
    true
}

fn default_terminal_theme() -> String {
    "DevHaven Dark".to_string()
}

fn default_shared_scripts_root() -> String {
    "~/.devhaven/scripts".to_string()
}

fn default_vite_dev_port() -> u16 {
    1420
}

fn default_web_enabled() -> bool {
    true
}

fn default_web_bind_host() -> String {
    "0.0.0.0".to_string()
}

fn default_web_bind_port() -> u16 {
    3210
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OpenToolSettings {
    pub command_path: String,
    pub arguments: Vec<String>,
}

impl Default for OpenToolSettings {
    fn default() -> Self {
        Self {
            command_path: String::new(),
            arguments: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitIdentity {
    pub name: String,
    pub email: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillAgent {
    pub id: String,
    pub label: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillSummary {
    pub name: String,
    pub description: String,
    pub canonical_path: String,
    #[serde(default)]
    pub paths: Vec<String>,
    #[serde(default)]
    pub agents: Vec<GlobalSkillAgent>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillsSnapshot {
    #[serde(default)]
    pub agents: Vec<GlobalSkillAgent>,
    #[serde(default)]
    pub skills: Vec<GlobalSkillSummary>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillInstallRequest {
    pub source: String,
    #[serde(default)]
    pub skill_names: Vec<String>,
    #[serde(default)]
    pub agent_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillInstallResult {
    pub command: String,
    pub stdout: String,
    pub stderr: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GlobalSkillUninstallRequest {
    pub skill_name: String,
    pub canonical_path: String,
    #[serde(default)]
    pub paths: Vec<String>,
    pub agent_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TagData {
    pub name: String,
    pub color: ColorData,
    pub hidden: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ColorData {
    pub r: f64,
    pub g: f64,
    pub b: f64,
    pub a: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Project {
    pub id: String,
    pub name: String,
    pub path: String,
    pub tags: Vec<String>,
    #[serde(default)]
    pub scripts: Vec<ProjectScript>,
    #[serde(default)]
    pub worktrees: Vec<ProjectWorktree>,
    pub mtime: SwiftDate,
    pub size: i64,
    pub checksum: String,
    pub git_commits: i64,
    pub git_last_commit: SwiftDate,
    #[serde(default)]
    pub git_last_commit_message: Option<String>,
    pub git_daily: Option<String>,
    pub created: SwiftDate,
    pub checked: SwiftDate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectWorktree {
    pub id: String,
    pub name: String,
    pub path: String,
    pub branch: String,
    #[serde(default)]
    pub base_branch: Option<String>,
    #[serde(default)]
    pub inherit_config: bool,
    pub created: SwiftDate,
    #[serde(default)]
    pub status: Option<WorktreeInitVisualStatus>,
    #[serde(default)]
    pub init_step: Option<WorktreeInitStep>,
    #[serde(default)]
    pub init_message: Option<String>,
    #[serde(default)]
    pub init_error: Option<String>,
    #[serde(default)]
    pub init_job_id: Option<String>,
    #[serde(default)]
    pub updated_at: Option<SwiftDate>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectScript {
    pub id: String,
    pub name: String,
    pub start: String,
    #[serde(default)]
    pub param_schema: Vec<ScriptParamField>,
    #[serde(default)]
    pub template_params: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum ScriptParamFieldType {
    Text,
    Number,
    Secret,
}

impl Default for ScriptParamFieldType {
    fn default() -> Self {
        Self::Text
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScriptParamField {
    pub key: String,
    pub label: String,
    #[serde(default)]
    pub r#type: ScriptParamFieldType,
    #[serde(default)]
    pub required: bool,
    #[serde(default)]
    pub default_value: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedScriptEntry {
    pub id: String,
    pub name: String,
    pub absolute_path: String,
    pub relative_path: String,
    pub command_template: String,
    #[serde(default)]
    pub params: Vec<ScriptParamField>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedScriptManifestScript {
    pub id: String,
    pub name: String,
    pub path: String,
    #[serde(default)]
    pub command_template: String,
    #[serde(default)]
    pub params: Vec<ScriptParamField>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SharedScriptPresetRestoreResult {
    pub preset_version: String,
    pub added_scripts: usize,
    pub skipped_scripts: usize,
    pub created_files: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MarkdownFileEntry {
    pub path: String,
    pub absolute_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProjectNotesPreview {
    pub path: String,
    pub notes_preview: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FsEntryKind {
    File,
    Dir,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum FsFailureReason {
    TooLarge,
    Binary,
    OutsideProject,
    SymlinkEscape,
    NotFound,
    NotADirectory,
    NotAFile,
    IoError,
    InvalidPath,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsEntry {
    pub name: String,
    pub relative_path: String,
    pub kind: FsEntryKind,
    #[serde(default)]
    pub size: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsListResponse {
    pub ok: bool,
    pub relative_path: String,
    pub entries: Vec<FsEntry>,
    #[serde(default)]
    pub reason: Option<FsFailureReason>,
    #[serde(default)]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsReadResponse {
    pub ok: bool,
    pub relative_path: String,
    #[serde(default)]
    pub content: Option<String>,
    pub size: u64,
    #[serde(rename = "maxSize")]
    pub max_size: u64,
    #[serde(default)]
    pub reason: Option<FsFailureReason>,
    #[serde(default)]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FsWriteResponse {
    pub ok: bool,
    pub relative_path: String,
    pub size: u64,
    #[serde(rename = "maxSize")]
    pub max_size: u64,
    #[serde(default)]
    pub reason: Option<FsFailureReason>,
    #[serde(default)]
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitDailyResult {
    pub path: String,
    #[serde(rename = "gitDaily")]
    pub git_daily: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeatmapCacheEntry {
    #[serde(rename = "dateString")]
    pub date_string: String,
    #[serde(rename = "commitCount")]
    pub commit_count: i64,
    #[serde(rename = "projectIds")]
    pub project_ids: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HeatmapCacheFile {
    pub version: i32,
    #[serde(rename = "lastUpdated")]
    pub last_updated: String,
    #[serde(rename = "dailyActivity")]
    pub daily_activity: HashMap<String, HeatmapCacheEntry>,
    #[serde(rename = "projectCount")]
    pub project_count: i64,
    #[serde(default, rename = "gitDailySignature")]
    pub git_daily_signature: String,
}

impl Default for HeatmapCacheFile {
    fn default() -> Self {
        Self {
            version: 1,
            last_updated: String::new(),
            daily_activity: HashMap::new(),
            project_count: 0,
            git_daily_signature: String::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BranchListItem {
    pub name: String,
    #[serde(rename = "isMain")]
    pub is_main: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitWorktreeAddResult {
    pub path: String,
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitWorktreeListItem {
    pub path: String,
    pub branch: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct InteractionLockPayload {
    pub locked: bool,
    #[serde(default)]
    pub reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorktreeInitVisualStatus {
    Creating,
    Ready,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WorktreeInitStep {
    Pending,
    Validating,
    CheckingBranch,
    CreatingWorktree,
    PreparingEnvironment,
    Syncing,
    Ready,
    Failed,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitStartRequest {
    pub project_id: String,
    pub project_path: String,
    pub branch: String,
    pub create_branch: bool,
    #[serde(default)]
    pub base_branch: Option<String>,
    #[serde(default)]
    pub target_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitStartResult {
    pub job_id: String,
    pub project_id: String,
    pub project_path: String,
    pub worktree_path: String,
    pub branch: String,
    #[serde(default)]
    pub base_branch: Option<String>,
    pub step: WorktreeInitStep,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitCreateBlockingResult {
    pub job_id: String,
    pub project_id: String,
    pub project_path: String,
    pub worktree_path: String,
    pub branch: String,
    #[serde(default)]
    pub base_branch: Option<String>,
    pub message: String,
    #[serde(default)]
    pub warning: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitProgressPayload {
    pub job_id: String,
    pub project_id: String,
    pub project_path: String,
    pub worktree_path: String,
    pub branch: String,
    #[serde(default)]
    pub base_branch: Option<String>,
    pub step: WorktreeInitStep,
    pub message: String,
    #[serde(default)]
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitCancelResult {
    pub job_id: String,
    pub cancelled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitRetryRequest {
    pub job_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitStatusQuery {
    #[serde(default)]
    pub project_id: Option<String>,
    #[serde(default)]
    pub project_path: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WorktreeInitJobStatus {
    pub job_id: String,
    pub project_id: String,
    pub project_path: String,
    pub worktree_path: String,
    pub branch: String,
    #[serde(default)]
    pub base_branch: Option<String>,
    pub create_branch: bool,
    pub step: WorktreeInitStep,
    pub message: String,
    #[serde(default)]
    pub error: Option<String>,
    pub updated_at: i64,
    pub is_running: bool,
    pub cancel_requested: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum GitFileStatus {
    Added,
    Modified,
    Deleted,
    Renamed,
    Copied,
    Untracked,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitChangedFile {
    pub path: String,
    #[serde(default)]
    pub old_path: Option<String>,
    pub status: GitFileStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitRepoStatus {
    pub branch: String,
    #[serde(default)]
    pub upstream: Option<String>,
    pub ahead: i32,
    pub behind: i32,
    pub staged: Vec<GitChangedFile>,
    pub unstaged: Vec<GitChangedFile>,
    pub untracked: Vec<GitChangedFile>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GitDiffContents {
    pub original: String,
    pub modified: String,
    #[serde(default)]
    pub original_truncated: bool,
    #[serde(default)]
    pub modified_truncated: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum CodexMonitorState {
    Offline,
    Idle,
    Working,
    Completed,
    Error,
    NeedsAttention,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexMonitorSession {
    pub id: String,
    pub cwd: String,
    pub cli_version: Option<String>,
    #[serde(default)]
    pub model: Option<String>,
    #[serde(default)]
    pub effort: Option<String>,
    pub started_at: i64,
    pub last_activity_at: i64,
    pub state: CodexMonitorState,
    pub is_running: bool,
    #[serde(default)]
    pub session_title: Option<String>,
    #[serde(default)]
    pub details: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "kebab-case")]
pub enum CodexAgentEventType {
    AgentStart,
    AgentStop,
    AgentActive,
    AgentIdle,
    TaskComplete,
    TaskError,
    NeedsAttention,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexAgentEvent {
    #[serde(rename = "type")]
    pub event_type: CodexAgentEventType,
    pub agent: String,
    pub timestamp: i64,
    #[serde(default)]
    pub details: Option<String>,
    #[serde(default)]
    pub session_id: Option<String>,
    #[serde(default)]
    pub session_title: Option<String>,
    #[serde(default)]
    pub working_directory: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CodexMonitorSnapshot {
    pub sessions: Vec<CodexMonitorSession>,
    pub is_codex_running: bool,
    pub updated_at: i64,
}
