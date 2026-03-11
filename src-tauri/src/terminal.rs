use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Arc, Mutex, mpsc};
use std::thread;
use std::time::{Duration, Instant};

use portable_pty::{Child, CommandBuilder, MasterPty, PtySize, native_pty_system};
use serde::Serialize;
use tauri::{AppHandle, Emitter, State};
use uuid::Uuid;

use crate::web_event_bus;

const TERMINAL_OUTPUT_EVENT: &str = "terminal-output";
const TERMINAL_EXIT_EVENT: &str = "terminal-exit";
const TERMINAL_OUTPUT_BATCH_MS: u64 = 8;
const TERMINAL_OUTPUT_BATCH_MAX_BYTES: usize = 32 * 1024;
const TERMINAL_OUTPUT_CACHE_MAX_BYTES: usize = 4 * 1024 * 1024;

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

#[derive(Default, Clone)]
pub struct TerminalState {
    pub sessions: Arc<Mutex<HashMap<String, Arc<PtySession>>>>,
    pub session_to_pty: Arc<Mutex<HashMap<String, String>>>,
    pub pty_to_session: Arc<Mutex<HashMap<String, String>>>,
    pub pty_clients: Arc<Mutex<HashMap<String, HashSet<String>>>>,
    pub output_cache_by_pty: Arc<Mutex<HashMap<String, String>>>,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    pub replay_data: Option<String>,
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

fn emit_terminal_output(app_handle: &AppHandle, session_id: &str, data: &mut String) {
    if data.is_empty() {
        return;
    }

    let payload = TerminalOutputPayload {
        session_id: session_id.to_string(),
        data: std::mem::take(data),
    };

    let _ = app_handle.emit(TERMINAL_OUTPUT_EVENT, payload.clone());
    web_event_bus::publish(TERMINAL_OUTPUT_EVENT, &payload);
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

fn normalize_client_id(client_id: Option<String>, window_label: &str) -> String {
    client_id
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .unwrap_or_else(|| format!("window:{window_label}"))
}

fn trim_terminal_output_cache(cache: &mut String) {
    if cache.len() <= TERMINAL_OUTPUT_CACHE_MAX_BYTES {
        return;
    }

    let target_start = cache.len().saturating_sub(TERMINAL_OUTPUT_CACHE_MAX_BYTES);
    let start = adjust_trim_start_for_escape_sequence(cache, target_start);
    cache.drain(..start);
}

fn advance_to_char_boundary(text: &str, mut index: usize) -> usize {
    while index < text.len() && !text.is_char_boundary(index) {
        index += 1;
    }
    index
}

fn find_csi_sequence_end(bytes: &[u8], mut index: usize) -> Option<usize> {
    while let Some(&byte) = bytes.get(index) {
        if (0x40..=0x7e).contains(&byte) {
            return Some(index + 1);
        }
        index += 1;
    }
    None
}

fn find_st_terminated_sequence_end(bytes: &[u8], mut index: usize) -> Option<usize> {
    while let Some(&byte) = bytes.get(index) {
        if byte == 0x1b && bytes.get(index + 1) == Some(&b'\\') {
            return Some(index + 2);
        }
        index += 1;
    }
    None
}

fn find_osc_sequence_end(bytes: &[u8], mut index: usize) -> Option<usize> {
    while let Some(&byte) = bytes.get(index) {
        if byte == 0x07 {
            return Some(index + 1);
        }
        if byte == 0x1b && bytes.get(index + 1) == Some(&b'\\') {
            return Some(index + 2);
        }
        index += 1;
    }
    None
}

fn find_escape_sequence_end(bytes: &[u8], start: usize) -> Option<usize> {
    let marker = *bytes.get(start + 1)?;
    match marker {
        b'[' => find_csi_sequence_end(bytes, start + 2),
        b']' => find_osc_sequence_end(bytes, start + 2),
        b'P' | b'^' | b'_' | b'X' => find_st_terminated_sequence_end(bytes, start + 2),
        _ => {
            let mut index = start + 1;
            while let Some(&byte) = bytes.get(index) {
                if (0x30..=0x7e).contains(&byte) {
                    return Some(index + 1);
                }
                index += 1;
            }
            None
        }
    }
}

fn adjust_trim_start_for_escape_sequence(cache: &str, start: usize) -> usize {
    let bytes = cache.as_bytes();
    let mut safe_start = advance_to_char_boundary(cache, start);

    while safe_start > 0 {
        let Some(escape_index) = bytes[..safe_start].iter().rposition(|byte| *byte == 0x1b) else {
            break;
        };
        let Some(sequence_end) = find_escape_sequence_end(bytes, escape_index) else {
            return cache.len();
        };
        if sequence_end <= safe_start {
            break;
        }
        safe_start = advance_to_char_boundary(cache, sequence_end);
    }

    safe_start
}

fn append_terminal_output_cache(state: &TerminalState, pty_id: &str, chunk: &str) {
    if chunk.is_empty() {
        return;
    }

    let Ok(mut cache_by_pty) = state.output_cache_by_pty.lock() else {
        return;
    };
    let cache = cache_by_pty
        .entry(pty_id.to_string())
        .or_insert_with(String::new);
    cache.push_str(chunk);
    trim_terminal_output_cache(cache);
}

fn register_terminal_session_index(
    state: &TerminalState,
    session_id: &str,
    pty_id: &str,
) -> Result<(), String> {
    let old_pty = {
        let mut session_to_pty = state
            .session_to_pty
            .lock()
            .map_err(|_| "终端会话索引锁定失败".to_string())?;
        session_to_pty.insert(session_id.to_string(), pty_id.to_string())
    };

    let mut pty_to_session = state
        .pty_to_session
        .lock()
        .map_err(|_| "终端会话索引锁定失败".to_string())?;
    if let Some(old_pty) = old_pty {
        pty_to_session.remove(&old_pty);
    }
    pty_to_session.insert(pty_id.to_string(), session_id.to_string());
    Ok(())
}

fn attach_terminal_client(
    state: &TerminalState,
    pty_id: &str,
    client_id: &str,
) -> Result<(), String> {
    let mut clients = state
        .pty_clients
        .lock()
        .map_err(|_| "终端会话客户端索引锁定失败".to_string())?;
    clients
        .entry(pty_id.to_string())
        .or_insert_with(HashSet::new)
        .insert(client_id.to_string());
    Ok(())
}

fn detach_terminal_client(
    state: &TerminalState,
    pty_id: &str,
    client_id: Option<&str>,
    force: bool,
) -> Result<bool, String> {
    if force {
        if let Ok(mut clients) = state.pty_clients.lock() {
            clients.remove(pty_id);
        }
        return Ok(true);
    }

    let Some(client_id) = client_id else {
        return Ok(true);
    };

    let mut clients = state
        .pty_clients
        .lock()
        .map_err(|_| "终端会话客户端索引锁定失败".to_string())?;
    let Some(owners) = clients.get_mut(pty_id) else {
        return Ok(true);
    };
    owners.remove(client_id);
    if !owners.is_empty() {
        return Ok(false);
    }
    clients.remove(pty_id);
    Ok(true)
}

fn find_existing_pty_by_session(
    state: &TerminalState,
    session_id: &str,
) -> Result<Option<String>, String> {
    let maybe_pty = state
        .session_to_pty
        .lock()
        .map_err(|_| "终端会话索引锁定失败".to_string())?
        .get(session_id)
        .cloned();

    let Some(pty_id) = maybe_pty else {
        return Ok(None);
    };

    let is_alive = state
        .sessions
        .lock()
        .map_err(|_| "终端会话锁定失败".to_string())?
        .contains_key(&pty_id);
    if is_alive {
        return Ok(Some(pty_id));
    }

    // 清理异常退出后遗留的索引，再按新会话重建。
    if let Ok(mut session_to_pty) = state.session_to_pty.lock() {
        session_to_pty.remove(session_id);
    }
    if let Ok(mut pty_to_session) = state.pty_to_session.lock() {
        pty_to_session.remove(&pty_id);
    }
    if let Ok(mut clients) = state.pty_clients.lock() {
        clients.remove(&pty_id);
    }
    Ok(None)
}

fn remove_terminal_session_index_by_pty(state: &TerminalState, pty_id: &str) {
    let session_id = {
        let Ok(mut pty_to_session) = state.pty_to_session.lock() else {
            return;
        };
        pty_to_session.remove(pty_id)
    };

    if let Some(session_id) = session_id {
        if let Ok(mut session_to_pty) = state.session_to_pty.lock() {
            let should_remove = session_to_pty
                .get(&session_id)
                .map(|current| current == pty_id)
                .unwrap_or(false);
            if should_remove {
                session_to_pty.remove(&session_id);
            }
        }
    }

    if let Ok(mut clients) = state.pty_clients.lock() {
        clients.remove(pty_id);
    }
    if let Ok(mut cache_by_pty) = state.output_cache_by_pty.lock() {
        cache_by_pty.remove(pty_id);
    }
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
    client_id: Option<String>,
) -> Result<TerminalCreateResult, String> {
    let shell = default_shell();
    let session_id = session_id.unwrap_or_else(|| Uuid::new_v4().to_string());
    let client_id = normalize_client_id(client_id, &window_label);

    if let Some(existing_pty) = find_existing_pty_by_session(&state, &session_id)? {
        attach_terminal_client(&state, &existing_pty, &client_id)?;
        let replay_data = state
            .output_cache_by_pty
            .lock()
            .ok()
            .and_then(|cache_by_pty| cache_by_pty.get(&existing_pty).cloned())
            .filter(|value| !value.is_empty());
        return Ok(TerminalCreateResult {
            pty_id: existing_pty,
            session_id,
            shell,
            replay_data,
        });
    }

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

    let pty_id = Uuid::new_v4().to_string();

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

    if let Err(error) = register_terminal_session_index(&state, &session_id, &pty_id)
        .and_then(|_| attach_terminal_client(&state, &pty_id, &client_id))
    {
        remove_terminal_session_index_by_pty(&state, &pty_id);
        if let Ok(mut sessions) = state.sessions.lock() {
            sessions.remove(&pty_id);
        }
        if let Ok(mut child) = session.child.lock() {
            let _ = child.kill();
            let _ = child.wait();
        }
        return Err(error);
    }

    if let Ok(mut cache_by_pty) = state.output_cache_by_pty.lock() {
        cache_by_pty.insert(pty_id.clone(), String::new());
    }

    let app_handle = app.clone();
    let sessions_map = state.sessions.clone();
    let terminal_state_for_cleanup = state.inner().clone();
    let session_id_for_output = session_id.clone();
    let pty_id_for_output = pty_id.clone();
    let session_for_output = session.clone();

    thread::spawn(move || {
        let batch_window = Duration::from_millis(TERMINAL_OUTPUT_BATCH_MS);
        let (output_tx, output_rx) = mpsc::channel::<String>();

        let reader_thread = thread::spawn(move || {
            let mut reader = reader;
            let mut buffer = [0u8; 8192];
            let mut pending_utf8: Vec<u8> = Vec::new();
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(size) => {
                        pending_utf8.extend_from_slice(&buffer[..size]);
                        let data = drain_utf8_stream(&mut pending_utf8);
                        if !data.is_empty() && output_tx.send(data).is_err() {
                            return;
                        }
                    }
                    Err(_) => break,
                }
            }

            // 尽量不要丢尾巴：如果最后残留了半个字符（或非法字节），用 lossy 方式吐出来。
            if !pending_utf8.is_empty() {
                let data = String::from_utf8_lossy(&pending_utf8).to_string();
                if !data.is_empty() {
                    let _ = output_tx.send(data);
                }
            }
        });

        let mut batch_data = String::new();
        let mut batch_started_at: Option<Instant> = None;
        loop {
            // 微批量策略：第一个 chunk 到达后，最多等待 8ms 聚合后统一 emit；
            // 若流持续不断，则按窗口周期强制 flush，避免事件风暴并控制 UI 延迟。
            let wait_timeout = batch_started_at
                .map(|started| batch_window.saturating_sub(started.elapsed()))
                .unwrap_or(batch_window);

            match output_rx.recv_timeout(wait_timeout) {
                Ok(chunk) => {
                    if batch_started_at.is_none() {
                        batch_started_at = Some(Instant::now());
                    }
                    batch_data.push_str(&chunk);

                    let should_flush_by_time = batch_started_at
                        .map(|started| started.elapsed() >= batch_window)
                        .unwrap_or(false);
                    let should_flush_by_size = batch_data.len() >= TERMINAL_OUTPUT_BATCH_MAX_BYTES;

                    // 高吞吐下除了 8ms 窗口，还按字节阈值强制 flush，避免单批过大。
                    if should_flush_by_time || should_flush_by_size {
                        append_terminal_output_cache(
                            &terminal_state_for_cleanup,
                            &pty_id_for_output,
                            &batch_data,
                        );
                        emit_terminal_output(&app_handle, &session_id_for_output, &mut batch_data);
                        batch_started_at = None;
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    append_terminal_output_cache(
                        &terminal_state_for_cleanup,
                        &pty_id_for_output,
                        &batch_data,
                    );
                    emit_terminal_output(&app_handle, &session_id_for_output, &mut batch_data);
                    batch_started_at = None;
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    // reader 结束后，先刷完缓存，再进入 exit 事件，保证输出完整有序。
                    append_terminal_output_cache(
                        &terminal_state_for_cleanup,
                        &pty_id_for_output,
                        &batch_data,
                    );
                    emit_terminal_output(&app_handle, &session_id_for_output, &mut batch_data);
                    break;
                }
            }
        }
        let _ = reader_thread.join();

        let exit_code = match session_for_output.child.lock() {
            Ok(mut child) => child.wait().ok().map(|status| status.exit_code() as i32),
            Err(_) => None,
        };

        let payload = TerminalExitPayload {
            session_id: session_id_for_output.clone(),
            code: exit_code,
        };
        let _ = app_handle.emit(TERMINAL_EXIT_EVENT, payload.clone());
        web_event_bus::publish(TERMINAL_EXIT_EVENT, &payload);
        if let Ok(mut sessions) = sessions_map.lock() {
            sessions.remove(&pty_id_for_output);
        }
        remove_terminal_session_index_by_pty(&terminal_state_for_cleanup, &pty_id_for_output);
    });

    Ok(TerminalCreateResult {
        pty_id,
        session_id,
        shell,
        replay_data: None,
    })
}

#[tauri::command]
pub fn terminal_write(
    state: State<TerminalState>,
    pty_id: String,
    data: String,
) -> Result<(), String> {
    let session = {
        let sessions = state
            .sessions
            .lock()
            .map_err(|_| "终端会话锁定失败".to_string())?;
        sessions
            .get(&pty_id)
            .cloned()
            .ok_or_else(|| "终端会话不存在".to_string())?
    };
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
    let session = {
        let sessions = state
            .sessions
            .lock()
            .map_err(|_| "终端会话锁定失败".to_string())?;
        sessions
            .get(&pty_id)
            .cloned()
            .ok_or_else(|| "终端会话不存在".to_string())?
    };
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
pub fn terminal_kill(
    state: State<TerminalState>,
    pty_id: String,
    client_id: Option<String>,
    force: Option<bool>,
) -> Result<(), String> {
    let should_terminate = detach_terminal_client(
        &state,
        &pty_id,
        client_id
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty()),
        force.unwrap_or(false),
    )?;
    if !should_terminate {
        return Ok(());
    }

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
    remove_terminal_session_index_by_pty(&state, &pty_id);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trim_terminal_output_cache_keeps_plain_text_tail() {
        let mut cache = "a".repeat(TERMINAL_OUTPUT_CACHE_MAX_BYTES + 32);
        trim_terminal_output_cache(&mut cache);

        assert_eq!(cache.len(), TERMINAL_OUTPUT_CACHE_MAX_BYTES);
        assert!(cache.chars().all(|ch| ch == 'a'));
    }

    #[test]
    fn trim_terminal_output_cache_skips_partial_csi_sequence() {
        let csi = "\u{1b}[?1;2c";
        let prefix = "r".repeat(19);
        let inside_offset = 2;
        let suffix = "v".repeat(TERMINAL_OUTPUT_CACHE_MAX_BYTES + inside_offset - csi.len());
        let mut cache = format!("{prefix}{csi}{suffix}");

        trim_terminal_output_cache(&mut cache);

        assert_eq!(cache.len(), suffix.len());
        assert!(cache.chars().all(|ch| ch == 'v'));
    }

    #[test]
    fn trim_terminal_output_cache_skips_partial_osc_sequence_with_st() {
        let osc = concat!(
            "\u{1b}]10;rgb:8383/9494/9696\u{1b}\\",
            "\u{1b}]11;rgb:0000/2b2b/3636\u{1b}\\",
        );
        let prefix = "p".repeat(17);
        let inside_offset = 5;
        let suffix = "x".repeat(TERMINAL_OUTPUT_CACHE_MAX_BYTES + inside_offset - osc.len());
        let mut cache = format!("{prefix}{osc}{suffix}");

        trim_terminal_output_cache(&mut cache);

        let expected_prefix = "\u{1b}]11;rgb:0000/2b2b/3636\u{1b}\\";
        assert_eq!(cache.len(), expected_prefix.len() + suffix.len());
        assert!(cache.starts_with(expected_prefix));
        assert!(cache[expected_prefix.len()..].chars().all(|ch| ch == 'x'));
    }

    #[test]
    fn trim_terminal_output_cache_skips_partial_osc_sequence_with_bel() {
        let osc = concat!(
            "\u{1b}]10;rgb:8383/9494/9696\u{7}",
            "\u{1b}]11;rgb:0000/2b2b/3636\u{7}",
        );
        let prefix = "q".repeat(11);
        let inside_offset = 3;
        let suffix = "y".repeat(TERMINAL_OUTPUT_CACHE_MAX_BYTES + inside_offset - osc.len());
        let mut cache = format!("{prefix}{osc}{suffix}");

        trim_terminal_output_cache(&mut cache);

        let expected_prefix = "\u{1b}]11;rgb:0000/2b2b/3636\u{7}";
        assert_eq!(cache.len(), expected_prefix.len() + suffix.len());
        assert!(cache.starts_with(expected_prefix));
        assert!(cache[expected_prefix.len()..].chars().all(|ch| ch == 'y'));
    }

    #[test]
    fn trim_terminal_output_cache_drops_when_boundary_lands_inside_second_osc() {
        let first_osc = "\u{1b}]10;rgb:8383/9494/9696\u{7}";
        let second_osc = "\u{1b}]11;rgb:0000/2b2b/3636\u{7}";
        let prefix = "z".repeat(23);
        let inside_offset = 4;
        let suffix = "w".repeat(TERMINAL_OUTPUT_CACHE_MAX_BYTES + inside_offset - second_osc.len());
        let mut cache = format!("{prefix}{first_osc}{second_osc}{suffix}");

        trim_terminal_output_cache(&mut cache);

        assert_eq!(cache.len(), suffix.len());
        assert!(cache.chars().all(|ch| ch == 'w'));
    }
}
