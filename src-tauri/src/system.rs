use std::io::Write;
use std::process::{Command, Stdio};

use tauri::AppHandle;
use tauri_plugin_clipboard_manager::ClipboardExt;

#[derive(Debug, serde::Deserialize)]
pub struct EditorOpenParams {
    pub path: String,
    pub app_name: Option<String>,
    pub bundle_id: Option<String>,
    pub command_path: Option<String>,
    pub arguments: Option<Vec<String>>,
}

#[derive(Debug, Clone, serde::Deserialize)]
pub struct SystemNotificationParams {
    pub title: String,
    pub body: Option<String>,
}

/// 在系统文件管理器中定位路径。
pub fn open_in_finder(path: &str) -> Result<(), String> {
    if cfg!(target_os = "macos") {
        let status = Command::new("/usr/bin/open")
            .args(["-R", path])
            .status()
            .map_err(|err| format!("无法打开 Finder: {err}"))?;
        if status.success() {
            return Ok(());
        }
        return Err("Finder 打开失败".to_string());
    }

    open_with_default(path)
}

/// 使用指定编辑器打开文件或目录。
pub fn open_in_editor(params: EditorOpenParams) -> Result<(), String> {
    if cfg!(target_os = "macos") {
        if let Some(app_name) = params.app_name.clone() {
            let status = Command::new("/usr/bin/open")
                .args(["-a", app_name.as_str(), params.path.as_str()])
                .status()
                .map_err(|err| format!("打开编辑器失败: {err}"))?;
            if status.success() {
                return Ok(());
            }
        }

        if let Some(bundle_id) = params.bundle_id.clone() {
            let status = Command::new("/usr/bin/open")
                .args(["-b", bundle_id.as_str(), params.path.as_str()])
                .status()
                .map_err(|err| format!("打开编辑器失败: {err}"))?;
            if status.success() {
                return Ok(());
            }
        }
    }

    if let Some(command_path) = params.command_path {
        let mut command = Command::new(command_path);
        if let Some(arguments) = params.arguments {
            command.args(arguments);
        }
        let status = command
            .arg(params.path)
            .status()
            .map_err(|err| format!("打开编辑器失败: {err}"))?;
        if status.success() {
            return Ok(());
        }
    }

    Err("未能打开编辑器".to_string())
}

/// 复制文本到系统剪贴板（跨平台）。
pub fn copy_to_clipboard(app: &AppHandle, content: &str) -> Result<(), String> {
    if let Err(err) = app.clipboard().write_text(content.to_string()) {
        #[cfg(target_os = "macos")]
        {
            let _ = err;
            return copy_with_pbcopy(content).map_err(|err| format!("写入剪贴板失败: {err}"));
        }
        #[cfg(not(target_os = "macos"))]
        {
            return Err(format!("写入剪贴板失败: {err}"));
        }
    }
    Ok(())
}

/// 发送系统通知。
pub fn send_system_notification(params: SystemNotificationParams) -> Result<(), String> {
    let title = params.title.trim().to_string();
    if title.is_empty() {
        return Err("通知标题不能为空".to_string());
    }

    #[cfg(target_os = "macos")]
    {
        let script = build_macos_notification_script(&title, params.body.as_deref());
        let status = Command::new("/usr/bin/osascript")
            .arg("-e")
            .arg(script)
            .status()
            .map_err(|err| format!("发送系统通知失败: {err}"))?;
        if status.success() {
            return Ok(());
        }
        return Err("发送系统通知失败".to_string());
    }

    #[cfg(not(target_os = "macos"))]
    {
        let _ = params;
        Err("当前平台暂未实现系统通知".to_string())
    }
}

#[cfg(target_os = "macos")]
fn copy_with_pbcopy(content: &str) -> Result<(), std::io::Error> {
    let mut child = Command::new("/usr/bin/pbcopy")
        .stdin(Stdio::piped())
        .spawn()?;
    if let Some(stdin) = child.stdin.as_mut() {
        stdin.write_all(content.as_bytes())?;
    }
    let status = child.wait()?;
    if status.success() {
        Ok(())
    } else {
        Err(std::io::Error::new(
            std::io::ErrorKind::Other,
            "写入剪贴板失败",
        ))
    }
}

// 使用系统默认方式打开路径。
fn open_with_default(path: &str) -> Result<(), String> {
    let status = Command::new("/usr/bin/open")
        .arg(path)
        .status()
        .map_err(|err| format!("无法打开路径: {err}"))?;
    if status.success() {
        Ok(())
    } else {
        Err("打开路径失败".to_string())
    }
}

#[cfg(target_os = "macos")]
fn build_macos_notification_script(title: &str, body: Option<&str>) -> String {
    let escaped_title = escape_applescript_string(title);
    let escaped_body = escape_applescript_string(body.unwrap_or(""));
    format!(r#"display notification "{}" with title "{}""#, escaped_body, escaped_title)
}

#[cfg(target_os = "macos")]
fn escape_applescript_string(input: &str) -> String {
    input.replace('\\', r#"\\"#).replace('"', r#"\""#)
}

#[cfg(test)]
mod tests {
    #[cfg(target_os = "macos")]
    use super::{build_macos_notification_script, escape_applescript_string};

    #[cfg(target_os = "macos")]
    #[test]
    fn escape_applescript_string_handles_quotes_and_backslashes() {
        assert_eq!(
            escape_applescript_string(r#"Hello "DevHaven" \ Codex"#),
            r#"Hello \"DevHaven\" \\ Codex"#
        );
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn build_macos_notification_script_includes_title_and_body() {
        let script = build_macos_notification_script("Codex 已完成", Some(r#"项目 "A""#));
        assert!(script.contains(r#"with title "Codex 已完成""#));
        assert!(script.contains(r#"display notification "项目 \"A\"""#));
    }
}
