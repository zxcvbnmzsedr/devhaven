use std::collections::HashMap;
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
    #[serde(skip_serializing_if = "Option::is_none")]
    window_label: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct TerminalExitPayload {
    session_id: String,
    code: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    window_label: Option<String>,
}

fn emit_terminal_output(
    app_handle: &AppHandle,
    window_label: &str,
    session_id: &str,
    data: &mut String,
) {
    if data.is_empty() {
        return;
    }

    let payload = TerminalOutputPayload {
        session_id: session_id.to_string(),
        data: std::mem::take(data),
        window_label: Some(window_label.to_string()),
    };

    let _ = app_handle.emit_to(window_label, TERMINAL_OUTPUT_EVENT, payload.clone());
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
                        emit_terminal_output(
                            &app_handle,
                            &window_label_for_output,
                            &session_id_for_output,
                            &mut batch_data,
                        );
                        batch_started_at = None;
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    emit_terminal_output(
                        &app_handle,
                        &window_label_for_output,
                        &session_id_for_output,
                        &mut batch_data,
                    );
                    batch_started_at = None;
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => {
                    // reader 结束后，先刷完缓存，再进入 exit 事件，保证输出完整有序。
                    emit_terminal_output(
                        &app_handle,
                        &window_label_for_output,
                        &session_id_for_output,
                        &mut batch_data,
                    );
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
            window_label: Some(window_label_for_output.clone()),
        };
        let _ = app_handle.emit_to(
            &window_label_for_output,
            TERMINAL_EXIT_EVENT,
            payload.clone(),
        );
        web_event_bus::publish(TERMINAL_EXIT_EVENT, &payload);
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
