use std::collections::{HashMap, HashSet};
use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

use portable_pty::{Child, CommandBuilder, MasterPty, PtySize, native_pty_system};
use serde::Serialize;
use serde_json::Value;
use sysinfo::{Pid, System};
use tauri::{AppHandle, Emitter, Manager, State};
use uuid::Uuid;

use crate::models::TerminalCodexPaneOverlay;

const TERMINAL_OUTPUT_EVENT: &str = "terminal-output";
const TERMINAL_EXIT_EVENT: &str = "terminal-exit";
const MAX_ROLLOUT_TAIL_LINES: usize = 800;
const MAX_ROLLOUT_TAIL_BYTES: u64 = 192 * 1024;
const MAX_ROLLOUT_TAIL_BYTES_CAP: u64 = 2 * 1024 * 1024;
const MAX_ROLLOUT_JSON_LINE_BYTES: usize = 2 * 1024 * 1024;

/// 将 PTY 的字节流按 UTF-8 逐步解码。
///
/// 关键点：PTY 读到的字节可能会把一个 UTF-8 字符拆到两次 read() 里。
/// 如果每次 read() 都直接 `String::from_utf8_lossy(&chunk)`，就会把拆开的字符解成 `�`，
/// 在中文/emoji 等多字节字符场景看起来像“乱码”。
fn drain_utf8_stream(pending: &mut Vec<u8>) -> String {
    if pending.is_empty() {
        return String::new();
    }

    let mut out = String::new();
    loop {
        match std::str::from_utf8(pending) {
            Ok(text) => {
                out.push_str(text);
                pending.clear();
                break;
            }
            Err(err) => {
                let valid_up_to = err.valid_up_to();
                if valid_up_to > 0 {
                    // SAFETY: valid_up_to 之前的字节已被 UTF-8 校验为有效。
                    let valid = unsafe { std::str::from_utf8_unchecked(&pending[..valid_up_to]) };
                    out.push_str(valid);
                    pending.drain(..valid_up_to);
                    continue;
                }

                match err.error_len() {
                    None => {
                        // 不完整的 UTF-8 序列（通常发生在末尾），等待更多字节再解码。
                        break;
                    }
                    Some(len) => {
                        // 非法字节：输出替换字符并跳过该段，避免死循环。
                        out.push('\u{FFFD}');
                        pending.drain(..len);
                    }
                }
            }
        }
    }

    out
}

#[derive(Default)]
pub struct TerminalState {
    pub sessions: Arc<Mutex<HashMap<String, Arc<PtySession>>>>,
    pub session_meta_by_key: Arc<Mutex<HashMap<String, TerminalSessionMeta>>>,
    pub pty_to_session_key: Arc<Mutex<HashMap<String, String>>>,
}

#[derive(Debug, Clone)]
pub struct TerminalSessionMeta {
    pub window_label: String,
    pub session_id: String,
    pub pty_id: String,
    pub shell_pid: Option<u32>,
}

#[derive(Debug, Clone, Default)]
struct RolloutContextInfo {
    model: Option<String>,
    effort: Option<String>,
    updated_at: i64,
}

pub struct PtySession {
    pub master: Mutex<Box<dyn MasterPty + Send>>,
    pub writer: Mutex<Box<dyn Write + Send>>,
    pub child: Mutex<Box<dyn Child + Send>>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TerminalCreateResult {
    pub pty_id: String,
    pub session_id: String,
    pub shell: String,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalOutputPayload {
    session_id: String,
    data: String,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalExitPayload {
    session_id: String,
    code: Option<i32>,
}

fn default_shell() -> String {
    std::env::var("SHELL").unwrap_or_else(|_| "/bin/zsh".to_string())
}

#[cfg(target_os = "macos")]
fn resolve_login_username() -> Option<String> {
    if let Some(user) = std::env::var("USER")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
    {
        return Some(user);
    }

    Command::new("/usr/bin/id")
        .arg("-un")
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn build_terminal_command(shell: &str) -> CommandBuilder {
    #[cfg(target_os = "macos")]
    {
        if let Some(username) = resolve_login_username() {
            let mut cmd = CommandBuilder::new("/usr/bin/login");
            cmd.arg("-flp");
            cmd.arg(username);
            cmd.arg("/bin/bash");
            cmd.arg("--noprofile");
            cmd.arg("--norc");
            cmd.arg("-c");
            cmd.arg(format!("exec -l {shell}"));
            return cmd;
        }
    }

    CommandBuilder::new(shell.to_string())
}

fn ensure_terminal_env(cmd: &mut CommandBuilder) {
    // GUI 启动的 macOS App 往往缺少 TERM/PATH 等环境变量，导致交互式 shell 初始化时报错。
    if cmd.get_env("TERM").is_none() {
        cmd.env("TERM", "xterm-256color");
    }

    #[cfg(target_os = "macos")]
    {
        // Homebrew 典型安装路径不一定在 Finder 启动的进程 PATH 中，补齐以保持 dev/打包一致。
        let current = cmd
            .get_env("PATH")
            .map(|p| p.to_os_string())
            .or_else(|| std::env::var_os("PATH"))
            .unwrap_or_default();
        let existing: Vec<PathBuf> = std::env::split_paths(&current).collect();

        let mut prepend: Vec<PathBuf> = Vec::new();
        let mut candidate_dirs: Vec<PathBuf> = vec![
            PathBuf::from("/opt/homebrew/bin"),
            PathBuf::from("/opt/homebrew/sbin"),
            PathBuf::from("/usr/local/bin"),
            PathBuf::from("/usr/local/sbin"),
        ];

        // JetBrains Toolbox 的 shell scripts（例如 idea）默认安装在这里，
        // GUI 启动时通常不会自动出现在 PATH 中。
        if let Some(home) = std::env::var_os("HOME") {
            let toolbox_scripts = PathBuf::from(home)
                .join("Library")
                .join("Application Support")
                .join("JetBrains")
                .join("Toolbox")
                .join("scripts");
            candidate_dirs.push(toolbox_scripts);
        }

        for p in candidate_dirs {
            if !p.exists() {
                continue;
            }
            if existing.iter().any(|e| e == &p) || prepend.iter().any(|e| e == &p) {
                continue;
            }
            prepend.push(p);
        }

        if !prepend.is_empty() {
            let mut merged = prepend;
            merged.extend(existing);
            if let Ok(joined) = std::env::join_paths(merged) {
                cmd.env("PATH", joined);
            }
        }
    }
}

fn build_terminal_session_key(window_label: &str, session_id: &str) -> String {
    format!("{}::{}", window_label, session_id)
}

fn register_terminal_session_meta(
    state: &TerminalState,
    meta: TerminalSessionMeta,
) -> Result<(), String> {
    let key = build_terminal_session_key(&meta.window_label, &meta.session_id);
    let old_pty = {
        let mut session_meta_by_key = state
            .session_meta_by_key
            .lock()
            .map_err(|_| "终端会话元信息锁定失败".to_string())?;
        session_meta_by_key
            .insert(key.clone(), meta.clone())
            .map(|old| old.pty_id)
    };

    let mut pty_to_session_key = state
        .pty_to_session_key
        .lock()
        .map_err(|_| "终端会话索引锁定失败".to_string())?;
    if let Some(old_pty) = old_pty {
        pty_to_session_key.remove(&old_pty);
    }
    pty_to_session_key.insert(meta.pty_id.clone(), key);
    Ok(())
}

fn remove_terminal_session_meta_by_pty(
    session_meta_by_key: &Arc<Mutex<HashMap<String, TerminalSessionMeta>>>,
    pty_to_session_key: &Arc<Mutex<HashMap<String, String>>>,
    pty_id: &str,
) {
    let key = {
        let Ok(mut pty_index) = pty_to_session_key.lock() else {
            return;
        };
        pty_index.remove(pty_id)
    };

    let Some(key) = key else {
        return;
    };

    if let Ok(mut session_meta) = session_meta_by_key.lock() {
        let should_remove = session_meta
            .get(&key)
            .map(|current| current.pty_id == pty_id)
            .unwrap_or(false);
        if should_remove {
            session_meta.remove(&key);
        }
    }
}

fn now_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

fn system_time_to_millis(time: SystemTime) -> Option<i64> {
    time.duration_since(UNIX_EPOCH)
        .ok()
        .map(|duration| duration.as_millis() as i64)
}

fn file_modified_millis(path: &Path) -> Option<i64> {
    let modified = fs::metadata(path).ok()?.modified().ok()?;
    system_time_to_millis(modified)
}

fn parse_timestamp(value: &Value) -> Option<i64> {
    value
        .as_str()
        .and_then(|text| chrono::DateTime::parse_from_rfc3339(text).ok())
        .map(|dt| dt.timestamp_millis())
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
    let mut lines: Vec<&str> = text.split('\n').collect();
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

fn parse_rollout_context(path: &Path) -> RolloutContextInfo {
    let mut info = RolloutContextInfo {
        updated_at: file_modified_millis(path).unwrap_or(0),
        ..RolloutContextInfo::default()
    };

    let lines = match read_tail_lines_resilient(
        path,
        MAX_ROLLOUT_TAIL_LINES,
        MAX_ROLLOUT_TAIL_BYTES,
        MAX_ROLLOUT_TAIL_BYTES_CAP,
    ) {
        Ok(lines) => lines,
        Err(_) => return info,
    };

    for line in lines {
        if line.trim().is_empty() || line.len() > MAX_ROLLOUT_JSON_LINE_BYTES {
            continue;
        }
        let value: Value = match serde_json::from_str(&line) {
            Ok(value) => value,
            Err(_) => continue,
        };
        if value.get("type").and_then(|item| item.as_str()) != Some("turn_context") {
            continue;
        }
        let Some(payload) = value.get("payload") else {
            continue;
        };

        if let Some(model) = payload
            .get("model")
            .and_then(|item| item.as_str())
            .map(|text| text.trim())
            .filter(|text| !text.is_empty())
        {
            info.model = Some(model.to_string());
        }

        if let Some(effort) = payload
            .get("effort")
            .and_then(|item| item.as_str())
            .map(|text| text.trim())
            .filter(|text| !text.is_empty())
        {
            info.effort = Some(effort.to_string());
        }

        if let Some(timestamp) = value
            .get("timestamp")
            .and_then(parse_timestamp)
            .or_else(|| payload.get("timestamp").and_then(parse_timestamp))
        {
            info.updated_at = info.updated_at.max(timestamp);
        }
    }

    info
}

fn is_rollout_file(path: &Path) -> bool {
    let Some(file_name) = path.file_name().and_then(|value| value.to_str()) else {
        return false;
    };
    file_name.starts_with("rollout-") && file_name.ends_with(".jsonl")
}

fn choose_latest_rollout_path(paths: &[PathBuf]) -> Option<PathBuf> {
    let mut best_path: Option<PathBuf> = None;
    let mut best_modified = i64::MIN;

    for path in paths {
        let modified = file_modified_millis(path).unwrap_or(0);
        if best_path.is_none() || modified > best_modified {
            best_path = Some(path.clone());
            best_modified = modified;
        }
    }

    best_path
}

fn run_lsof_output_for_pid(pid: u32) -> Option<std::process::Output> {
    #[cfg(not(any(target_os = "macos", target_os = "linux")))]
    {
        let _ = pid;
        None
    }

    #[cfg(any(target_os = "macos", target_os = "linux"))]
    {
        let pid_text = pid.to_string();
        let args = ["-n", "-P", "-Fn", "-p", pid_text.as_str()];
        match Command::new("lsof").args(args).output() {
            Ok(output) => Some(output),
            Err(error) => {
                if error.kind() != std::io::ErrorKind::NotFound {
                    log::debug!("运行 lsof 失败: {}", error);
                    return None;
                }
                for candidate in ["/usr/sbin/lsof", "/usr/bin/lsof"] {
                    match Command::new(candidate).args(args).output() {
                        Ok(output) => return Some(output),
                        Err(_) => continue,
                    }
                }
                None
            }
        }
    }
}

fn list_rollout_files_opened_by_pid(pid: u32, codex_sessions_root: &Path) -> Vec<PathBuf> {
    let output = match run_lsof_output_for_pid(pid) {
        Some(output) => output,
        None => return Vec::new(),
    };

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut files = Vec::new();
    for line in stdout.lines() {
        let Some(path_text) = line.strip_prefix('n') else {
            continue;
        };
        let path = PathBuf::from(path_text.trim());
        if !path.starts_with(codex_sessions_root) {
            continue;
        }
        if !is_rollout_file(&path) {
            continue;
        }
        files.push(path);
    }

    files.sort();
    files.dedup();
    files
}

fn build_process_children_index(system: &System) -> HashMap<u32, Vec<u32>> {
    let mut children: HashMap<u32, Vec<u32>> = HashMap::new();
    for (pid, process) in system.processes() {
        let Some(parent) = process.parent() else {
            continue;
        };
        children
            .entry(parent.as_u32())
            .or_default()
            .push(pid.as_u32());
    }
    children
}

fn collect_descendant_codex_pids(
    root_pid: u32,
    system: &System,
    children_index: &HashMap<u32, Vec<u32>>,
) -> Vec<u32> {
    let mut stack = vec![root_pid];
    let mut seen = HashSet::new();
    let mut codex_pids = Vec::new();

    while let Some(current_pid) = stack.pop() {
        if !seen.insert(current_pid) {
            continue;
        }

        if current_pid != root_pid {
            if let Some(process) = system.process(Pid::from_u32(current_pid)) {
                let name = process.name().to_ascii_lowercase();
                if name == "codex" || name == "codex.exe" {
                    codex_pids.push(current_pid);
                }
            }
        }

        if let Some(children) = children_index.get(&current_pid) {
            stack.extend(children.iter().copied());
        }
    }

    codex_pids.sort_unstable();
    codex_pids.dedup();
    codex_pids
}

fn collect_target_terminal_sessions(
    state: &TerminalState,
    window_label: &str,
    session_ids: &[String],
) -> Result<Vec<TerminalSessionMeta>, String> {
    let session_meta_by_key = state
        .session_meta_by_key
        .lock()
        .map_err(|_| "终端会话元信息锁定失败".to_string())?;

    let mut result = Vec::new();
    for session_id in session_ids {
        let key = build_terminal_session_key(window_label, session_id);
        if let Some(meta) = session_meta_by_key.get(&key) {
            result.push(meta.clone());
        }
    }
    Ok(result)
}

#[tauri::command]
pub fn terminal_get_codex_pane_overlay(
    app: AppHandle,
    state: State<TerminalState>,
    window_label: String,
    session_ids: Vec<String>,
) -> Result<Vec<TerminalCodexPaneOverlay>, String> {
    if session_ids.is_empty() {
        return Ok(Vec::new());
    }

    let target_sessions = collect_target_terminal_sessions(&state, &window_label, &session_ids)?;
    if target_sessions.is_empty() {
        return Ok(Vec::new());
    }

    let codex_sessions_root = app
        .path()
        .home_dir()
        .map_err(|err| format!("无法获取用户目录: {err}"))?
        .join(".codex")
        .join("sessions");
    if !codex_sessions_root.exists() {
        return Ok(Vec::new());
    }

    let mut system = System::new();
    system.refresh_processes();
    let children_index = build_process_children_index(&system);
    let mut rollout_cache: HashMap<PathBuf, RolloutContextInfo> = HashMap::new();
    let now = now_millis();

    let mut overlays = Vec::new();
    for terminal_session in target_sessions {
        let Some(shell_pid) = terminal_session.shell_pid else {
            continue;
        };

        let codex_pids = collect_descendant_codex_pids(shell_pid, &system, &children_index);
        if codex_pids.is_empty() {
            continue;
        }

        let mut rollout_paths = Vec::new();
        for codex_pid in codex_pids {
            rollout_paths.extend(list_rollout_files_opened_by_pid(
                codex_pid,
                &codex_sessions_root,
            ));
        }

        let Some(rollout_path) = choose_latest_rollout_path(&rollout_paths) else {
            continue;
        };

        let rollout_info = rollout_cache
            .entry(rollout_path.clone())
            .or_insert_with(|| parse_rollout_context(&rollout_path))
            .clone();

        overlays.push(TerminalCodexPaneOverlay {
            session_id: terminal_session.session_id,
            model: rollout_info.model,
            effort: rollout_info.effort,
            updated_at: if rollout_info.updated_at > 0 {
                rollout_info.updated_at
            } else {
                now
            },
        });
    }

    Ok(overlays)
}

#[tauri::command]
pub fn terminal_create_session(
    app: AppHandle,
    state: State<TerminalState>,
    project_path: String,
    cols: u16,
    rows: u16,
    window_label: String,
    session_id: Option<String>,
) -> Result<TerminalCreateResult, String> {
    let shell = default_shell();
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|err| format!("创建终端失败: {err}"))?;

    let mut cmd = build_terminal_command(&shell);
    cmd.cwd(project_path);
    ensure_terminal_env(&mut cmd);

    let child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|err| format!("启动终端失败: {err}"))?;
    drop(pair.slave);

    let master = pair.master;
    let reader = master
        .try_clone_reader()
        .map_err(|err| format!("读取终端失败: {err}"))?;
    let writer = master
        .take_writer()
        .map_err(|err| format!("打开终端写入失败: {err}"))?;

    let session_id = session_id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let pty_id = Uuid::new_v4().to_string();
    let shell_pid = child.process_id();

    let session = Arc::new(PtySession {
        master: Mutex::new(master),
        writer: Mutex::new(writer),
        child: Mutex::new(child),
    });

    {
        let mut sessions = state
            .sessions
            .lock()
            .map_err(|_| "终端会话锁定失败".to_string())?;
        sessions.insert(pty_id.clone(), session.clone());
    }

    if let Err(error) = register_terminal_session_meta(
        &state,
        TerminalSessionMeta {
            window_label: window_label.clone(),
            session_id: session_id.clone(),
            pty_id: pty_id.clone(),
            shell_pid,
        },
    ) {
        if let Ok(mut sessions) = state.sessions.lock() {
            sessions.remove(&pty_id);
        }
        if let Ok(mut child) = session.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
        return Err(error);
    }

    let app_handle = app.clone();
    let sessions_map = state.sessions.clone();
    let session_meta_by_key = state.session_meta_by_key.clone();
    let pty_to_session_key = state.pty_to_session_key.clone();
    let session_id_for_output = session_id.clone();
    let window_label_for_output = window_label.clone();
    let pty_id_for_output = pty_id.clone();
    let session_for_output = session.clone();

    thread::spawn(move || {
        let mut reader = reader;
        let mut buffer = [0u8; 8192];
        let mut pending_utf8: Vec<u8> = Vec::new();
        loop {
            match reader.read(&mut buffer) {
                Ok(0) => break,
                Ok(size) => {
                    pending_utf8.extend_from_slice(&buffer[..size]);
                    let data = drain_utf8_stream(&mut pending_utf8);
                    if !data.is_empty() {
                        let _ = app_handle.emit_to(
                            &window_label_for_output,
                            TERMINAL_OUTPUT_EVENT,
                            TerminalOutputPayload {
                                session_id: session_id_for_output.clone(),
                                data,
                            },
                        );
                    }
                }
                Err(_) => break,
            }
        }

        // 尽量不要丢尾巴：如果最后残留了半个字符（或非法字节），用 lossy 方式吐出来。
        if !pending_utf8.is_empty() {
            let data = String::from_utf8_lossy(&pending_utf8).to_string();
            if !data.is_empty() {
                let _ = app_handle.emit_to(
                    &window_label_for_output,
                    TERMINAL_OUTPUT_EVENT,
                    TerminalOutputPayload {
                        session_id: session_id_for_output.clone(),
                        data,
                    },
                );
            }
        }

        let exit_code = match session_for_output.child.lock() {
            Ok(mut child) => child.wait().ok().map(|status| status.exit_code() as i32),
            Err(_) => None,
        };

        let _ = app_handle.emit_to(
            &window_label_for_output,
            TERMINAL_EXIT_EVENT,
            TerminalExitPayload {
                session_id: session_id_for_output.clone(),
                code: exit_code,
            },
        );
        if let Ok(mut sessions) = sessions_map.lock() {
            sessions.remove(&pty_id_for_output);
        }
        remove_terminal_session_meta_by_pty(
            &session_meta_by_key,
            &pty_to_session_key,
            &pty_id_for_output,
        );
    });

    Ok(TerminalCreateResult {
        pty_id,
        session_id,
        shell,
    })
}

#[tauri::command]
pub fn terminal_write(
    state: State<TerminalState>,
    pty_id: String,
    data: String,
) -> Result<(), String> {
    let sessions = state
        .sessions
        .lock()
        .map_err(|_| "终端会话锁定失败".to_string())?;
    let session = sessions
        .get(&pty_id)
        .ok_or_else(|| "终端会话不存在".to_string())?;
    let mut writer = session
        .writer
        .lock()
        .map_err(|_| "终端写入锁定失败".to_string())?;
    writer
        .write_all(data.as_bytes())
        .map_err(|err| format!("终端写入失败: {err}"))?;
    writer
        .flush()
        .map_err(|err| format!("终端刷新失败: {err}"))?;
    Ok(())
}

#[tauri::command]
pub fn terminal_resize(
    state: State<TerminalState>,
    pty_id: String,
    cols: u16,
    rows: u16,
) -> Result<(), String> {
    let sessions = state
        .sessions
        .lock()
        .map_err(|_| "终端会话锁定失败".to_string())?;
    let session = sessions
        .get(&pty_id)
        .ok_or_else(|| "终端会话不存在".to_string())?;
    let master = session
        .master
        .lock()
        .map_err(|_| "终端调整锁定失败".to_string())?;
    master
        .resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|err| format!("调整终端大小失败: {err}"))?;
    Ok(())
}

#[tauri::command]
pub fn terminal_kill(state: State<TerminalState>, pty_id: String) -> Result<(), String> {
    let session = {
        let mut sessions = state
            .sessions
            .lock()
            .map_err(|_| "终端会话锁定失败".to_string())?;
        sessions.remove(&pty_id)
    };

    if let Some(session) = session {
        let mut child = session
            .child
            .lock()
            .map_err(|_| "终端会话锁定失败".to_string())?;
        let _ = child.kill();
        let _ = child.wait();
    }
    remove_terminal_session_meta_by_pty(
        &state.session_meta_by_key,
        &state.pty_to_session_key,
        &pty_id,
    );
    Ok(())
}
