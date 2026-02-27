use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{
    Mutex, OnceLock,
    atomic::{AtomicBool, Ordering},
    mpsc::{self, Receiver},
};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use chrono::{Datelike, Local, Utc};
use notify::{EventKind, RecommendedWatcher, RecursiveMode, Watcher};
use serde_json::Value;
use sysinfo::System;
use tauri::{AppHandle, Emitter, Manager};

use crate::models::{
    CodexAgentEvent, CodexAgentEventType, CodexMonitorSession, CodexMonitorSnapshot,
    CodexMonitorState,
};

const CODEX_SESSIONS_DIR: &str = ".codex/sessions";
const MAX_TAIL_LINES: usize = 2000;
const MAX_TAIL_BYTES: u64 = 256 * 1024;
const MAX_TAIL_BYTES_CAP: u64 = 8 * 1024 * 1024;
const MAX_JSON_LINE_BYTES: usize = 2 * 1024 * 1024;
const ACTIVE_WINDOW_MS: i64 = 10_000;
const COMPLETION_WINDOW_MS: i64 = 3_000;
const ERROR_WINDOW_MS: i64 = 90_000;
const NEEDS_ATTENTION_WINDOW_MS: i64 = 15 * 60_000;
const OFFLINE_GRACE_MS: i64 = 15_000;
const RECENT_FILE_WINDOW_MS: i64 = 5 * 60_000;
const WATCH_DEBOUNCE_MS: u64 = 350;
const PROCESS_POLL_INTERVAL_MS: u64 = 3_000;
const CANDIDATE_DAYS: usize = 2;

pub const CODEX_MONITOR_SNAPSHOT_EVENT: &str = "codex-monitor-snapshot";
pub const CODEX_MONITOR_AGENT_EVENT: &str = "codex-monitor-agent-event";

type SessionCache = HashMap<PathBuf, CachedSession>;

static CODEX_MONITOR_RUNTIME: OnceLock<Mutex<MonitorRuntime>> = OnceLock::new();
static CODEX_MONITOR_STARTED: AtomicBool = AtomicBool::new(false);

#[derive(Clone)]
struct CachedSession {
    session: CodexMonitorSession,
    modified: i64,
    size: u64,
}

#[derive(Default)]
struct MonitorRuntime {
    cache: SessionCache,
    previous_states: HashMap<String, CodexMonitorState>,
    previous_process_running: bool,
    has_bootstrapped: bool,
}

#[derive(Default)]
struct SessionTracker {
    last_activity_at: i64,
    last_user_ts: i64,
    last_assistant_ts: i64,
    last_abort_ts: i64,
    last_agent_activity_ts: i64,
    last_error_ts: i64,
    last_needs_attention_ts: i64,
    session_title: Option<String>,
    details: Option<String>,
    model: Option<String>,
    effort: Option<String>,
}

struct SessionMeta {
    id: String,
    cwd: String,
    cli_version: Option<String>,
    started_at: i64,
}

pub fn ensure_monitoring_started(app: &AppHandle) -> Result<(), String> {
    let base_dir = app
        .path()
        .home_dir()
        .map_err(|err| format!("无法获取用户目录: {err}"))?
        .join(CODEX_SESSIONS_DIR);

    if !base_dir.exists() {
        return Ok(());
    }

    if CODEX_MONITOR_STARTED
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return Ok(());
    }

    let watcher_app = app.clone();
    thread::spawn(move || {
        let (tx, rx) = mpsc::channel();
        let mut watcher = match RecommendedWatcher::new(tx, notify::Config::default()) {
            Ok(watcher) => watcher,
            Err(error) => {
                log::warn!("启动 Codex 监控失败: {}", error);
                return;
            }
        };

        if let Err(error) = watcher.watch(&base_dir, RecursiveMode::Recursive) {
            log::warn!("监听 Codex 会话目录失败: {}", error);
            return;
        }

        emit_monitoring(&watcher_app);
        watch_loop(rx, watcher_app);
    });

    let poll_app = app.clone();
    thread::spawn(move || {
        loop {
            thread::sleep(Duration::from_millis(PROCESS_POLL_INTERVAL_MS));
            emit_monitoring(&poll_app);
        }
    });

    Ok(())
}

pub fn get_snapshot(app: &AppHandle) -> Result<CodexMonitorSnapshot, String> {
    refresh_monitoring(app, false).map(|(snapshot, _)| snapshot)
}

fn watch_loop(rx: Receiver<Result<notify::Event, notify::Error>>, app: AppHandle) {
    let mut pending = false;
    let mut last_emit = std::time::Instant::now()
        .checked_sub(Duration::from_millis(WATCH_DEBOUNCE_MS))
        .unwrap_or_else(std::time::Instant::now);

    loop {
        match rx.recv_timeout(Duration::from_millis(WATCH_DEBOUNCE_MS)) {
            Ok(Ok(event)) => {
                if should_refresh_for_event(&event) {
                    pending = true;
                    if last_emit.elapsed() >= Duration::from_millis(WATCH_DEBOUNCE_MS) {
                        pending = false;
                        last_emit = std::time::Instant::now();
                        emit_monitoring(&app);
                    }
                }
            }
            Ok(Err(error)) => {
                log::warn!("Codex 监控监听错误: {}", error);
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                if pending {
                    pending = false;
                    last_emit = std::time::Instant::now();
                    emit_monitoring(&app);
                }
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => break,
        }
    }
}

fn should_refresh_for_event(event: &notify::Event) -> bool {
    let matches_kind = matches!(
        event.kind,
        EventKind::Create(_) | EventKind::Modify(_) | EventKind::Remove(_)
    );
    if !matches_kind {
        return false;
    }
    event.paths.iter().any(|path| is_rollout_file(path))
}

fn emit_monitoring(app: &AppHandle) {
    match refresh_monitoring(app, true) {
        Ok((snapshot, events)) => {
            if let Err(error) = app.emit(CODEX_MONITOR_SNAPSHOT_EVENT, snapshot) {
                log::warn!("推送 Codex 监控快照失败: {}", error);
            }
            for event in events {
                if let Err(error) = app.emit(CODEX_MONITOR_AGENT_EVENT, event) {
                    log::warn!("推送 Codex 监控事件失败: {}", error);
                }
            }
        }
        Err(error) => {
            log::warn!("刷新 Codex 监控失败: {}", error);
        }
    }
}

fn refresh_monitoring(
    app: &AppHandle,
    emit_events: bool,
) -> Result<(CodexMonitorSnapshot, Vec<CodexAgentEvent>), String> {
    let base_dir = app
        .path()
        .home_dir()
        .map_err(|err| format!("无法获取用户目录: {err}"))?
        .join(CODEX_SESSIONS_DIR);

    let now_ms = Utc::now().timestamp_millis();
    let mut seen = HashSet::new();
    let mut files = Vec::new();
    if base_dir.exists() {
        files = collect_rollout_files(&base_dir)?;
    }

    let process_running = any_codex_process_running();
    let recent_threshold = now_ms - RECENT_FILE_WINDOW_MS;

    let runtime = CODEX_MONITOR_RUNTIME.get_or_init(|| Mutex::new(MonitorRuntime::default()));
    let mut runtime = runtime
        .lock()
        .map_err(|_| "Codex 监控状态锁异常".to_string())?;

    for path in files {
        seen.insert(path.clone());
        let metadata = match fs::metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) => {
                log::warn!(
                    "读取 Codex 会话文件失败: path={} err={}",
                    path.display(),
                    error
                );
                continue;
            }
        };

        let modified = metadata
            .modified()
            .ok()
            .and_then(system_time_to_millis)
            .unwrap_or(0);
        let size = metadata.len();
        let is_cached = runtime.cache.contains_key(&path);
        let is_old = modified > 0 && modified < recent_threshold;
        if is_old && !is_cached {
            continue;
        }

        let should_refresh = match runtime.cache.get(&path) {
            Some(cached) => {
                cached.modified != modified
                    || cached.size != size
                    || requires_time_based_refresh(&cached.session.state)
            }
            None => true,
        };

        if should_refresh {
            match parse_session_file(&path, now_ms, process_running) {
                Ok(session) => {
                    runtime.cache.insert(
                        path,
                        CachedSession {
                            session,
                            modified,
                            size,
                        },
                    );
                }
                Err(error) => {
                    log::warn!("解析 Codex 会话失败: path={} err={}", path.display(), error);
                }
            }
        }
    }

    runtime.cache.retain(|path, _| seen.contains(path));

    let mut sessions: Vec<CodexMonitorSession> = runtime
        .cache
        .iter_mut()
        .map(|(path, cached)| {
            if matches!(cached.session.state, CodexMonitorState::Working) {
                if let Some(false) = codex_rollout_file_open_by_codex(path) {
                    cached.session.state = if process_running {
                        CodexMonitorState::Idle
                    } else {
                        CodexMonitorState::Offline
                    };
                    cached.session.is_running = false;
                }
            }
            cached.session.clone()
        })
        .collect();

    sessions.sort_by(|left, right| right.last_activity_at.cmp(&left.last_activity_at));

    let snapshot = CodexMonitorSnapshot {
        sessions,
        is_codex_running: process_running,
        updated_at: now_ms,
    };

    let events = build_monitor_events(&mut runtime, &snapshot, now_ms, emit_events);

    Ok((snapshot, events))
}

fn build_monitor_events(
    runtime: &mut MonitorRuntime,
    snapshot: &CodexMonitorSnapshot,
    timestamp: i64,
    emit_events: bool,
) -> Vec<CodexAgentEvent> {
    let mut events = Vec::new();

    if runtime.has_bootstrapped && emit_events {
        if runtime.previous_process_running != snapshot.is_codex_running {
            events.push(CodexAgentEvent {
                event_type: if snapshot.is_codex_running {
                    CodexAgentEventType::AgentStart
                } else {
                    CodexAgentEventType::AgentStop
                },
                agent: "codex".to_string(),
                timestamp,
                details: None,
                session_id: None,
                session_title: None,
                working_directory: None,
            });
        }
    }

    let mut next_states = HashMap::new();
    for session in &snapshot.sessions {
        next_states.insert(session.id.clone(), session.state.clone());

        if !runtime.has_bootstrapped || !emit_events {
            continue;
        }

        let previous = runtime.previous_states.get(&session.id);
        if let Some(event_type) = transition_to_event_type(previous, &session.state) {
            events.push(build_session_event(event_type, session, timestamp));
        }
    }

    if runtime.has_bootstrapped && emit_events {
        for (session_id, previous_state) in &runtime.previous_states {
            if next_states.contains_key(session_id) {
                continue;
            }
            if matches!(
                previous_state,
                CodexMonitorState::Working
                    | CodexMonitorState::NeedsAttention
                    | CodexMonitorState::Error
            ) {
                events.push(CodexAgentEvent {
                    event_type: CodexAgentEventType::AgentIdle,
                    agent: "codex".to_string(),
                    timestamp,
                    details: Some("会话已结束".to_string()),
                    session_id: Some(session_id.clone()),
                    session_title: None,
                    working_directory: None,
                });
            }
        }
    }

    runtime.previous_states = next_states;
    runtime.previous_process_running = snapshot.is_codex_running;
    runtime.has_bootstrapped = true;

    events
}

fn transition_to_event_type(
    previous: Option<&CodexMonitorState>,
    current: &CodexMonitorState,
) -> Option<CodexAgentEventType> {
    match current {
        CodexMonitorState::Error => {
            if matches!(previous, Some(CodexMonitorState::Error)) {
                None
            } else {
                Some(CodexAgentEventType::TaskError)
            }
        }
        CodexMonitorState::NeedsAttention => {
            if matches!(previous, Some(CodexMonitorState::NeedsAttention)) {
                None
            } else {
                Some(CodexAgentEventType::NeedsAttention)
            }
        }
        CodexMonitorState::Working => {
            if matches!(previous, Some(CodexMonitorState::Working)) {
                None
            } else {
                Some(CodexAgentEventType::AgentActive)
            }
        }
        CodexMonitorState::Completed => {
            if matches!(previous, Some(CodexMonitorState::Completed)) {
                None
            } else {
                Some(CodexAgentEventType::TaskComplete)
            }
        }
        CodexMonitorState::Idle | CodexMonitorState::Offline => {
            if matches!(
                previous,
                Some(CodexMonitorState::Working)
                    | Some(CodexMonitorState::NeedsAttention)
                    | Some(CodexMonitorState::Error)
                    | Some(CodexMonitorState::Completed)
            ) {
                Some(CodexAgentEventType::AgentIdle)
            } else {
                None
            }
        }
    }
}

fn build_session_event(
    event_type: CodexAgentEventType,
    session: &CodexMonitorSession,
    timestamp: i64,
) -> CodexAgentEvent {
    CodexAgentEvent {
        event_type,
        agent: "codex".to_string(),
        timestamp,
        details: session.details.clone(),
        session_id: Some(session.id.clone()),
        session_title: session.session_title.clone(),
        working_directory: if session.cwd.is_empty() {
            None
        } else {
            Some(session.cwd.clone())
        },
    }
}

fn requires_time_based_refresh(state: &CodexMonitorState) -> bool {
    matches!(
        state,
        CodexMonitorState::Working
            | CodexMonitorState::Completed
            | CodexMonitorState::NeedsAttention
            | CodexMonitorState::Error
    )
}

fn collect_rollout_files(base_dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files = Vec::new();
    let candidate_dirs = collect_candidate_dirs(base_dir);
    if candidate_dirs.is_empty() {
        collect_rollout_files_recursive(base_dir, &mut files)?;
    } else {
        for dir in candidate_dirs {
            collect_rollout_files_shallow(&dir, &mut files)?;
        }
    }
    Ok(files)
}

fn collect_candidate_dirs(base_dir: &Path) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    let mut date = Local::now().date_naive();
    for _ in 0..CANDIDATE_DAYS {
        let dir = build_date_dir(base_dir, date);
        if dir.exists() && dir.is_dir() {
            dirs.push(dir);
        }
        date = date.pred_opt().unwrap_or(date);
    }
    dirs
}

fn build_date_dir(base_dir: &Path, date: chrono::NaiveDate) -> PathBuf {
    base_dir
        .join(format!("{:04}", date.year()))
        .join(format!("{:02}", date.month()))
        .join(format!("{:02}", date.day()))
}

fn collect_rollout_files_shallow(dir: &Path, output: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = fs::read_dir(dir).map_err(|err| format!("读取目录失败: {err}"))?;
    for entry in entries {
        let entry = entry.map_err(|err| format!("读取目录项失败: {err}"))?;
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if is_rollout_file(&path) {
            output.push(path);
        }
    }
    Ok(())
}

fn collect_rollout_files_recursive(dir: &Path, output: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries = fs::read_dir(dir).map_err(|err| format!("读取目录失败: {err}"))?;
    for entry in entries {
        let entry = entry.map_err(|err| format!("读取目录项失败: {err}"))?;
        let path = entry.path();
        if path.is_dir() {
            collect_rollout_files_recursive(&path, output)?;
            continue;
        }
        if !path.is_file() {
            continue;
        }
        if is_rollout_file(&path) {
            output.push(path);
        }
    }
    Ok(())
}

fn is_rollout_file(path: &Path) -> bool {
    let Some(file_name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };
    file_name.starts_with("rollout-") && file_name.ends_with(".jsonl")
}

fn parse_session_file(
    path: &Path,
    now_ms: i64,
    is_codex_running: bool,
) -> Result<CodexMonitorSession, String> {
    let meta = read_session_meta(path)?;
    let tail_lines =
        read_tail_lines_resilient(path, MAX_TAIL_LINES, MAX_TAIL_BYTES, MAX_TAIL_BYTES_CAP)?;

    let mut tracker = SessionTracker {
        last_activity_at: meta.started_at,
        ..SessionTracker::default()
    };

    for line in tail_lines {
        if line.trim().is_empty() || line.len() > MAX_JSON_LINE_BYTES {
            continue;
        }
        let value: Value = match serde_json::from_str(&line) {
            Ok(parsed) => parsed,
            Err(_) => continue,
        };

        process_entry(&value, &mut tracker);
    }

    if tracker.last_activity_at <= 0 {
        if let Some(modified) = file_modified_millis(path) {
            tracker.last_activity_at = modified;
        }
    }

    let pending_turn = tracker.last_user_ts > 0
        && tracker.last_user_ts > tracker.last_assistant_ts
        && tracker.last_user_ts > tracker.last_abort_ts;
    let has_agent_activity_for_pending_turn = tracker.last_agent_activity_ts
        >= tracker.last_user_ts
        && tracker.last_agent_activity_ts > 0;
    let is_actively_streaming = has_agent_activity_for_pending_turn
        && now_ms.saturating_sub(tracker.last_agent_activity_ts) <= ACTIVE_WINDOW_MS;
    let has_recent_completion = tracker.last_assistant_ts > 0
        && !pending_turn
        && now_ms.saturating_sub(tracker.last_assistant_ts) <= COMPLETION_WINDOW_MS;
    let has_recent_error = tracker.last_error_ts > 0
        && now_ms.saturating_sub(tracker.last_error_ts) <= ERROR_WINDOW_MS;
    let has_recent_attention = tracker.last_needs_attention_ts > 0
        && now_ms.saturating_sub(tracker.last_needs_attention_ts) <= NEEDS_ATTENTION_WINDOW_MS;

    let mut state = if has_recent_error {
        CodexMonitorState::Error
    } else if has_recent_attention {
        CodexMonitorState::NeedsAttention
    } else if pending_turn && is_actively_streaming {
        CodexMonitorState::Working
    } else if has_recent_completion {
        CodexMonitorState::Completed
    } else {
        CodexMonitorState::Idle
    };

    if !is_codex_running
        && now_ms.saturating_sub(tracker.last_activity_at) > OFFLINE_GRACE_MS
        && !matches!(state, CodexMonitorState::Completed)
    {
        state = CodexMonitorState::Offline;
    }

    // 统一工作态文案，避免出现“思考中/工具调用中/回复生成中”等多种表达。
    if matches!(state, CodexMonitorState::Working) {
        tracker.details = Some("运行中".to_string());
    }

    let is_running = matches!(
        state,
        CodexMonitorState::Working | CodexMonitorState::NeedsAttention | CodexMonitorState::Error
    );

    Ok(CodexMonitorSession {
        id: meta.id,
        cwd: meta.cwd,
        cli_version: meta.cli_version,
        model: tracker.model,
        effort: tracker.effort,
        started_at: meta.started_at,
        last_activity_at: tracker.last_activity_at,
        state,
        is_running,
        session_title: tracker.session_title,
        details: tracker.details,
    })
}

fn process_entry(value: &Value, tracker: &mut SessionTracker) {
    let payload = value.get("payload");
    let timestamp = value
        .get("timestamp")
        .and_then(parse_timestamp)
        .or_else(|| {
            payload
                .and_then(|item| item.get("timestamp"))
                .and_then(parse_timestamp)
        })
        .unwrap_or(0);
    if timestamp > tracker.last_activity_at {
        tracker.last_activity_at = timestamp;
    }

    let typ = value
        .get("type")
        .and_then(|item| item.as_str())
        .unwrap_or("");
    match typ {
        "event_msg" => process_event_msg(payload, timestamp, tracker),
        "response_item" => process_response_item(payload, timestamp, tracker),
        "turn_context" => process_turn_context(payload, tracker),
        _ => {
            if entry_indicates_error(value) {
                tracker.last_error_ts = tracker.last_error_ts.max(timestamp);
                if tracker.details.is_none() {
                    tracker.details = Some("任务执行出现错误".to_string());
                }
            }
        }
    }
}

fn process_turn_context(payload: Option<&Value>, tracker: &mut SessionTracker) {
    let Some(payload) = payload else {
        return;
    };

    if let Some(model) = payload
        .get("model")
        .and_then(|item| item.as_str())
        .map(|text| text.trim())
        .filter(|text| !text.is_empty())
    {
        tracker.model = Some(model.to_string());
    }

    if let Some(effort) = payload
        .get("effort")
        .and_then(|item| item.as_str())
        .map(|text| text.trim())
        .filter(|text| !text.is_empty())
    {
        tracker.effort = Some(effort.to_string());
    }
}

fn process_event_msg(payload: Option<&Value>, timestamp: i64, tracker: &mut SessionTracker) {
    let event_type = payload
        .and_then(|item| item.get("type"))
        .and_then(|item| item.as_str())
        .unwrap_or("");

    match event_type {
        "user_message" => {
            tracker.last_user_ts = tracker.last_user_ts.max(timestamp);
            tracker.details = Some("Processing user message".to_string());
            if tracker.session_title.is_none() {
                tracker.session_title = payload
                    .and_then(extract_user_message_text)
                    .map(|text| truncate_text(&text, 42));
            }
        }
        "agent_message" => {
            tracker.last_assistant_ts = tracker.last_assistant_ts.max(timestamp);
            tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
            tracker.details = payload
                .and_then(extract_message_preview)
                .map(|text| truncate_text(&text, 80))
                .or_else(|| Some("生成回复中".to_string()));
        }
        "agent_reasoning" | "token_count" => {
            tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
            tracker.details = Some("运行中".to_string());
        }
        "turn_aborted" => {
            tracker.last_abort_ts = tracker.last_abort_ts.max(timestamp);
            tracker.details = Some("任务已中止".to_string());
        }
        "turn_error" | "error" => {
            tracker.last_error_ts = tracker.last_error_ts.max(timestamp);
            tracker.details = payload
                .and_then(extract_message_preview)
                .map(|text| format!("错误: {}", truncate_text(&text, 80)))
                .or_else(|| Some("任务执行出现错误".to_string()));
        }
        "needs_attention" | "awaiting_user_input" => {
            tracker.last_needs_attention_ts = tracker.last_needs_attention_ts.max(timestamp);
            tracker.details = Some("等待用户处理".to_string());
        }
        _ => {
            if let Some(payload_value) = payload {
                if entry_indicates_needs_attention(payload_value) {
                    tracker.last_needs_attention_ts =
                        tracker.last_needs_attention_ts.max(timestamp);
                    tracker.details = Some("等待用户处理".to_string());
                }
                if entry_indicates_error(payload_value) {
                    tracker.last_error_ts = tracker.last_error_ts.max(timestamp);
                    tracker.details = Some("任务执行出现错误".to_string());
                }
            }
        }
    }
}

fn process_response_item(payload: Option<&Value>, timestamp: i64, tracker: &mut SessionTracker) {
    let item_type = payload
        .and_then(|item| item.get("type"))
        .and_then(|item| item.as_str())
        .unwrap_or("");

    match item_type {
        "function_call" => {
            tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
            tracker.details = payload
                .and_then(build_function_call_details)
                .or_else(|| Some("工具调用中".to_string()));
            if let Some(payload_value) = payload {
                let name = payload_value
                    .get("name")
                    .and_then(|item| item.as_str())
                    .unwrap_or("")
                    .to_ascii_lowercase();
                if name == "request_user_input"
                    || name.contains("approval")
                    || name.contains("confirm")
                {
                    tracker.last_needs_attention_ts =
                        tracker.last_needs_attention_ts.max(timestamp);
                }
            }
        }
        "function_call_output" => {
            tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
            if payload.map(entry_indicates_error).unwrap_or(false) {
                tracker.last_error_ts = tracker.last_error_ts.max(timestamp);
                tracker.details = Some("工具调用失败".to_string());
            }
        }
        "message" => {
            let role = payload
                .and_then(|item| item.get("role"))
                .and_then(|item| item.as_str())
                .unwrap_or("");
            match role {
                "user" => {
                    tracker.last_user_ts = tracker.last_user_ts.max(timestamp);
                    if tracker.session_title.is_none() {
                        tracker.session_title = payload
                            .and_then(extract_user_message_text)
                            .map(|text| truncate_text(&text, 42));
                    }
                }
                "assistant" => {
                    tracker.last_assistant_ts = tracker.last_assistant_ts.max(timestamp);
                    tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
                    tracker.details = payload
                        .and_then(extract_message_preview)
                        .map(|text| truncate_text(&text, 80))
                        .or_else(|| Some("回复已生成".to_string()));
                }
                _ => {}
            }
        }
        "reasoning" => {
            tracker.last_agent_activity_ts = tracker.last_agent_activity_ts.max(timestamp);
            tracker.details = Some("运行中".to_string());
        }
        _ => {
            if let Some(payload_value) = payload {
                if entry_indicates_needs_attention(payload_value) {
                    tracker.last_needs_attention_ts =
                        tracker.last_needs_attention_ts.max(timestamp);
                    tracker.details = Some("等待用户处理".to_string());
                }
                if entry_indicates_error(payload_value) {
                    tracker.last_error_ts = tracker.last_error_ts.max(timestamp);
                    tracker.details = Some("任务执行出现错误".to_string());
                }
            }
        }
    }
}

fn build_function_call_details(payload: &Value) -> Option<String> {
    let function_name = payload.get("name").and_then(|item| item.as_str())?;
    let arguments = parse_function_arguments(payload);

    if function_name == "shell_command" {
        if let Some(command) = arguments
            .as_ref()
            .and_then(|args| args.get("command"))
            .and_then(|item| item.as_str())
        {
            return Some(format!("shell: {}", truncate_text(command, 80)));
        }
    }

    if function_name == "apply_patch" {
        return Some("Applying patch".to_string());
    }

    let maybe_path = arguments
        .as_ref()
        .and_then(|args| args.get("path").and_then(|item| item.as_str()))
        .or_else(|| {
            arguments
                .as_ref()
                .and_then(|args| args.get("file").and_then(|item| item.as_str()))
        });
    if let Some(path) = maybe_path {
        let file_name = Path::new(path)
            .file_name()
            .and_then(|item| item.to_str())
            .unwrap_or(path);
        return Some(format!(
            "{}: {}",
            function_name,
            truncate_text(file_name, 80)
        ));
    }

    Some(function_name.to_string())
}

fn parse_function_arguments(payload: &Value) -> Option<Value> {
    let raw = payload.get("arguments")?;
    if raw.is_object() {
        return Some(raw.clone());
    }
    if let Some(text) = raw.as_str() {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            return None;
        }
        return serde_json::from_str(trimmed).ok();
    }
    None
}

fn extract_user_message_text(payload: &Value) -> Option<String> {
    payload
        .get("message")
        .and_then(|item| item.as_str())
        .map(|text| text.trim().to_string())
        .filter(|text| !text.is_empty())
        .or_else(|| {
            payload
                .get("text")
                .and_then(|item| item.as_str())
                .map(|text| text.trim().to_string())
                .filter(|text| !text.is_empty())
        })
        .or_else(|| extract_message_preview(payload))
}

fn extract_message_preview(payload: &Value) -> Option<String> {
    payload
        .get("message")
        .and_then(value_to_preview_text)
        .or_else(|| payload.get("content").and_then(value_to_preview_text))
        .or_else(|| payload.get("output").and_then(value_to_preview_text))
}

fn value_to_preview_text(value: &Value) -> Option<String> {
    if let Some(text) = value.as_str() {
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            return Some(trimmed.to_string());
        }
        return None;
    }

    if let Some(array) = value.as_array() {
        for item in array {
            if let Some(text) = item.get("text").and_then(|field| field.as_str()) {
                let trimmed = text.trim();
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
            if let Some(text) = item.get("content").and_then(|field| field.as_str()) {
                let trimmed = text.trim();
                if !trimmed.is_empty() {
                    return Some(trimmed.to_string());
                }
            }
        }
    }

    if let Some(object) = value.as_object() {
        for key in ["text", "content", "message", "output"] {
            if let Some(field) = object.get(key) {
                if let Some(text) = value_to_preview_text(field) {
                    return Some(text);
                }
            }
        }
    }

    None
}

fn entry_indicates_error(value: &Value) -> bool {
    if value
        .get("is_error")
        .and_then(|item| item.as_bool())
        .unwrap_or(false)
    {
        return true;
    }

    let text = value.to_string().to_ascii_lowercase();
    text.contains("\"error\"")
        || text.contains("failed")
        || text.contains("exception")
        || text.contains("traceback")
}

fn entry_indicates_needs_attention(value: &Value) -> bool {
    let text = value.to_string().to_ascii_lowercase();
    text.contains("request_user_input")
        || text.contains("needs_attention")
        || text.contains("awaiting_user_input")
        || text.contains("requires_confirmation")
        || text.contains("approval")
}

fn truncate_text(input: &str, max_chars: usize) -> String {
    if input.chars().count() <= max_chars {
        return input.to_string();
    }
    let truncated: String = input.chars().take(max_chars).collect();
    format!("{}…", truncated)
}

fn read_session_meta(path: &Path) -> Result<SessionMeta, String> {
    let file = File::open(path).map_err(|err| format!("读取会话文件失败: {err}"))?;
    let mut reader = BufReader::new(file);
    let mut line = String::new();
    reader
        .read_line(&mut line)
        .map_err(|err| format!("读取会话首行失败: {err}"))?;
    if line.trim().is_empty() {
        return Err("会话文件为空".to_string());
    }
    let value: Value =
        serde_json::from_str(&line).map_err(|err| format!("解析会话首行失败: {err}"))?;
    if value.get("type").and_then(|item| item.as_str()) != Some("session_meta") {
        return Err("会话首行不是 session_meta".to_string());
    }
    let payload = value
        .get("payload")
        .ok_or_else(|| "session_meta 缺少 payload".to_string())?;
    let id = payload
        .get("id")
        .and_then(|item| item.as_str())
        .filter(|text| !text.is_empty())
        .map(|text| text.to_string())
        .or_else(|| fallback_session_id(path))
        .ok_or_else(|| "session_meta 缺少 id".to_string())?;
    let cwd = payload
        .get("cwd")
        .and_then(|item| item.as_str())
        .unwrap_or("")
        .to_string();
    let cli_version = payload
        .get("cli_version")
        .and_then(|item| item.as_str())
        .map(|text| text.to_string());
    let started_at = payload
        .get("timestamp")
        .and_then(parse_timestamp)
        .or_else(|| value.get("timestamp").and_then(parse_timestamp))
        .or_else(|| file_modified_millis(path))
        .unwrap_or(0);

    Ok(SessionMeta {
        id,
        cwd,
        cli_version,
        started_at,
    })
}

fn read_tail_lines(path: &Path, max_lines: usize, max_bytes: u64) -> Result<Vec<String>, String> {
    let mut file = File::open(path).map_err(|err| format!("读取会话文件失败: {err}"))?;
    let size = file
        .metadata()
        .map_err(|err| format!("读取文件元信息失败: {err}"))?
        .len();
    let start = if size > max_bytes {
        size - max_bytes
    } else {
        0
    };
    let read_start = if start > 0 {
        start.saturating_sub(1)
    } else {
        0
    };

    file.seek(SeekFrom::Start(read_start))
        .map_err(|err| format!("定位会话文件失败: {err}"))?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)
        .map_err(|err| format!("读取会话文件失败: {err}"))?;

    let text = String::from_utf8_lossy(&buffer);
    let mut lines: Vec<&str> = text.split("\n").collect();
    if read_start > 0 && !lines.is_empty() {
        lines.remove(0);
    }

    let mut trimmed: Vec<String> = lines
        .into_iter()
        .filter(|line| !line.trim().is_empty())
        .map(|line| line.to_string())
        .collect();

    if trimmed.len() > max_lines {
        trimmed = trimmed.split_off(trimmed.len() - max_lines);
    }

    Ok(trimmed)
}

fn read_tail_lines_resilient(
    path: &Path,
    max_lines: usize,
    initial_bytes: u64,
    max_bytes_cap: u64,
) -> Result<Vec<String>, String> {
    let size = fs::metadata(path)
        .map_err(|err| format!("读取文件元信息失败: {err}"))?
        .len();
    if size == 0 {
        return Ok(Vec::new());
    }

    let mut bytes = initial_bytes.min(size).max(1024);
    loop {
        let lines = read_tail_lines(path, max_lines, bytes)?;
        if !lines.is_empty() || bytes >= size || bytes >= max_bytes_cap {
            return Ok(lines);
        }
        bytes = bytes.saturating_mul(2).min(size).min(max_bytes_cap);
    }
}

fn parse_timestamp(value: &Value) -> Option<i64> {
    value
        .as_str()
        .and_then(|text| chrono::DateTime::parse_from_rfc3339(text).ok())
        .map(|dt| dt.timestamp_millis())
}

fn fallback_session_id(path: &Path) -> Option<String> {
    path.file_stem()
        .and_then(|value| value.to_str())
        .map(|text| text.to_string())
}

fn file_modified_millis(path: &Path) -> Option<i64> {
    let modified = fs::metadata(path).ok()?.modified().ok()?;
    system_time_to_millis(modified)
}

fn system_time_to_millis(time: SystemTime) -> Option<i64> {
    time.duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_millis() as i64)
}

fn codex_rollout_file_open_by_codex(path: &Path) -> Option<bool> {
    if !(cfg!(target_os = "macos") || cfg!(target_os = "linux")) {
        return None;
    }

    let args = ["-n", "-P", "-F", "pc", "--"];
    let output = run_lsof_output_with_fallback(&args, path)?;
    let stdout = String::from_utf8_lossy(&output.stdout);
    if stdout.trim().is_empty() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        if !stderr.trim().is_empty() {
            let stderr_lower = stderr.to_ascii_lowercase();
            if stderr_lower.contains("no such file")
                || stderr_lower.contains("no such file or directory")
                || stderr_lower.contains("status error")
            {
                return Some(false);
            }
            return None;
        }
        return Some(false);
    }

    Some(lsof_stdout_indicates_codex_open(&stdout))
}

fn lsof_stdout_indicates_codex_open(stdout: &str) -> bool {
    stdout.lines().any(|line| {
        let Some(command) = line.strip_prefix('c') else {
            return false;
        };
        let name = command.trim().to_ascii_lowercase();
        name == "codex" || name == "codex.exe"
    })
}

fn run_lsof_output_with_fallback(args: &[&str], path: &Path) -> Option<std::process::Output> {
    match Command::new("lsof").args(args).arg(path).output() {
        Ok(output) => Some(output),
        Err(error) => {
            if error.kind() != std::io::ErrorKind::NotFound {
                log::debug!("运行 lsof 失败: {}", error);
                return None;
            }

            for candidate in ["/usr/sbin/lsof", "/usr/bin/lsof"] {
                match Command::new(candidate).args(args).arg(path).output() {
                    Ok(output) => return Some(output),
                    Err(_) => continue,
                }
            }
            None
        }
    }
}

fn any_codex_process_running() -> bool {
    let mut system = System::new();
    system.refresh_processes();
    system.processes().values().any(|process| {
        let name = process.name().to_ascii_lowercase();
        name == "codex" || name == "codex.exe"
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    fn write_session(lines: &[&str]) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("devhaven-codex-monitor-{}", Uuid::new_v4()));
        fs::create_dir_all(&dir).expect("create temp dir");
        let path = dir.join("rollout-test.jsonl");
        fs::write(&path, lines.join("\n")).expect("write temp session");
        path
    }

    #[test]
    fn parse_session_file_marks_working_when_pending_turn_is_streaming() {
        let path = write_session(&[
            r#"{"timestamp":"2026-01-28T05:07:13.570Z","type":"session_meta","payload":{"id":"abc","timestamp":"2026-01-28T05:07:13.545Z","cwd":"/tmp/project","cli_version":"0.92.0"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:14.000Z","type":"event_msg","payload":{"type":"agent_reasoning"}}"#,
        ]);

        let now = chrono::DateTime::parse_from_rfc3339("2036-01-28T05:08:15.000Z")
            .expect("parse now")
            .timestamp_millis();
        let session = parse_session_file(&path, now, true).expect("parse session");
        assert_eq!(session.state, CodexMonitorState::Working);
        assert!(session.is_running);
    }

    #[test]
    fn parse_session_file_marks_completed_after_assistant_reply() {
        let path = write_session(&[
            r#"{"timestamp":"2026-01-28T05:07:13.570Z","type":"session_meta","payload":{"id":"abc","timestamp":"2026-01-28T05:07:13.545Z","cwd":"/tmp/project","cli_version":"0.92.0"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:13.000Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:14.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":"done"}}"#,
        ]);

        let now = chrono::DateTime::parse_from_rfc3339("2036-01-28T05:08:15.500Z")
            .expect("parse now")
            .timestamp_millis();
        let session = parse_session_file(&path, now, true).expect("parse session");
        assert_eq!(session.state, CodexMonitorState::Completed);
        assert!(!session.is_running);
    }

    #[test]
    fn parse_session_file_marks_needs_attention_for_request_user_input() {
        let path = write_session(&[
            r#"{"timestamp":"2026-01-28T05:07:13.570Z","type":"session_meta","payload":{"id":"abc","timestamp":"2026-01-28T05:07:13.545Z","cwd":"/tmp/project","cli_version":"0.92.0"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:13.000Z","type":"response_item","payload":{"type":"function_call","name":"request_user_input","arguments":"{}"}}"#,
        ]);

        let now = chrono::DateTime::parse_from_rfc3339("2036-01-28T05:08:20.000Z")
            .expect("parse now")
            .timestamp_millis();
        let session = parse_session_file(&path, now, true).expect("parse session");
        assert_eq!(session.state, CodexMonitorState::NeedsAttention);
    }

    #[test]
    fn parse_session_file_marks_error_when_function_call_output_failed() {
        let path = write_session(&[
            r#"{"timestamp":"2026-01-28T05:07:13.570Z","type":"session_meta","payload":{"id":"abc","timestamp":"2026-01-28T05:07:13.545Z","cwd":"/tmp/project","cli_version":"0.92.0"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:13.000Z","type":"response_item","payload":{"type":"function_call_output","is_error":true,"output":"failed"}}"#,
        ]);

        let now = chrono::DateTime::parse_from_rfc3339("2036-01-28T05:08:20.000Z")
            .expect("parse now")
            .timestamp_millis();
        let session = parse_session_file(&path, now, true).expect("parse session");
        assert_eq!(session.state, CodexMonitorState::Error);
    }

    #[test]
    fn parse_session_file_extracts_model_and_effort_from_turn_context() {
        let path = write_session(&[
            r#"{"timestamp":"2026-01-28T05:07:13.570Z","type":"session_meta","payload":{"id":"abc","timestamp":"2026-01-28T05:07:13.545Z","cwd":"/tmp/project","cli_version":"0.92.0"}}"#,
            r#"{"timestamp":"2036-01-28T05:08:13.000Z","type":"turn_context","payload":{"model":"gpt-5-codex","effort":"xhigh"}}"#,
        ]);

        let now = chrono::DateTime::parse_from_rfc3339("2036-01-28T05:08:20.000Z")
            .expect("parse now")
            .timestamp_millis();
        let session = parse_session_file(&path, now, true).expect("parse session");
        assert_eq!(session.model.as_deref(), Some("gpt-5-codex"));
        assert_eq!(session.effort.as_deref(), Some("xhigh"));
    }

    #[test]
    fn transition_to_event_type_maps_states() {
        assert_eq!(
            transition_to_event_type(Some(&CodexMonitorState::Idle), &CodexMonitorState::Working),
            Some(CodexAgentEventType::AgentActive)
        );
        assert_eq!(
            transition_to_event_type(
                Some(&CodexMonitorState::Working),
                &CodexMonitorState::Completed
            ),
            Some(CodexAgentEventType::TaskComplete)
        );
        assert_eq!(
            transition_to_event_type(
                Some(&CodexMonitorState::NeedsAttention),
                &CodexMonitorState::Idle
            ),
            Some(CodexAgentEventType::AgentIdle)
        );
    }
}
