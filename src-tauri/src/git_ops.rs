use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::OnceLock;

use crate::models::{
    BranchListItem, GitChangedFile, GitDiffContents, GitFileStatus, GitRepoStatus,
    GitWorktreeAddResult, GitWorktreeListItem,
};

/// 列出仓库下所有分支名称。
pub fn list_branches(base_path: &str) -> Vec<BranchListItem> {
    if !is_git_repo(base_path) {
        return Vec::new();
    }

    let result = execute_git_command(base_path, &["branch", "--list"]);
    if !result.success {
        return Vec::new();
    }

    let branches: Vec<String> = result
        .output
        .lines()
        .map(|line| line.replace('*', "").trim().to_string())
        .filter(|line| !line.is_empty())
        .collect();

    let default_branch = resolve_default_branch(&branches, base_path);

    branches
        .into_iter()
        .map(|name| BranchListItem {
            is_main: default_branch.as_deref() == Some(name.as_str()),
            name,
        })
        .collect()
}

/// 判断路径是否为 Git 仓库（以 `<path>/.git` 是否存在为准）。
///
/// 注意：worktree 场景下 `.git` 可能是文件，但依然视为存在。
pub fn is_git_repo(path: &str) -> bool {
    Path::new(path).join(".git").exists()
}

/// 获取仓库状态（staged/unstaged/untracked + 分支信息）。
pub fn get_repo_status(base_path: &str) -> Result<GitRepoStatus, String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let result = execute_git_command(base_path, &["status", "--porcelain=v2", "-z", "-b"]);
    if !result.success {
        return Err(result.output);
    }

    parse_porcelain_v2_status(&result.output)
}

/// 获取单文件对比用的原始/修改内容（用于 Monaco DiffEditor）。
///
/// - staged=true: original=HEAD:<old_or_current_path> modified=:<current_path>
/// - staged=false: original=:<old_or_current_path> modified=工作区文件内容
pub fn get_diff_contents(
    base_path: &str,
    relative_path: &str,
    staged: bool,
    old_relative_path: Option<&str>,
) -> Result<GitDiffContents, String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }
    let relative_path = relative_path.trim();
    if relative_path.is_empty() {
        return Err("路径为空".to_string());
    }

    let old_path = old_relative_path
        .map(|s| s.trim())
        .filter(|s| !s.is_empty())
        .unwrap_or(relative_path);

    const MAX_FILE_BYTES: usize = 1_200_000;

    let (original_bytes, original_truncated) = if staged {
        let spec = format!("HEAD:{old_path}");
        read_git_object_optional(base_path, &spec, MAX_FILE_BYTES)?
    } else {
        let spec = format!(":{old_path}");
        read_git_object_optional(base_path, &spec, MAX_FILE_BYTES)?
    };

    let (modified_bytes, modified_truncated) = if staged {
        let spec = format!(":{relative_path}");
        read_git_object_optional(base_path, &spec, MAX_FILE_BYTES)?
    } else {
        read_worktree_file_optional(base_path, relative_path, MAX_FILE_BYTES)?
    };

    let original = bytes_to_text(original_bytes)?;
    let modified = bytes_to_text(modified_bytes)?;

    Ok(GitDiffContents {
        original,
        modified,
        original_truncated,
        modified_truncated,
    })
}

/// 暂存文件（git add）。
pub fn stage_files(base_path: &str, relative_paths: &[String]) -> Result<(), String> {
    run_git_with_paths(base_path, ["add", "--"], relative_paths)
}

/// 取消暂存（git reset HEAD -- <paths>）。
pub fn unstage_files(base_path: &str, relative_paths: &[String]) -> Result<(), String> {
    run_git_with_paths(base_path, ["reset", "HEAD", "--"], relative_paths)
}

/// 丢弃未暂存修改（git checkout -- <paths>）。
pub fn discard_files(base_path: &str, relative_paths: &[String]) -> Result<(), String> {
    run_git_with_paths(base_path, ["checkout", "--"], relative_paths)
}

/// 提交已暂存改动（git commit -m）。
pub fn commit(base_path: &str, message: &str) -> Result<(), String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }
    let message = message.trim();
    if message.is_empty() {
        return Err("提交信息不能为空".to_string());
    }
    let result = execute_git_command(base_path, &["commit", "-m", message]);
    if result.success {
        Ok(())
    } else {
        Err(result.output)
    }
}

/// 切换分支（git checkout <branch>）。
pub fn checkout_branch(base_path: &str, branch: &str) -> Result<(), String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }
    let branch = branch.trim();
    if branch.is_empty() {
        return Err("分支名不能为空".to_string());
    }
    let result = execute_git_command(base_path, &["checkout", branch]);
    if result.success {
        Ok(())
    } else {
        Err(result.output)
    }
}

/// 删除本地分支（git branch -d/-D）。
pub fn delete_branch(base_path: &str, branch: &str, force: bool) -> Result<(), String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let branch = branch.trim();
    if branch.is_empty() {
        return Err("分支名不能为空".to_string());
    }

    let args = if force {
        ["branch", "-D", branch]
    } else {
        ["branch", "-d", branch]
    };
    let result = execute_git_command(base_path, &args);
    if result.success {
        Ok(())
    } else {
        Err(normalize_delete_branch_error(&result.output, force))
    }
}

/// 创建 Git worktree。
///
/// - create_branch=true: `git worktree add -b <branch> <target_path> [<start_point>]`
/// - create_branch=false: `git worktree add <target_path> <branch>`
pub fn add_worktree(
    base_path: &str,
    target_path: Option<&str>,
    branch: &str,
    create_branch: bool,
    start_point: Option<&str>,
) -> Result<GitWorktreeAddResult, String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let branch = branch.trim();
    if branch.is_empty() {
        return Err("分支名不能为空".to_string());
    }

    let target_path = resolve_worktree_target_path(base_path, branch, target_path)?;

    let target = Path::new(&target_path);
    if target.exists() {
        return Err("目标目录已存在，无法创建 worktree".to_string());
    }

    let parent = match target.parent() {
        Some(value) => value,
        None => return Err("目标路径非法".to_string()),
    };
    if !parent.exists() {
        fs::create_dir_all(parent).map_err(|err| format!("创建目标目录失败: {err}"))?;
    }
    if !parent.is_dir() {
        return Err("目标目录的父路径不是文件夹".to_string());
    }

    let mut args: Vec<&str> = vec!["worktree", "add"];
    if create_branch {
        let start_point = start_point.map(str::trim).filter(|value| !value.is_empty());
        args.push("-b");
        args.push(branch);
        args.push(target_path.as_str());
        if let Some(start_point) = start_point {
            args.push(start_point);
        }
    } else {
        args.push(target_path.as_str());
        args.push(branch);
    }

    let result = execute_git_command(base_path, &args);
    if result.success {
        return Ok(GitWorktreeAddResult {
            path: target_path.to_string(),
            branch: branch.to_string(),
        });
    }

    Err(normalize_worktree_add_error(&result.output, create_branch))
}

/// 解析“新建分支”模式下的创建起点：远端优先，本地回退。
///
/// 返回值是可直接用于 `git worktree add -b ... <start_point>` 的引用。
/// 优先返回 `origin/<base_branch>`，若不可用则回退 `<base_branch>`。
pub fn resolve_create_branch_start_point(
    base_path: &str,
    base_branch: &str,
) -> Result<String, String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let base_branch = base_branch.trim();
    if base_branch.is_empty() {
        return Err("基线分支不可用：分支名不能为空".to_string());
    }

    let remote_ref = format!("origin/{base_branch}");

    if has_origin_remote(base_path) {
        match branch_exists_on_remote(base_path, base_branch) {
            RemoteBranchCheck::Exists => {
                let fetch_error = fetch_origin_branch(base_path, base_branch).err();
                if ref_exists_locally(base_path, &remote_ref) {
                    if let Some(err) = fetch_error {
                        log::warn!(
                            "刷新远端基线分支失败，改用本地缓存引用 {}: {}",
                            remote_ref,
                            err
                        );
                    }
                    return Ok(remote_ref);
                }

                if ref_exists_locally(base_path, base_branch) {
                    return Ok(base_branch.to_string());
                }

                if let Some(err) = fetch_error {
                    return Err(format!(
                        "基线分支不可用：远端分支 {} 刷新失败，且本地不存在同名分支（{}）",
                        remote_ref, err
                    ));
                }

                return Err(format!(
                    "基线分支不可用：远端分支 {} 无法在本地解析",
                    remote_ref
                ));
            }
            RemoteBranchCheck::NotFound => {
                if ref_exists_locally(base_path, base_branch) {
                    return Ok(base_branch.to_string());
                }
                return Err(format!(
                    "基线分支不可用：远端与本地均不存在分支 {}",
                    base_branch
                ));
            }
            RemoteBranchCheck::Error(error) => {
                if ref_exists_locally(base_path, base_branch) {
                    log::warn!(
                        "远端基线分支校验失败，回退本地分支 {}: {}",
                        base_branch,
                        error
                    );
                    return Ok(base_branch.to_string());
                }
                return Err(format!(
                    "基线分支不可用：无法校验远端分支 {}，且本地不存在同名分支（{}）",
                    base_branch, error
                ));
            }
        }
    }

    if ref_exists_locally(base_path, base_branch) {
        return Ok(base_branch.to_string());
    }

    Err(format!("基线分支不可用：未找到本地分支 {}", base_branch))
}

pub fn resolve_worktree_target_path(
    base_path: &str,
    branch: &str,
    target_path: Option<&str>,
) -> Result<String, String> {
    let branch = branch.trim();
    if branch.is_empty() {
        return Err("分支名不能为空".to_string());
    }

    Ok(target_path
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or(resolve_default_worktree_path(base_path, branch)?))
}

/// 列出仓库下已有 worktree（不包含主仓库目录）。
pub fn list_worktrees(base_path: &str) -> Result<Vec<GitWorktreeListItem>, String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let result = execute_git_command(base_path, &["worktree", "list", "--porcelain"]);
    if !result.success {
        return Err(result.output);
    }

    Ok(parse_worktree_list_output(base_path, &result.output))
}

/// 删除 Git worktree（git worktree remove）。
pub fn remove_worktree(base_path: &str, worktree_path: &str, force: bool) -> Result<(), String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }

    let worktree_path = worktree_path.trim();
    if worktree_path.is_empty() {
        return Err("worktree 路径不能为空".to_string());
    }

    let base_normalized = normalize_path_for_compare(base_path);
    let worktree_normalized = normalize_path_for_compare(worktree_path);
    if base_normalized == worktree_normalized {
        return Err("不能删除主仓库目录".to_string());
    }

    // 先校验 worktree 是否存在于该仓库，避免误删任意目录。
    let listed = list_worktrees(base_path)?
        .into_iter()
        .any(|item| normalize_path_for_compare(&item.path) == worktree_normalized);
    if !listed {
        return Err("worktree 不存在或已移除".to_string());
    }

    let mut args: Vec<&str> = vec!["worktree", "remove"];
    if force {
        args.push("--force");
    }
    args.push(worktree_path);

    let result = execute_git_command(base_path, &args);
    if result.success {
        return Ok(());
    }

    // 若用户手动删除了目录，git 可能会提示 not a working tree；这时尝试 prune 清理残留记录。
    let lower = result.output.to_ascii_lowercase();
    if lower.contains("not a working tree")
        || lower.contains("is missing")
        || lower.contains("no such file or directory")
    {
        let prune = execute_git_command(base_path, &["worktree", "prune"]);
        if prune.success {
            let remaining = list_worktrees(base_path)?
                .into_iter()
                .any(|item| normalize_path_for_compare(&item.path) == worktree_normalized);
            if !remaining {
                return Ok(());
            }
        }
    }

    Err(normalize_worktree_remove_error(&result.output, force))
}

fn resolve_default_worktree_path(base_path: &str, branch: &str) -> Result<String, String> {
    let home = resolve_home_dir().ok_or_else(|| "无法解析用户主目录".to_string())?;
    let repo_name = resolve_repo_name(base_path);
    let normalized_branch = branch
        .replace('\\', "/")
        .split('/')
        .filter(|segment| !segment.trim().is_empty())
        .collect::<Vec<_>>()
        .join("/");

    if normalized_branch.is_empty() {
        return Err("分支名不能为空".to_string());
    }

    Ok(home
        .join(".devhaven")
        .join("worktrees")
        .join(repo_name)
        .join(normalized_branch)
        .to_string_lossy()
        .to_string())
}

fn has_origin_remote(base_path: &str) -> bool {
    let result = execute_git_command(base_path, &["remote", "get-url", "origin"]);
    result.success
}

enum RemoteBranchCheck {
    Exists,
    NotFound,
    Error(String),
}

fn branch_exists_on_remote(base_path: &str, branch: &str) -> RemoteBranchCheck {
    let output = Command::new(resolve_git_executable())
        .args(["ls-remote", "--exit-code", "--heads", "origin", branch])
        .current_dir(base_path)
        .output();

    match output {
        Ok(output) => {
            if output.status.success() {
                return RemoteBranchCheck::Exists;
            }

            if output.status.code() == Some(2) {
                return RemoteBranchCheck::NotFound;
            }

            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let message = if stderr.is_empty() {
                stdout
            } else if stdout.is_empty() {
                stderr
            } else {
                format!("{stdout}\n{stderr}").trim().to_string()
            };
            RemoteBranchCheck::Error(message)
        }
        Err(err) => RemoteBranchCheck::Error(format!("执行命令失败: {err}")),
    }
}

fn fetch_origin_branch(base_path: &str, branch: &str) -> Result<(), String> {
    let result = execute_git_command(base_path, &["fetch", "origin", branch]);
    if result.success {
        return Ok(());
    }
    Err(result.output)
}

fn ref_exists_locally(base_path: &str, reference: &str) -> bool {
    let reference = reference.trim();
    if reference.is_empty() {
        return false;
    }
    let commit_ref = format!("{reference}^{{commit}}");
    let output = Command::new(resolve_git_executable())
        .args(["rev-parse", "--verify", "--quiet", commit_ref.as_str()])
        .current_dir(base_path)
        .output();
    match output {
        Ok(output) => output.status.success(),
        Err(_) => false,
    }
}

fn resolve_repo_name(base_path: &str) -> String {
    let fallback = "repository".to_string();
    let raw = Path::new(base_path)
        .file_name()
        .and_then(|value| value.to_str())
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToString::to_string)
        .unwrap_or_else(|| fallback.clone());

    let sanitized: String = raw
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.') {
                ch
            } else {
                '-'
            }
        })
        .collect();

    let result = sanitized.trim_matches(['-', '.', '_']);
    if result.is_empty() {
        fallback
    } else {
        result.to_string()
    }
}

fn resolve_home_dir() -> Option<PathBuf> {
    if let Some(home) = std::env::var_os("HOME") {
        if !home.is_empty() {
            return Some(PathBuf::from(home));
        }
    }

    if cfg!(windows) {
        if let Some(profile) = std::env::var_os("USERPROFILE") {
            if !profile.is_empty() {
                return Some(PathBuf::from(profile));
            }
        }
        match (std::env::var_os("HOMEDRIVE"), std::env::var_os("HOMEPATH")) {
            (Some(drive), Some(path)) if !drive.is_empty() && !path.is_empty() => {
                let mut result = PathBuf::from(drive);
                result.push(path);
                return Some(result);
            }
            _ => {}
        }
    }

    None
}

fn parse_worktree_list_output(base_path: &str, output: &str) -> Vec<GitWorktreeListItem> {
    let base_normalized = normalize_path_for_compare(base_path);
    let mut items: Vec<GitWorktreeListItem> = Vec::new();

    let mut current_path: Option<String> = None;
    let mut current_branch: Option<String> = None;
    let mut current_detached = false;

    let mut flush_current =
        |path: &mut Option<String>, branch: &mut Option<String>, detached: &mut bool| {
            let Some(path_value) = path.take() else {
                *branch = None;
                *detached = false;
                return;
            };

            let branch_value = branch.take().unwrap_or_default();
            let normalized_path = normalize_path_for_compare(&path_value);
            let is_base = normalized_path == base_normalized;

            if !is_base && !*detached && !branch_value.is_empty() {
                items.push(GitWorktreeListItem {
                    path: path_value,
                    branch: branch_value,
                });
            }
            *detached = false;
        };

    for raw_line in output.lines() {
        let line = raw_line.trim();

        if line.is_empty() {
            flush_current(
                &mut current_path,
                &mut current_branch,
                &mut current_detached,
            );
            continue;
        }

        if let Some(path_value) = line.strip_prefix("worktree ") {
            flush_current(
                &mut current_path,
                &mut current_branch,
                &mut current_detached,
            );
            current_path = Some(path_value.trim().to_string());
            continue;
        }

        if let Some(branch_ref) = line.strip_prefix("branch ") {
            let branch_name = branch_ref
                .trim()
                .strip_prefix("refs/heads/")
                .unwrap_or(branch_ref.trim());
            current_branch = Some(branch_name.to_string());
            continue;
        }

        if line == "detached" {
            current_detached = true;
        }
    }

    flush_current(
        &mut current_path,
        &mut current_branch,
        &mut current_detached,
    );

    items.sort_by(|left, right| left.path.cmp(&right.path));
    items
}

fn normalize_path_for_compare(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        return String::new();
    }

    // 优先用 canonicalize 消除软链接/大小写差异（例如 macOS 的 /var -> /private/var），避免比较失败。
    let mut normalized = trimmed.replace('\\', "/").trim_end_matches('/').to_string();
    if let Ok(canonical) = std::fs::canonicalize(&normalized) {
        normalized = canonical
            .to_string_lossy()
            .replace('\\', "/")
            .trim_end_matches('/')
            .to_string();
    }
    if cfg!(windows) {
        normalized.to_ascii_lowercase()
    } else {
        normalized
    }
}

fn normalize_worktree_add_error(raw: &str, create_branch: bool) -> String {
    let lower = raw.to_ascii_lowercase();

    if lower.contains("already checked out") || lower.contains("already used by worktree") {
        return "该分支已在其他 worktree 检出，请切换分支或先移除旧 worktree".to_string();
    }

    if create_branch && lower.contains("already exists") && lower.contains("branch") {
        return "分支已存在，请改用“已有分支”模式或更换分支名".to_string();
    }

    if lower.contains("already exists") {
        return "目标目录已存在，无法创建 worktree".to_string();
    }

    if lower.contains("not a git repository") {
        return "不是 Git 仓库".to_string();
    }

    if lower.contains("invalid reference")
        || lower.contains("unknown revision")
        || lower.contains("not a valid object name")
        || lower.contains("pathspec")
    {
        return "分支不存在或不可用，请检查分支名称".to_string();
    }

    raw.to_string()
}

fn normalize_worktree_remove_error(raw: &str, force: bool) -> String {
    let lower = raw.to_ascii_lowercase();

    if lower.contains("not a git repository") {
        return "不是 Git 仓库".to_string();
    }

    if lower.contains("not a working tree") {
        return "worktree 不存在或已移除".to_string();
    }

    if lower.contains("contains modified or untracked files")
        || lower.contains("cannot remove a dirty worktree")
        || (lower.contains("dirty") && lower.contains("worktree"))
    {
        if force {
            return "强制删除失败：worktree 可能被进程占用或被锁定，请先关闭相关终端/编辑器后重试"
                .to_string();
        }
        return "该 worktree 存在未提交修改，无法删除。请先提交/清理，或使用“强制删除”".to_string();
    }

    if lower.contains("locked") && lower.contains("worktree") {
        return "worktree 已锁定，无法删除。可先执行 git worktree unlock 后重试".to_string();
    }

    raw.to_string()
}

fn normalize_delete_branch_error(raw: &str, force: bool) -> String {
    let lower = raw.to_ascii_lowercase();

    if lower.contains("not a git repository") {
        return "不是 Git 仓库".to_string();
    }

    if lower.contains("not found") && lower.contains("branch") {
        return "分支不存在或已删除".to_string();
    }

    if lower.contains("checked out") {
        return "分支正在当前仓库或其他 worktree 中使用，无法删除".to_string();
    }

    if !force && lower.contains("not fully merged") {
        return "分支包含未合并提交，无法删除。请先合并后重试".to_string();
    }

    raw.to_string()
}

// 执行 Git 命令并统一输出格式。
fn execute_git_command(path: &str, args: &[&str]) -> GitCommandResult {
    let output = Command::new(resolve_git_executable())
        .args(args)
        .current_dir(path)
        .output();

    match output {
        Ok(output) => {
            let success = output.status.success();
            let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
            let combined = if success {
                stdout
            } else if stderr.is_empty() {
                stdout
            } else {
                format!("{stdout}\n{stderr}").trim().to_string()
            };
            GitCommandResult {
                success,
                output: combined,
            }
        }
        Err(err) => GitCommandResult {
            success: false,
            output: format!("执行命令失败: {err}"),
        },
    }
}

fn is_git_show_not_found(stderr: &str) -> bool {
    let msg = stderr.to_ascii_lowercase();
    msg.contains("does not exist")
        || msg.contains("not in the index")
        || msg.contains("exists on disk, but not in the index")
        || msg.contains("invalid object name")
        || msg.contains("ambiguous argument")
}

fn looks_binary(bytes: &[u8]) -> bool {
    bytes.iter().take(8000).any(|b| *b == 0)
}

fn bytes_to_text(bytes: Option<Vec<u8>>) -> Result<String, String> {
    match bytes {
        None => Ok(String::new()),
        Some(bytes) => {
            if looks_binary(&bytes) {
                return Err("检测到二进制文件，无法以文本对比展示。".to_string());
            }
            Ok(String::from_utf8_lossy(&bytes).to_string())
        }
    }
}

fn read_git_object_optional(
    base_path: &str,
    spec: &str,
    max_bytes: usize,
) -> Result<(Option<Vec<u8>>, bool), String> {
    let output = Command::new(resolve_git_executable())
        .args(["show", spec])
        .current_dir(base_path)
        .output()
        .map_err(|err| format!("执行命令失败: {err}"))?;

    if output.status.success() {
        let (bytes, truncated) = truncate_bytes(output.stdout, max_bytes);
        return Ok((Some(bytes), truncated));
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if is_git_show_not_found(&stderr) {
        return Ok((None, false));
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if stderr.is_empty() {
        Err(stdout)
    } else if stdout.is_empty() {
        Err(stderr)
    } else {
        Err(format!("{stdout}\n{stderr}").trim().to_string())
    }
}

fn read_worktree_file_optional(
    base_path: &str,
    relative_path: &str,
    max_bytes: usize,
) -> Result<(Option<Vec<u8>>, bool), String> {
    use std::io::Read;

    let path = Path::new(base_path).join(relative_path);
    let file = match fs::File::open(&path) {
        Ok(file) => file,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok((None, false)),
        Err(err) => return Err(format!("读取文件失败: {err}")),
    };

    let mut buf: Vec<u8> = Vec::new();
    let mut handle = file.take((max_bytes as u64) + 1);
    handle
        .read_to_end(&mut buf)
        .map_err(|err| format!("读取文件失败: {err}"))?;

    let truncated = buf.len() > max_bytes;
    if truncated {
        buf.truncate(max_bytes);
    }
    Ok((Some(buf), truncated))
}

fn truncate_bytes(mut bytes: Vec<u8>, max_bytes: usize) -> (Vec<u8>, bool) {
    if bytes.len() <= max_bytes {
        return (bytes, false);
    }
    bytes.truncate(max_bytes);
    (bytes, true)
}

fn resolve_git_executable() -> &'static str {
    static BIN: OnceLock<String> = OnceLock::new();
    BIN.get_or_init(|| {
        if Path::new("/usr/bin/git").exists() {
            "/usr/bin/git".to_string()
        } else {
            "git".to_string()
        }
    })
    .as_str()
}

fn run_git_with_paths<const N: usize>(
    base_path: &str,
    prefix_args: [&str; N],
    relative_paths: &[String],
) -> Result<(), String> {
    if !is_git_repo(base_path) {
        return Err("不是 Git 仓库".to_string());
    }
    if relative_paths.is_empty() {
        return Ok(());
    }

    let output = Command::new(resolve_git_executable())
        .args(prefix_args)
        .args(relative_paths)
        .current_dir(base_path)
        .output()
        .map_err(|err| format!("执行命令失败: {err}"))?;

    if output.status.success() {
        return Ok(());
    }

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if stderr.is_empty() {
        Err(stdout)
    } else if stdout.is_empty() {
        Err(stderr)
    } else {
        Err(format!("{stdout}\n{stderr}").trim().to_string())
    }
}

fn parse_porcelain_v2_status(output: &str) -> Result<GitRepoStatus, String> {
    let mut branch = String::new();
    let mut upstream: Option<String> = None;
    let mut ahead: i32 = 0;
    let mut behind: i32 = 0;
    let mut staged: Vec<GitChangedFile> = Vec::new();
    let mut unstaged: Vec<GitChangedFile> = Vec::new();
    let mut untracked: Vec<GitChangedFile> = Vec::new();

    let parts: Vec<&str> = output.split('\0').collect();
    let mut index = 0usize;
    while index < parts.len() {
        let record = parts[index];
        if record.is_empty() {
            index += 1;
            continue;
        }

        if let Some(rest) = record.strip_prefix("# ") {
            if let Some(value) = rest.strip_prefix("branch.head ") {
                branch = value.trim().to_string();
            } else if let Some(value) = rest.strip_prefix("branch.upstream ") {
                let value = value.trim();
                if !value.is_empty() {
                    upstream = Some(value.to_string());
                }
            } else if let Some(value) = rest.strip_prefix("branch.ab ") {
                // Format: +A -B
                let mut iter = value.split_whitespace();
                let ahead_token = iter.next().unwrap_or("");
                let behind_token = iter.next().unwrap_or("");
                ahead = ahead_token
                    .trim_start_matches('+')
                    .parse::<i32>()
                    .unwrap_or(0);
                behind = behind_token
                    .trim_start_matches('-')
                    .parse::<i32>()
                    .unwrap_or(0);
            }
            index += 1;
            continue;
        }

        let record_type = record.chars().next().unwrap_or(' ');
        match record_type {
            '1' => {
                parse_change_record(record, 8, None, &mut staged, &mut unstaged);
            }
            '2' => {
                let old_path = parts.get(index + 1).map(|value| (*value).to_string());
                parse_change_record(record, 9, old_path, &mut staged, &mut unstaged);
                // Record type 2 uses an extra NUL-delimited pathname
                index += 1;
            }
            '?' => {
                // Format: "? <path>"
                if let Some(path) = record.strip_prefix("? ") {
                    let path = path.trim();
                    if !path.is_empty() {
                        untracked.push(GitChangedFile {
                            path: path.to_string(),
                            old_path: None,
                            status: GitFileStatus::Untracked,
                        });
                    }
                }
            }
            // ignore ignored files: "! <path>"
            '!' => {}
            _ => {
                // Unrecognized record type; ignore to avoid breaking the UI.
            }
        }

        index += 1;
    }

    if branch.is_empty() {
        branch = "HEAD".to_string();
    }

    Ok(GitRepoStatus {
        branch,
        upstream,
        ahead,
        behind,
        staged,
        unstaged,
        untracked,
    })
}

fn parse_change_record(
    record: &str,
    path_token_start_index: usize,
    old_path: Option<String>,
    staged: &mut Vec<GitChangedFile>,
    unstaged: &mut Vec<GitChangedFile>,
) {
    let tokens: Vec<&str> = record.split_whitespace().collect();
    if tokens.len() < 2 {
        return;
    }
    let xy = tokens[1];
    let x = xy.chars().next().unwrap_or('.');
    let y = xy.chars().nth(1).unwrap_or('.');

    if tokens.len() <= path_token_start_index {
        return;
    }
    let path_tokens = &tokens[path_token_start_index..];
    let path = path_tokens.join(" ").trim().to_string();
    if path.is_empty() {
        return;
    }

    if x != '.' && x != ' ' {
        staged.push(GitChangedFile {
            path: path.clone(),
            old_path: old_path.clone(),
            status: map_git_status_char(x),
        });
    }

    if y != '.' && y != ' ' {
        unstaged.push(GitChangedFile {
            path,
            old_path,
            status: map_git_status_char(y),
        });
    }
}

fn map_git_status_char(value: char) -> GitFileStatus {
    match value {
        'A' => GitFileStatus::Added,
        'M' => GitFileStatus::Modified,
        'D' => GitFileStatus::Deleted,
        'R' => GitFileStatus::Renamed,
        'C' => GitFileStatus::Copied,
        '?' => GitFileStatus::Untracked,
        _ => GitFileStatus::Modified,
    }
}

fn resolve_default_branch(branches: &[String], base_path: &str) -> Option<String> {
    let symbolic = execute_git_command(base_path, &["symbolic-ref", "refs/remotes/origin/HEAD"]);
    if symbolic.success {
        if let Some(name) = symbolic.output.split('/').last() {
            let name = name.trim();
            if branches.iter().any(|branch| branch == name) {
                return Some(name.to_string());
            }
        }
    }

    if branches.iter().any(|branch| branch == "main") {
        return Some("main".to_string());
    }
    if branches.iter().any(|branch| branch == "master") {
        return Some("master".to_string());
    }

    None
}

struct GitCommandResult {
    success: bool,
    output: String,
}

#[cfg(test)]
mod tests {
    use super::{
        add_worktree, delete_branch, is_git_repo, list_worktrees, parse_worktree_list_output,
        remove_worktree, resolve_create_branch_start_point, resolve_git_executable,
    };
    use std::fs;
    use std::path::Path;
    use std::process::Command;

    fn git(path: &Path, args: &[&str]) -> Result<String, String> {
        let output = Command::new(resolve_git_executable())
            .args(args)
            .current_dir(path)
            .output()
            .map_err(|err| format!("执行 git 失败: {err}"))?;

        if output.status.success() {
            return Ok(String::from_utf8_lossy(&output.stdout).trim().to_string());
        }

        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            Err(stdout)
        } else if stdout.is_empty() {
            Err(stderr)
        } else {
            Err(format!("{stdout}\n{stderr}").trim().to_string())
        }
    }

    #[test]
    fn add_worktree_creates_directory_with_new_branch() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.with_file_name(format!(
            "{}-wt",
            root.file_name().unwrap().to_string_lossy()
        ));

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let root_str = root.to_string_lossy().to_string();
        let worktree_str = worktree.to_string_lossy().to_string();
        let result = add_worktree(
            &root_str,
            Some(&worktree_str),
            "feature/worktree",
            true,
            None,
        )
        .expect("create worktree");

        assert_eq!(result.path, worktree_str);
        assert_eq!(result.branch, "feature/worktree");
        assert!(worktree.join(".git").exists());
        assert!(is_git_repo(&worktree.to_string_lossy()));
        assert_eq!(
            git(&worktree, &["branch", "--show-current"]).expect("read current branch"),
            "feature/worktree"
        );

        let _ = fs::remove_dir_all(&worktree);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn add_worktree_supports_explicit_start_point() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.with_file_name(format!(
            "{}-wt-explicit",
            root.file_name().unwrap().to_string_lossy()
        ));

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "main\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let default_branch = git(&root, &["branch", "--show-current"]).expect("default branch");
        git(&root, &["checkout", "-b", "develop"]).expect("create develop");
        fs::write(root.join("BASELINE.txt"), "develop\n").expect("write baseline marker");
        git(&root, &["add", "."]).expect("git add develop");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "develop baseline",
            ],
        )
        .expect("git commit develop");
        git(&root, &["checkout", &default_branch]).expect("checkout default branch");

        let root_str = root.to_string_lossy().to_string();
        let worktree_str = worktree.to_string_lossy().to_string();
        add_worktree(
            &root_str,
            Some(&worktree_str),
            "feature/from-develop",
            true,
            Some("develop"),
        )
        .expect("create worktree with explicit start point");

        assert_eq!(
            git(
                &worktree,
                &["merge-base", "--is-ancestor", "develop", "HEAD"]
            ),
            Ok(String::new())
        );
        assert!(worktree.join("BASELINE.txt").exists());

        let _ = fs::remove_dir_all(&worktree);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn resolve_create_branch_start_point_prefers_origin_ref() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let remote = root.with_file_name(format!(
            "{}-remote.git",
            root.file_name().unwrap().to_string_lossy()
        ));

        fs::create_dir_all(&root).expect("create root");
        Command::new(resolve_git_executable())
            .args(["init", "--bare", remote.to_string_lossy().as_ref()])
            .output()
            .expect("init bare remote");

        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let default_branch = git(&root, &["branch", "--show-current"]).expect("default branch");
        git(
            &root,
            &["remote", "add", "origin", remote.to_string_lossy().as_ref()],
        )
        .expect("add origin");
        git(&root, &["checkout", "-b", "develop"]).expect("create develop");
        fs::write(root.join("DEVELOP.md"), "develop\n").expect("write develop marker");
        git(&root, &["add", "."]).expect("git add develop");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "develop",
            ],
        )
        .expect("git commit develop");
        git(&root, &["push", "-u", "origin", "develop"]).expect("push develop");
        git(&root, &["checkout", &default_branch]).expect("checkout default branch");

        let start_point =
            resolve_create_branch_start_point(root.to_string_lossy().as_ref(), "develop")
                .expect("resolve start point");
        assert_eq!(start_point, "origin/develop");

        let _ = fs::remove_dir_all(&root);
        let _ = fs::remove_dir_all(&remote);
    }

    #[test]
    fn resolve_create_branch_start_point_returns_error_when_branch_missing() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let error = resolve_create_branch_start_point(root.to_string_lossy().as_ref(), "develop")
            .expect_err("missing base branch should fail");
        assert!(error.contains("基线分支不可用"));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn remove_worktree_removes_directory_and_unregisters() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.with_file_name(format!(
            "{}-wt",
            root.file_name().unwrap().to_string_lossy()
        ));

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let root_str = root.to_string_lossy().to_string();
        let worktree_str = worktree.to_string_lossy().to_string();
        add_worktree(&root_str, Some(&worktree_str), "feature/remove", true, None)
            .expect("create worktree");

        remove_worktree(&root_str, &worktree_str, false).expect("remove worktree");

        assert!(!worktree.exists());
        assert!(
            list_worktrees(&root_str)
                .expect("list worktrees")
                .is_empty()
        );

        let _ = fs::remove_dir_all(&worktree);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn delete_branch_removes_local_branch() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");

        let default_branch = git(&root, &["branch", "--show-current"]).expect("default branch");
        git(&root, &["checkout", "-b", "feature/delete-me"]).expect("create feature branch");
        git(&root, &["checkout", &default_branch]).expect("checkout default branch");

        let root_str = root.to_string_lossy().to_string();
        delete_branch(&root_str, "feature/delete-me", false).expect("delete branch");

        assert_eq!(
            git(&root, &["branch", "--list", "feature/delete-me"]).expect("list branch"),
            ""
        );

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn add_worktree_rejects_non_repo_path() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.join("worktree");
        let root_str = root.to_string_lossy().to_string();
        let worktree_str = worktree.to_string_lossy().to_string();

        fs::create_dir_all(&root).expect("create root");

        let err = add_worktree(&root_str, Some(&worktree_str), "feature/x", true, None)
            .expect_err("should reject non git repo");
        assert_eq!(err, "不是 Git 仓库");

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn add_worktree_rejects_existing_target_directory() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.join("worktree");
        let root_str = root.to_string_lossy().to_string();
        let worktree_str = worktree.to_string_lossy().to_string();

        fs::create_dir_all(&root).expect("create root");
        git(&root, &["init"]).expect("git init");
        fs::write(root.join("README.md"), "init\n").expect("write readme");
        git(&root, &["add", "."]).expect("git add");
        git(
            &root,
            &[
                "-c",
                "user.name=DevHaven",
                "-c",
                "user.email=devhaven@example.com",
                "commit",
                "-m",
                "init",
            ],
        )
        .expect("git commit");
        fs::create_dir_all(&worktree).expect("create existing worktree dir");

        let err = add_worktree(&root_str, Some(&worktree_str), "feature/x", true, None)
            .expect_err("should reject existing target");
        assert_eq!(err, "目标目录已存在，无法创建 worktree");

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn parse_worktree_list_output_filters_base_and_detached() {
        let output = r#"
worktree /repo/main
HEAD 111111
branch refs/heads/main

worktree /repo/feature-a
HEAD 222222
branch refs/heads/feature/a

worktree /repo/detached
HEAD 333333
detached
"#;

        let items = parse_worktree_list_output("/repo/main", output);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].path, "/repo/feature-a");
        assert_eq!(items[0].branch, "feature/a");
    }

    #[test]
    fn parse_worktree_list_output_accepts_branch_without_refs_prefix() {
        let output = r#"
worktree /repo/main
HEAD 111111
branch refs/heads/main

worktree /repo/release
HEAD 222222
branch release/1.0
"#;

        let items = parse_worktree_list_output("/repo/main", output);
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].path, "/repo/release");
        assert_eq!(items[0].branch, "release/1.0");
    }
}
