use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Mutex, OnceLock};

use rayon::prelude::*;

use crate::models::Project;
use crate::time_utils::{now_swift, system_time_to_swift, system_time_to_unix_seconds};

/// 递归扫描最大深度，防止栈溢出。
const MAX_SCAN_DEPTH: usize = 6;
/// GIT_INFO_CACHE 软上限：超过后触发一次裁剪。
const GIT_INFO_CACHE_MAX_SIZE: usize = 4_096;
/// 触发裁剪后优先回收到该水位，减少频繁触发。
const GIT_INFO_CACHE_PRUNE_TARGET_SIZE: usize = 3_072;

static GIT_INFO_CACHE: OnceLock<Mutex<HashMap<String, CachedGitInfo>>> = OnceLock::new();

/// 根据目录列表扫描可用项目路径（并行扫描多个工作目录）。
pub fn discover_projects(directories: &[String]) -> Vec<String> {
    let mut all_paths: Vec<String> = directories
        .par_iter()
        .flat_map(|directory| scan_directory_with_git(directory))
        .collect();
    all_paths.sort();
    all_paths.dedup();
    all_paths
}

/// 构建项目列表，复用已有数据并更新元信息（并行加载 Git 信息）。
pub fn build_projects(paths: &[String], existing: &[Project]) -> Vec<Project> {
    maybe_prune_git_info_cache(paths);

    let existing_by_path: HashMap<&str, &Project> = existing
        .iter()
        .map(|project| (project.path.as_str(), project))
        .collect();
    let projects: Vec<Project> = paths
        .par_iter()
        .filter_map(|path| create_project(path, &existing_by_path))
        .collect();

    // 构建过程中可能新增缓存项，收尾再做一次按当前输入路径优先的裁剪。
    maybe_prune_git_info_cache(paths);
    projects
}

// 扫描指定目录：收录根目录（若为 Git 仓库）、其直接子目录，以及并行深度扫描更深层的 Git 仓库。
fn scan_directory_with_git(path: &str) -> Vec<String> {
    let mut results = Vec::new();
    let root = Path::new(path);
    if !root.exists() {
        return results;
    }

    if is_git_repo(root) && !is_git_worktree(root) {
        if let Some(as_str) = root.to_str() {
            results.push(as_str.to_string());
        }
    }

    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(_) => return results,
    };

    let child_dirs: Vec<_> = entries
        .flatten()
        .filter(|entry| {
            let file_type = match entry.file_type() {
                Ok(ft) => ft,
                Err(_) => return false,
            };
            if file_type.is_symlink() || !file_type.is_dir() {
                return false;
            }
            !should_skip_direct_dir(&entry.file_name())
        })
        .collect();

    for entry in &child_dirs {
        let entry_path = entry.path();
        if let Some(as_str) = entry_path.to_str() {
            if !is_git_worktree(&entry_path) {
                results.push(as_str.to_string());
            }
        }
    }

    // 并行深度扫描嵌套 Git 仓库
    let nested: Vec<String> = child_dirs
        .par_iter()
        .flat_map(|entry| collect_git_repos(&entry.path(), 1))
        .collect();

    results.extend(nested);
    results
}

fn collect_git_repos(path: &Path, depth: usize) -> Vec<String> {
    if depth >= MAX_SCAN_DEPTH {
        return Vec::new();
    }

    if is_git_repo(path) {
        if !is_git_worktree(path) {
            if let Some(as_str) = path.to_str() {
                return vec![as_str.to_string()];
            }
        }
        return Vec::new();
    }

    let entries = match fs::read_dir(path) {
        Ok(entries) => entries,
        Err(_) => return Vec::new(),
    };

    let dirs: Vec<_> = entries
        .flatten()
        .filter(|entry| {
            let file_type = match entry.file_type() {
                Ok(ft) => ft,
                Err(_) => return false,
            };
            if file_type.is_symlink() || !file_type.is_dir() {
                return false;
            }
            !should_skip_recursive_dir(&entry.file_name())
        })
        .map(|entry| entry.path())
        .collect();

    dirs.par_iter()
        .flat_map(|dir| collect_git_repos(dir, depth + 1))
        .collect()
}

fn should_skip_direct_dir(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy();
    name.starts_with('.')
}

fn should_skip_recursive_dir(name: &std::ffi::OsStr) -> bool {
    let name = name.to_string_lossy();
    if name == ".git" {
        return true;
    }
    if name.starts_with('.') {
        return true;
    }
    matches!(name.as_ref(), "node_modules" | "target" | "dist" | "build")
}

#[cfg(test)]
mod tests {
    use super::{
        CachedGitInfo, GIT_INFO_CACHE_MAX_SIZE, GIT_INFO_CACHE_PRUNE_TARGET_SIZE, GitInfo,
        build_projects, load_git_info, prune_git_info_cache_entries, scan_directory_with_git,
    };
    use crate::time_utils::unix_to_swift;
    use std::collections::HashMap;
    use std::fs;
    use std::path::{Path, PathBuf};
    use std::process::Command;

    #[test]
    fn scan_directory_with_git_handles_root_and_nested_repos() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let sub_a = root.join("alpha");
        let sub_b = root.join("beta");
        let sub_c = root.join("gamma");
        let hidden = root.join(".hidden");
        let nested_repo = sub_a.join("project-x").join(".git");
        let nested_hidden_repo = hidden.join("project-y").join(".git");
        let nested_in_git = sub_b.join("ignored").join(".git");
        let worktree_dir = root.join("worktree-alpha");

        fs::create_dir_all(root.join(".git")).expect("create root git");
        fs::create_dir_all(&sub_a).expect("create alpha dir");
        fs::create_dir_all(sub_b.join(".git")).expect("create beta git");
        fs::create_dir_all(&sub_c).expect("create gamma dir");
        fs::create_dir_all(&hidden).expect("create hidden dir");
        fs::create_dir_all(&nested_repo).expect("create nested git");
        fs::create_dir_all(&nested_hidden_repo).expect("create hidden nested git");
        fs::create_dir_all(&nested_in_git).expect("create nested in git");
        fs::create_dir_all(&worktree_dir).expect("create worktree dir");
        fs::write(
            worktree_dir.join(".git"),
            format!(
                "gitdir: {}/.git/worktrees/worktree-alpha\n",
                root.to_string_lossy()
            ),
        )
        .expect("write worktree git file");

        let root_str = root.to_string_lossy().to_string();
        let results = scan_directory_with_git(&root_str);
        let result_paths: Vec<PathBuf> = results.into_iter().map(PathBuf::from).collect();

        assert!(result_paths.contains(&root));
        assert!(result_paths.contains(&sub_a));
        assert!(result_paths.contains(&sub_b));
        assert!(result_paths.contains(&sub_c));
        assert!(result_paths.contains(&sub_a.join("project-x")));
        assert!(!result_paths.contains(&worktree_dir));
        assert!(!result_paths.contains(&hidden));
        assert!(!result_paths.contains(&hidden.join("project-y")));
        assert!(!result_paths.contains(&sub_b.join("ignored")));

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn build_projects_skips_git_worktree_path() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        let worktree = root.join("worktree-demo");

        fs::create_dir_all(root.join(".git")).expect("create root git");
        fs::create_dir_all(&worktree).expect("create worktree dir");
        fs::write(
            worktree.join(".git"),
            format!(
                "gitdir: {}/.git/worktrees/worktree-demo\n",
                root.to_string_lossy()
            ),
        )
        .expect("write worktree git file");

        let paths = vec![worktree.to_string_lossy().to_string()];
        let projects = build_projects(&paths, &[]);
        assert!(projects.is_empty());

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn load_git_info_reads_commit_count_last_commit_and_message() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).expect("create test repo dir");
        init_git_repo(&root);

        fs::write(root.join("README.md"), "first\n").expect("write first file");
        run_git(&root, &["add", "README.md"]);
        run_git_with_dates(
            &root,
            &["commit", "-m", "first commit"],
            "1700000000 +0000",
            "1700000000 +0000",
        );

        fs::write(root.join("README.md"), "second\n").expect("update file");
        run_git(&root, &["add", "README.md"]);
        run_git_with_dates(
            &root,
            &["commit", "-m", "second commit"],
            "1700000100 +0000",
            "1700000100 +0000",
        );

        let info = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(info.commit_count, 2);
        assert_eq!(info.last_commit_message.as_deref(), Some("second commit"));
        let expected_last_commit = unix_to_swift(1700000100.0);
        assert!((info.last_commit - expected_last_commit).abs() < 1e-6);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn load_git_info_returns_zero_values_for_empty_repo() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).expect("create test repo dir");
        init_git_repo(&root);

        let info = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(info.commit_count, 0);
        assert_eq!(info.last_commit, unix_to_swift(0.0));
        assert_eq!(info.last_commit_message, None);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn load_git_info_recomputes_when_head_changes() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).expect("create test repo dir");
        init_git_repo(&root);

        fs::write(root.join("README.md"), "first\n").expect("write first file");
        run_git(&root, &["add", "README.md"]);
        run_git_with_dates(
            &root,
            &["commit", "-m", "first commit"],
            "1700000000 +0000",
            "1700000000 +0000",
        );

        let first = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(first.commit_count, 1);
        assert_eq!(first.last_commit_message.as_deref(), Some("first commit"));

        fs::write(root.join("README.md"), "second\n").expect("update file");
        run_git(&root, &["add", "README.md"]);
        run_git_with_dates(
            &root,
            &["commit", "-m", "second commit"],
            "1700000100 +0000",
            "1700000100 +0000",
        );

        let second = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(second.commit_count, 2);
        assert_eq!(second.last_commit_message.as_deref(), Some("second commit"));
        assert!(second.last_commit > first.last_commit);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn load_git_info_falls_back_when_repo_becomes_unavailable() {
        let root = std::env::temp_dir().join(format!("devhaven_test_{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&root).expect("create test repo dir");
        init_git_repo(&root);

        fs::write(root.join("README.md"), "first\n").expect("write first file");
        run_git(&root, &["add", "README.md"]);
        run_git_with_dates(
            &root,
            &["commit", "-m", "first commit"],
            "1700000000 +0000",
            "1700000000 +0000",
        );

        let info = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(info.commit_count, 1);

        fs::remove_dir_all(root.join(".git")).expect("remove git dir");

        let fallback = load_git_info(root.to_string_lossy().as_ref());
        assert_eq!(fallback.commit_count, 0);
        assert_eq!(fallback.last_commit, 0.0);
        assert_eq!(fallback.last_commit_message, None);

        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn prune_git_info_cache_prefers_paths_from_current_build() {
        let total_entries = GIT_INFO_CACHE_MAX_SIZE + 16;
        let preferred_keys = vec![
            "repo_0".to_string(),
            "repo_1".to_string(),
            "repo_2".to_string(),
        ];
        let mut cache = build_test_cache(total_entries);

        prune_git_info_cache_entries(&mut cache, &preferred_keys);

        assert_eq!(cache.len(), GIT_INFO_CACHE_PRUNE_TARGET_SIZE);
        for key in preferred_keys {
            assert!(
                cache.contains_key(&key),
                "preferred key should be kept: {key}"
            );
        }
    }

    #[test]
    fn prune_git_info_cache_enforces_hard_limit_when_all_entries_preferred() {
        let total_entries = GIT_INFO_CACHE_MAX_SIZE + 9;
        let preferred_keys: Vec<String> = (0..total_entries)
            .map(|index| format!("repo_{index}"))
            .collect();
        let mut cache = build_test_cache(total_entries);

        prune_git_info_cache_entries(&mut cache, &preferred_keys);

        assert_eq!(cache.len(), GIT_INFO_CACHE_MAX_SIZE);
    }

    fn build_test_cache(total_entries: usize) -> HashMap<String, CachedGitInfo> {
        let mut cache = HashMap::with_capacity(total_entries);
        for index in 0..total_entries {
            let key = format!("repo_{index}");
            cache.insert(key.clone(), mock_cached_git_info(index));
        }
        cache
    }

    fn mock_cached_git_info(index: usize) -> CachedGitInfo {
        CachedGitInfo {
            head_key: format!("hash:{index}"),
            git_info: GitInfo {
                commit_count: index as i64,
                last_commit: index as f64,
                last_commit_message: Some(format!("msg-{index}")),
            },
        }
    }

    fn init_git_repo(path: &Path) {
        run_git(path, &["init"]);
        run_git(path, &["config", "user.name", "DevHaven Test"]);
        run_git(path, &["config", "user.email", "devhaven-test@example.com"]);
    }

    fn run_git(path: &Path, args: &[&str]) {
        let output = Command::new("/usr/bin/git")
            .args(args)
            .current_dir(path)
            .output()
            .expect("run git command");
        assert!(
            output.status.success(),
            "git command failed: args={args:?}, stderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn run_git_with_dates(path: &Path, args: &[&str], author_date: &str, committer_date: &str) {
        let output = Command::new("/usr/bin/git")
            .args(args)
            .current_dir(path)
            .env("GIT_AUTHOR_DATE", author_date)
            .env("GIT_COMMITTER_DATE", committer_date)
            .output()
            .expect("run git command with dates");
        assert!(
            output.status.success(),
            "git command failed: args={args:?}, stderr={}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
}

// 创建单个项目模型，必要时复用已存在的配置。
fn create_project(path: &str, existing_by_path: &HashMap<&str, &Project>) -> Option<Project> {
    if is_git_worktree(Path::new(path)) {
        return None;
    }

    let metadata = fs::metadata(path).ok()?;
    if !metadata.is_dir() {
        return None;
    }

    let name = Path::new(path)
        .file_name()
        .and_then(|os| os.to_str())
        .unwrap_or(path)
        .to_string();

    let mtime = metadata
        .modified()
        .map(system_time_to_swift)
        .unwrap_or_else(|_| now_swift());

    let unix_mtime = metadata
        .modified()
        .map(system_time_to_unix_seconds)
        .unwrap_or(0.0);
    let size = metadata.len() as i64;
    let checksum = format!("{}_{}", unix_mtime, size);

    let git_info = load_git_info(path);

    if let Some(existing) = existing_by_path.get(path) {
        return Some(Project {
            id: existing.id.clone(),
            name,
            path: path.to_string(),
            tags: existing.tags.clone(),
            scripts: existing.scripts.clone(),
            worktrees: existing.worktrees.clone(),
            mtime,
            size,
            checksum,
            git_commits: git_info.commit_count,
            git_last_commit: git_info.last_commit,
            git_last_commit_message: git_info.last_commit_message.clone(),
            git_daily: existing.git_daily.clone(),
            created: existing.created,
            checked: now_swift(),
        });
    }

    Some(Project {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        path: path.to_string(),
        tags: Vec::new(),
        scripts: Vec::new(),
        worktrees: Vec::new(),
        mtime,
        size,
        checksum,
        git_commits: git_info.commit_count,
        git_last_commit: git_info.last_commit,
        git_last_commit_message: git_info.last_commit_message,
        git_daily: None,
        created: now_swift(),
        checked: now_swift(),
    })
}

#[derive(Clone)]
struct GitInfo {
    commit_count: i64,
    last_commit: f64,
    last_commit_message: Option<String>,
}

struct CachedGitInfo {
    head_key: String,
    git_info: GitInfo,
}

fn git_info_cache() -> &'static Mutex<HashMap<String, CachedGitInfo>> {
    GIT_INFO_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn maybe_prune_git_info_cache(preferred_paths: &[String]) {
    let mut cache = match git_info_cache().lock() {
        Ok(value) => value,
        Err(poisoned) => poisoned.into_inner(),
    };

    if cache.len() <= GIT_INFO_CACHE_MAX_SIZE {
        return;
    }

    prune_git_info_cache_entries(&mut cache, preferred_paths);
}

fn prune_git_info_cache_entries(
    cache: &mut HashMap<String, CachedGitInfo>,
    preferred_paths: &[String],
) {
    if cache.len() <= GIT_INFO_CACHE_MAX_SIZE {
        return;
    }

    let preferred_set: HashSet<&str> = preferred_paths.iter().map(String::as_str).collect();
    let remove_to_target = cache.len().saturating_sub(GIT_INFO_CACHE_PRUNE_TARGET_SIZE);

    if remove_to_target > 0 {
        let removable_non_preferred: Vec<String> = cache
            .keys()
            .filter(|path| !preferred_set.contains(path.as_str()))
            .take(remove_to_target)
            .cloned()
            .collect();
        for key in removable_non_preferred {
            cache.remove(&key);
        }
    }

    if cache.len() <= GIT_INFO_CACHE_MAX_SIZE {
        return;
    }

    // 极端情况下（例如当前输入 paths 覆盖几乎全部缓存）依然强制回收到上限，防止缓存无界增长。
    let overflow = cache.len() - GIT_INFO_CACHE_MAX_SIZE;
    let removable_non_preferred: Vec<String> = cache
        .keys()
        .filter(|path| !preferred_set.contains(path.as_str()))
        .take(overflow)
        .cloned()
        .collect();
    let removed_non_preferred = removable_non_preferred.len();
    for key in removable_non_preferred {
        cache.remove(&key);
    }

    if removed_non_preferred >= overflow || cache.len() <= GIT_INFO_CACHE_MAX_SIZE {
        return;
    }

    let still_overflow = cache.len() - GIT_INFO_CACHE_MAX_SIZE;
    let fallback_keys: Vec<String> = cache.keys().take(still_overflow).cloned().collect();
    for key in fallback_keys {
        cache.remove(&key);
    }
}

fn non_repo_git_info() -> GitInfo {
    GitInfo {
        commit_count: 0,
        last_commit: 0.0,
        last_commit_message: None,
    }
}

fn zero_commit_git_info() -> GitInfo {
    GitInfo {
        commit_count: 0,
        last_commit: crate::time_utils::unix_to_swift(0.0),
        last_commit_message: None,
    }
}

// 读取 Git 信息（提交次数、最后提交时间与最后提交摘要）。
fn load_git_info(path: &str) -> GitInfo {
    let git_dir = Path::new(path).join(".git");
    if !git_dir.exists() {
        remove_cached_git_info(path);
        return non_repo_git_info();
    }

    let head_key = match resolve_head_cache_key(path) {
        Some(value) => value,
        None => {
            remove_cached_git_info(path);
            return zero_commit_git_info();
        }
    };

    if let Some(cached) = get_cached_git_info(path, &head_key) {
        return cached;
    }

    if head_key.starts_with("unborn:") {
        let info = zero_commit_git_info();
        cache_git_info(path, head_key, info.clone());
        return info;
    }

    let commit_count = run_git_command(path, &["rev-list", "--count", "HEAD"])
        .and_then(|output| output.trim().parse::<i64>().ok())
        .unwrap_or(0);

    // 将最后提交时间与摘要合并为一次 git 调用，减少进程开销。
    let (last_commit, last_commit_message) =
        run_git_command(path, &["log", "--format=%ct%x1f%s", "-n", "1"])
            .map(|output| parse_last_commit_log_output(&output))
            .unwrap_or((0.0, None));

    let info = GitInfo {
        commit_count,
        last_commit: crate::time_utils::unix_to_swift(last_commit),
        last_commit_message,
    };
    cache_git_info(path, head_key, info.clone());
    info
}

fn resolve_head_cache_key(path: &str) -> Option<String> {
    let head = run_git_command(path, &["rev-parse", "--verify", "HEAD"])
        .map(|output| output.trim().to_string())
        .filter(|output| !output.is_empty());
    if let Some(value) = head {
        return Some(format!("hash:{value}"));
    }

    let head_content = read_head_file(path)?;
    Some(format!("unborn:{head_content}"))
}

fn read_head_file(path: &str) -> Option<String> {
    let git_dir = resolve_repo_git_dir(Path::new(path))?;
    let head_path = git_dir.join("HEAD");
    fs::read_to_string(head_path)
        .ok()
        .map(|content| content.trim().to_string())
        .filter(|content| !content.is_empty())
}

fn resolve_repo_git_dir(path: &Path) -> Option<PathBuf> {
    let git_path = path.join(".git");
    if git_path.is_dir() {
        return Some(git_path);
    }
    if git_path.is_file() {
        return resolve_gitdir_from_file(&git_path);
    }
    None
}

fn get_cached_git_info(path: &str, head_key: &str) -> Option<GitInfo> {
    let cache = match git_info_cache().lock() {
        Ok(value) => value,
        Err(poisoned) => poisoned.into_inner(),
    };

    let entry = cache.get(path)?;
    if entry.head_key != head_key {
        return None;
    }
    Some(entry.git_info.clone())
}

fn cache_git_info(path: &str, head_key: String, git_info: GitInfo) {
    let mut cache = match git_info_cache().lock() {
        Ok(value) => value,
        Err(poisoned) => poisoned.into_inner(),
    };
    cache.insert(path.to_string(), CachedGitInfo { head_key, git_info });
}

fn remove_cached_git_info(path: &str) {
    let mut cache = match git_info_cache().lock() {
        Ok(value) => value,
        Err(poisoned) => poisoned.into_inner(),
    };
    cache.remove(path);
}

fn parse_last_commit_log_output(output: &str) -> (f64, Option<String>) {
    let trimmed = output.trim();
    if trimmed.is_empty() {
        return (0.0, None);
    }

    let mut parts = trimmed.splitn(2, '\u{1f}');
    let last_commit = parts
        .next()
        .and_then(|value| value.trim().parse::<f64>().ok())
        .unwrap_or(0.0);
    let last_commit_message = parts
        .next()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(str::to_string);

    (last_commit, last_commit_message)
}

fn is_git_repo(path: &Path) -> bool {
    path.join(".git").exists()
}

fn is_git_worktree(path: &Path) -> bool {
    let git_path = path.join(".git");
    if !git_path.exists() || !git_path.is_file() {
        return false;
    }

    let gitdir_path = match resolve_gitdir_from_file(&git_path) {
        Some(value) => value,
        None => return false,
    };

    gitdir_path
        .components()
        .any(|component| component.as_os_str() == "worktrees")
}

fn resolve_gitdir_from_file(git_file_path: &Path) -> Option<PathBuf> {
    let content = fs::read_to_string(git_file_path).ok()?;
    let line = content.lines().next()?.trim();

    let raw_path = if let Some(value) = line.strip_prefix("gitdir:") {
        value.trim()
    } else if let Some(value) = line.strip_prefix("gitdir: ") {
        value.trim()
    } else {
        return None;
    };

    if raw_path.is_empty() {
        return None;
    }

    let parsed = PathBuf::from(raw_path);
    if parsed.is_absolute() {
        Some(parsed)
    } else {
        git_file_path.parent().map(|parent| parent.join(parsed))
    }
}

// 执行 Git 命令并返回输出内容。
fn run_git_command(path: &str, args: &[&str]) -> Option<String> {
    let output = Command::new("/usr/bin/git")
        .args(args)
        .current_dir(path)
        .output()
        .ok()?;

    if !output.status.success() {
        return None;
    }

    String::from_utf8(output.stdout).ok()
}
