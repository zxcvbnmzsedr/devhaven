use std::collections::{BTreeMap, BTreeSet, HashMap};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use uuid::Uuid;

#[cfg(unix)]
use std::os::unix::fs as unix_fs;
#[cfg(windows)]
use std::os::windows::fs as windows_fs;

use crate::models::{
    GlobalSkillAgent, GlobalSkillInstallRequest, GlobalSkillInstallResult, GlobalSkillSummary,
    GlobalSkillUninstallRequest, GlobalSkillsSnapshot,
};

const SKILL_SOURCE_SEARCH_DIRS: &[&str] = &[
    "skills",
    "skills/.curated",
    "skills/.experimental",
    "skills/.system",
    ".agents/skills",
    ".agent/skills",
    ".augment/skills",
    ".claude/skills",
    ".cline/skills",
    ".codebuddy/skills",
    ".commandcode/skills",
    ".continue/skills",
    ".goose/skills",
];

#[derive(Debug, Clone)]
struct SkillAgentScope {
    id: &'static str,
    label: &'static str,
    path: PathBuf,
}

#[derive(Debug, Clone)]
struct SkillScanScope {
    path: PathBuf,
    agent: Option<SkillAgentScope>,
}

#[derive(Debug, Clone)]
struct SkillAggregate {
    name: String,
    description: String,
    canonical_path: String,
    paths: BTreeSet<String>,
    agents: BTreeMap<String, String>,
}

#[derive(Debug, Clone)]
struct ParsedSkillFrontmatter {
    name: String,
    description: String,
}

#[derive(Debug, Clone)]
struct SourceSkill {
    install_name: String,
    display_name: String,
    description: String,
    path: PathBuf,
}

struct TempDirGuard {
    path: Option<PathBuf>,
}

impl TempDirGuard {
    fn none() -> Self {
        Self { path: None }
    }

    fn with_path(path: PathBuf) -> Self {
        Self { path: Some(path) }
    }
}

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        if let Some(path) = &self.path {
            let _ = fs::remove_dir_all(path);
        }
    }
}

pub fn list_global_skills() -> Result<GlobalSkillsSnapshot, String> {
    let home_dir = resolve_home_dir()?;
    let agent_scopes = build_agent_scopes(&home_dir);
    let scopes = build_global_scan_scopes(&home_dir, &agent_scopes);

    let mut aggregated = HashMap::<String, SkillAggregate>::new();
    for scope in scopes {
        collect_scope_skills(&scope, &mut aggregated);
    }

    let mut skills: Vec<GlobalSkillSummary> = aggregated
        .into_values()
        .map(|item| GlobalSkillSummary {
            name: item.name,
            description: item.description,
            canonical_path: item.canonical_path,
            paths: item.paths.into_iter().collect(),
            agents: item
                .agents
                .into_iter()
                .map(|(id, label)| GlobalSkillAgent { id, label })
                .collect(),
        })
        .collect();

    skills.sort_by(|left, right| {
        left.name
            .to_lowercase()
            .cmp(&right.name.to_lowercase())
            .then(left.name.cmp(&right.name))
    });

    let agents = agent_scopes
        .into_iter()
        .map(|agent| GlobalSkillAgent {
            id: agent.id.to_string(),
            label: agent.label.to_string(),
        })
        .collect();

    Ok(GlobalSkillsSnapshot { agents, skills })
}

pub fn install_global_skill(
    request: GlobalSkillInstallRequest,
) -> Result<GlobalSkillInstallResult, String> {
    let home_dir = resolve_home_dir()?;
    let agent_scopes = build_agent_scopes(&home_dir);
    let target_agents = resolve_target_agents(&agent_scopes, &request.agent_ids)?;

    let canonical_base = home_dir.join(".agents").join("skills");
    fs::create_dir_all(&canonical_base)
        .map_err(|err| format!("创建全局技能目录失败: {err} ({})", canonical_base.display()))?;

    let requested_skill_names = normalize_user_values(&request.skill_names);
    let mut logs = Vec::new();
    if should_treat_skill_names_as_sources(&requested_skill_names) {
        logs.push("source-mode: use skill names as source identifiers".to_string());
        logs.push(format!("sources: {}", requested_skill_names.join(", ")));
        logs.push(format!("source(input): {}", request.source.trim()));
        logs.push(format!(
            "agents: {}",
            target_agents
                .iter()
                .map(|agent| agent.id.to_string())
                .collect::<Vec<_>>()
                .join(", ")
        ));

        for source_identifier in &requested_skill_names {
            let (source_root, _source_guard) = prepare_source_root(source_identifier)?;
            let discovered_skills = discover_source_skills(&source_root)?;
            if discovered_skills.is_empty() {
                return Err(format!(
                    "来源中未发现可安装的技能（缺少 SKILL.md）：{}（来自 {}）",
                    source_root.display(),
                    source_identifier
                ));
            }

            logs.push(format!(
                "resolved source {} -> {}",
                source_identifier,
                source_root.display()
            ));
            logs.push(format!(
                "skills({source_identifier}): {}",
                discovered_skills
                    .iter()
                    .map(|skill| skill.install_name.clone())
                    .collect::<Vec<_>>()
                    .join(", ")
            ));

            for skill in &discovered_skills {
                let skill_logs = install_one_skill(skill, &canonical_base, &target_agents)?;
                logs.extend(skill_logs);
            }
        }

        return Ok(GlobalSkillInstallResult {
            command: "internal install_global_skill".to_string(),
            stdout: logs.join("\n"),
            stderr: String::new(),
        });
    }

    let source_input = request.source.trim();
    if source_input.is_empty() {
        return Err("安装来源不能为空。请填写仓库地址或本地路径。".to_string());
    }

    let (source_root, _source_guard) = prepare_source_root(source_input)?;
    let discovered_skills = discover_source_skills(&source_root)?;
    if discovered_skills.is_empty() {
        return Err(format!(
            "来源中未发现可安装的技能（缺少 SKILL.md）：{}",
            source_root.display()
        ));
    }

    let selected_skills = select_skills(&discovered_skills, &request.skill_names)?;
    logs.push(format!("source: {}", source_root.display()));
    logs.push(format!(
        "skills: {}",
        selected_skills
            .iter()
            .map(|skill| skill.install_name.clone())
            .collect::<Vec<_>>()
            .join(", ")
    ));
    logs.push(format!(
        "agents: {}",
        target_agents
            .iter()
            .map(|agent| agent.id.to_string())
            .collect::<Vec<_>>()
            .join(", ")
    ));

    for skill in &selected_skills {
        let skill_logs = install_one_skill(skill, &canonical_base, &target_agents)?;
        logs.extend(skill_logs);
    }

    Ok(GlobalSkillInstallResult {
        command: "internal install_global_skill".to_string(),
        stdout: logs.join("\n"),
        stderr: String::new(),
    })
}

pub fn uninstall_global_skill(
    request: GlobalSkillUninstallRequest,
) -> Result<GlobalSkillInstallResult, String> {
    let home_dir = resolve_home_dir()?;
    let agent_scopes = build_agent_scopes(&home_dir);
    let request_agent_ids = vec![request.agent_id.clone()];
    let mut target_agents = resolve_target_agents(&agent_scopes, &request_agent_ids)?;
    let target_agent = target_agents
        .pop()
        .ok_or_else(|| format!("不支持的 Agent 标识: {}", request.agent_id))?;

    let remove_targets = resolve_skill_remove_targets(&target_agent.path, &request);
    let mut logs = vec![
        format!("agent: {} ({})", target_agent.id, target_agent.path.display()),
        format!("skill: {}", request.skill_name),
    ];

    if remove_targets.is_empty() {
        logs.push("removed: 0 (未找到匹配目录)".to_string());
    } else {
        for target in &remove_targets {
            remove_existing_path(target)?;
            logs.push(format!("removed {}", target.display()));
        }
        logs.push(format!("removed: {}", remove_targets.len()));
    }

    Ok(GlobalSkillInstallResult {
        command: "internal uninstall_global_skill".to_string(),
        stdout: logs.join("\n"),
        stderr: String::new(),
    })
}

fn resolve_home_dir() -> Result<PathBuf, String> {
    if let Some(value) = env::var_os("HOME") {
        let path = PathBuf::from(value);
        if !path.as_os_str().is_empty() {
            return Ok(path);
        }
    }
    Err("无法解析 HOME 目录。".to_string())
}

fn build_agent_scopes(home_dir: &Path) -> Vec<SkillAgentScope> {
    let codex_home = env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .filter(|value| !value.as_os_str().is_empty())
        .unwrap_or_else(|| home_dir.join(".codex"));
    let claude_home = env::var_os("CLAUDE_CONFIG_DIR")
        .map(PathBuf::from)
        .filter(|value| !value.as_os_str().is_empty())
        .unwrap_or_else(|| home_dir.join(".claude"));
    let xdg_config_home = env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .filter(|value| !value.as_os_str().is_empty())
        .unwrap_or_else(|| home_dir.join(".config"));

    vec![
        SkillAgentScope {
            id: "codex",
            label: "Codex",
            path: codex_home.join("skills"),
        },
        SkillAgentScope {
            id: "claude-code",
            label: "Claude Code",
            path: claude_home.join("skills"),
        },
        SkillAgentScope {
            id: "cursor",
            label: "Cursor",
            path: home_dir.join(".cursor").join("skills"),
        },
        SkillAgentScope {
            id: "github-copilot",
            label: "GitHub Copilot",
            path: home_dir.join(".copilot").join("skills"),
        },
        SkillAgentScope {
            id: "gemini-cli",
            label: "Gemini CLI",
            path: home_dir.join(".gemini").join("skills"),
        },
        SkillAgentScope {
            id: "continue",
            label: "Continue",
            path: home_dir.join(".continue").join("skills"),
        },
        SkillAgentScope {
            id: "cline",
            label: "Cline",
            path: home_dir.join(".cline").join("skills"),
        },
        SkillAgentScope {
            id: "goose",
            label: "Goose",
            path: xdg_config_home.join("goose").join("skills"),
        },
    ]
}

fn build_global_scan_scopes(
    home_dir: &Path,
    agent_scopes: &[SkillAgentScope],
) -> Vec<SkillScanScope> {
    let mut scopes = vec![SkillScanScope {
        path: home_dir.join(".agents").join("skills"),
        agent: None,
    }];

    for agent in agent_scopes {
        scopes.push(SkillScanScope {
            path: agent.path.clone(),
            agent: Some(agent.clone()),
        });
    }

    scopes
}

fn collect_scope_skills(scope: &SkillScanScope, aggregated: &mut HashMap<String, SkillAggregate>) {
    let entries = match fs::read_dir(&scope.path) {
        Ok(value) => value,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !is_directory(&path) {
            continue;
        }

        let skill_md_path = path.join("SKILL.md");
        if !skill_md_path.is_file() {
            continue;
        }

        let parsed =
            parse_skill_frontmatter(&skill_md_path).unwrap_or_else(|| ParsedSkillFrontmatter {
                name: path
                    .file_name()
                    .map(|value| value.to_string_lossy().to_string())
                    .unwrap_or_default(),
                description: String::new(),
            });

        if parsed.name.trim().is_empty() {
            continue;
        }

        let key = parsed.name.to_lowercase();
        let path_label = path.to_string_lossy().to_string();
        let is_canonical_scope = scope.agent.is_none();

        match aggregated.get_mut(&key) {
            Some(existing) => {
                existing.paths.insert(path_label.clone());
                if existing.description.is_empty() && !parsed.description.is_empty() {
                    existing.description = parsed.description.clone();
                }
                if is_canonical_scope {
                    existing.canonical_path = path_label;
                }
                if let Some(agent) = &scope.agent {
                    existing
                        .agents
                        .insert(agent.id.to_string(), agent.label.to_string());
                }
            }
            None => {
                let mut paths = BTreeSet::new();
                paths.insert(path_label.clone());

                let mut agents = BTreeMap::new();
                if let Some(agent) = &scope.agent {
                    agents.insert(agent.id.to_string(), agent.label.to_string());
                }

                aggregated.insert(
                    key,
                    SkillAggregate {
                        name: parsed.name,
                        description: parsed.description,
                        canonical_path: path_label,
                        paths,
                        agents,
                    },
                );
            }
        }
    }
}

fn prepare_source_root(source: &str) -> Result<(PathBuf, TempDirGuard), String> {
    let local_path = PathBuf::from(source);
    if local_path.exists() {
        if local_path.is_dir() {
            return Ok((local_path, TempDirGuard::none()));
        }
        return Err(format!("来源不是目录：{source}"));
    }

    let clone_url = parse_remote_source(source)?;
    let temp_dir = env::temp_dir().join(format!("devhaven-skill-source-{}", Uuid::new_v4()));

    let output = Command::new(resolve_git_executable())
        .arg("clone")
        .arg("--depth")
        .arg("1")
        .arg(&clone_url)
        .arg(&temp_dir)
        .output()
        .map_err(|err| format!("执行 git clone 失败: {err}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let message = if stderr.is_empty() {
            "未知错误".to_string()
        } else {
            stderr
        };
        return Err(format!("拉取技能来源失败：{message}"));
    }

    Ok((temp_dir.clone(), TempDirGuard::with_path(temp_dir)))
}

fn parse_remote_source(source: &str) -> Result<String, String> {
    if source.starts_with("https://")
        || source.starts_with("http://")
        || source.starts_with("git@")
        || source.starts_with("ssh://")
    {
        return Ok(source.to_string());
    }

    if is_owner_repo_shorthand(source) {
        return Ok(format!("https://github.com/{source}.git"));
    }

    Err("无法识别安装来源。请填写本地目录、完整仓库 URL，或 owner/repo。".to_string())
}

fn is_owner_repo_shorthand(source: &str) -> bool {
    let mut parts = source.split('/');
    let owner = parts.next().unwrap_or_default();
    let repo = parts.next().unwrap_or_default();
    if parts.next().is_some() {
        return false;
    }
    is_valid_owner_repo_part(owner) && is_valid_owner_repo_part(repo)
}

fn is_valid_owner_repo_part(value: &str) -> bool {
    if value.is_empty() {
        return false;
    }
    value
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
}

fn discover_source_skills(source_root: &Path) -> Result<Vec<SourceSkill>, String> {
    let mut discovered = BTreeMap::<String, SourceSkill>::new();

    if source_root.join("SKILL.md").is_file() {
        collect_single_skill(source_root, &mut discovered)?;
    }
    collect_skills_from_container(source_root, &mut discovered)?;

    for relative in SKILL_SOURCE_SEARCH_DIRS {
        let dir = source_root.join(relative);
        collect_skills_from_container(&dir, &mut discovered)?;
    }

    Ok(discovered.into_values().collect())
}

fn collect_skills_from_container(
    container: &Path,
    discovered: &mut BTreeMap<String, SourceSkill>,
) -> Result<(), String> {
    if !is_directory(container) {
        return Ok(());
    }

    if container.join("SKILL.md").is_file() {
        collect_single_skill(container, discovered)?;
    }

    let entries = fs::read_dir(container)
        .map_err(|err| format!("读取技能目录失败: {err} ({})", container.display()))?;

    for entry in entries {
        let entry = entry.map_err(|err| format!("读取目录项失败: {err}"))?;
        let path = entry.path();
        if !is_directory(&path) {
            continue;
        }
        if path.join("SKILL.md").is_file() {
            collect_single_skill(&path, discovered)?;
        }
    }

    Ok(())
}

fn collect_single_skill(
    skill_dir: &Path,
    discovered: &mut BTreeMap<String, SourceSkill>,
) -> Result<(), String> {
    let skill_md = skill_dir.join("SKILL.md");
    if !skill_md.is_file() {
        return Ok(());
    }

    let parsed = parse_skill_frontmatter(&skill_md).unwrap_or_else(|| ParsedSkillFrontmatter {
        name: String::new(),
        description: String::new(),
    });

    let dir_name = skill_dir
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| "skill".to_string());
    let install_name_hint = resolve_install_name_hint(&dir_name, &parsed.name);
    let install_name = sanitize_skill_folder_name(&install_name_hint);
    if install_name.is_empty() {
        return Err(format!("技能目录名称无效：{}", skill_dir.display()));
    }

    let display_name = if parsed.name.trim().is_empty() {
        dir_name
    } else {
        parsed.name
    };

    discovered
        .entry(install_name.clone())
        .or_insert(SourceSkill {
            install_name,
            display_name,
            description: parsed.description,
            path: skill_dir.to_path_buf(),
        });
    Ok(())
}

fn sanitize_skill_folder_name(name: &str) -> String {
    let mut normalized = String::new();
    for ch in name.chars() {
        if ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_') {
            normalized.push(ch);
        } else {
            normalized.push('-');
        }
    }

    let mut compact = String::new();
    let mut previous_dash = false;
    for ch in normalized.chars() {
        if ch == '-' {
            if previous_dash {
                continue;
            }
            previous_dash = true;
            compact.push(ch);
            continue;
        }
        previous_dash = false;
        compact.push(ch);
    }

    compact.trim_matches('-').to_string()
}

fn should_treat_skill_names_as_sources(requested_names: &[String]) -> bool {
    !requested_names.is_empty()
        && !requested_names.iter().any(|value| value == "*")
        && requested_names
            .iter()
            .all(|value| is_source_like_value(value))
}

fn is_source_like_value(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        return false;
    }

    let local_path = PathBuf::from(trimmed);
    if local_path.exists() {
        return true;
    }

    parse_remote_source(trimmed).is_ok()
}

fn resolve_install_name_hint(dir_name: &str, parsed_name: &str) -> String {
    if is_generated_temp_source_dir(dir_name) && !parsed_name.trim().is_empty() {
        return parsed_name.to_string();
    }
    dir_name.to_string()
}

fn is_generated_temp_source_dir(dir_name: &str) -> bool {
    dir_name.starts_with("devhaven-skill-source-")
}

fn select_skills(
    all_skills: &[SourceSkill],
    request_names: &[String],
) -> Result<Vec<SourceSkill>, String> {
    let requested = normalize_user_values(request_names);
    if requested.is_empty() || requested.iter().any(|value| value == "*") {
        return Ok(all_skills.to_vec());
    }

    let mut selected = Vec::new();
    let mut selected_keys = BTreeSet::new();
    let mut missing = Vec::new();

    for request_name in &requested {
        let request_key = normalize_lookup_value(request_name);
        let matched = all_skills.iter().find(|skill| {
            normalize_lookup_value(&skill.install_name) == request_key
                || normalize_lookup_value(&skill.display_name) == request_key
        });

        if let Some(skill) = matched {
            if selected_keys.insert(skill.install_name.clone()) {
                selected.push(skill.clone());
            }
        } else {
            missing.push(request_name.clone());
        }
    }

    if !missing.is_empty() {
        let available = all_skills
            .iter()
            .map(|skill| skill.install_name.clone())
            .collect::<Vec<_>>()
            .join(", ");
        return Err(format!(
            "未找到以下 skills：{}。可用 skills：{}",
            missing.join(", "),
            available
        ));
    }

    Ok(selected)
}

fn normalize_lookup_value(value: &str) -> String {
    value
        .trim()
        .to_lowercase()
        .replace('_', "-")
        .replace(' ', "-")
}

fn resolve_target_agents(
    all_agents: &[SkillAgentScope],
    request_ids: &[String],
) -> Result<Vec<SkillAgentScope>, String> {
    let requested = normalize_user_values(request_ids);
    if requested.is_empty() {
        return Ok(all_agents.to_vec());
    }

    let by_id: HashMap<&str, &SkillAgentScope> =
        all_agents.iter().map(|agent| (agent.id, agent)).collect();
    let mut resolved = Vec::new();
    for id in &requested {
        let Some(scope) = by_id.get(id.as_str()) else {
            return Err(format!("不支持的 Agent 标识: {id}"));
        };
        resolved.push((*scope).clone());
    }
    Ok(resolved)
}

fn install_one_skill(
    skill: &SourceSkill,
    canonical_base: &Path,
    target_agents: &[SkillAgentScope],
) -> Result<Vec<String>, String> {
    let canonical_dir = canonical_base.join(&skill.install_name);
    sync_skill_directory(&skill.path, &canonical_dir)?;

    let mut logs = Vec::new();
    if skill.description.trim().is_empty() {
        logs.push(format!(
            "installed {} ({}) -> {}",
            skill.install_name,
            skill.display_name,
            canonical_dir.display()
        ));
    } else {
        logs.push(format!(
            "installed {} ({}) -> {}",
            skill.install_name,
            skill.description,
            canonical_dir.display()
        ));
    }

    for agent in target_agents {
        let agent_base = &agent.path;
        fs::create_dir_all(agent_base)
            .map_err(|err| format!("创建 Agent 目录失败: {err} ({})", agent_base.display()))?;

        let link_path = agent_base.join(&skill.install_name);
        if link_path == canonical_dir {
            logs.push(format!("  - {}: canonical", agent.id));
            continue;
        }

        remove_existing_path(&link_path)?;
        match create_symlink_dir(&canonical_dir, &link_path) {
            Ok(_) => logs.push(format!("  - {}: linked", agent.id)),
            Err(_) => {
                copy_dir_recursive(&canonical_dir, &link_path)?;
                logs.push(format!("  - {}: copied", agent.id));
            }
        }
    }

    Ok(logs)
}

fn resolve_skill_remove_targets(
    agent_skill_base: &Path,
    request: &GlobalSkillUninstallRequest,
) -> Vec<PathBuf> {
    let mut targets = BTreeSet::<PathBuf>::new();
    let mut candidate_names = BTreeSet::<String>::new();

    if let Some(name) = extract_skill_dir_name(&request.canonical_path) {
        candidate_names.insert(name);
    }

    for path in &request.paths {
        if let Some(name) = extract_skill_dir_name(path) {
            candidate_names.insert(name);
        }
    }

    let fallback_name = sanitize_skill_folder_name(&request.skill_name);
    if !fallback_name.is_empty() {
        candidate_names.insert(fallback_name);
    }

    for name in candidate_names {
        let candidate = agent_skill_base.join(name);
        if fs::symlink_metadata(&candidate).is_ok() {
            targets.insert(candidate);
        }
    }

    if !targets.is_empty() {
        return targets.into_iter().collect();
    }

    if request.skill_name.trim().is_empty() {
        return Vec::new();
    }

    let target_name = normalize_lookup_value(&request.skill_name);
    let entries = match fs::read_dir(agent_skill_base) {
        Ok(value) => value,
        Err(_) => return Vec::new(),
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if !is_directory(&path) {
            continue;
        }

        let skill_md = path.join("SKILL.md");
        if !skill_md.is_file() {
            continue;
        }

        let parsed_name = parse_skill_frontmatter(&skill_md)
            .map(|value| value.name)
            .unwrap_or_default();
        if !parsed_name.is_empty() && normalize_lookup_value(&parsed_name) == target_name {
            targets.insert(path);
        }
    }

    targets.into_iter().collect()
}

fn extract_skill_dir_name(path: &str) -> Option<String> {
    let file_name = Path::new(path).file_name()?.to_string_lossy().to_string();
    if file_name.trim().is_empty() {
        return None;
    }
    Some(file_name)
}

fn create_symlink_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        unix_fs::symlink(src, dst)
    }
    #[cfg(windows)]
    {
        windows_fs::symlink_dir(src, dst)
    }
}

fn sync_skill_directory(source: &Path, target: &Path) -> Result<(), String> {
    if !is_directory(source) {
        return Err(format!("技能来源目录不存在：{}", source.display()));
    }

    remove_existing_path(target)?;
    copy_dir_recursive(source, target)
}

fn copy_dir_recursive(source: &Path, target: &Path) -> Result<(), String> {
    fs::create_dir_all(target)
        .map_err(|err| format!("创建目录失败: {err} ({})", target.display()))?;

    let entries = fs::read_dir(source)
        .map_err(|err| format!("读取目录失败: {err} ({})", source.display()))?;
    for entry in entries {
        let entry = entry.map_err(|err| format!("读取目录项失败: {err}"))?;
        let from_path = entry.path();
        let to_path = target.join(entry.file_name());

        let meta = fs::symlink_metadata(&from_path)
            .map_err(|err| format!("读取路径元数据失败: {err} ({})", from_path.display()))?;
        let file_type = meta.file_type();
        if file_type.is_dir() {
            copy_dir_recursive(&from_path, &to_path)?;
            continue;
        }

        if file_type.is_file() {
            fs::copy(&from_path, &to_path).map_err(|err| {
                format!(
                    "复制文件失败: {err} ({} -> {})",
                    from_path.display(),
                    to_path.display()
                )
            })?;
            continue;
        }

        if file_type.is_symlink() {
            let target_meta = fs::metadata(&from_path)
                .map_err(|err| format!("读取符号链接目标失败: {err} ({})", from_path.display()))?;
            if target_meta.is_dir() {
                copy_dir_recursive(&from_path, &to_path)?;
            } else {
                fs::copy(&from_path, &to_path).map_err(|err| {
                    format!(
                        "复制链接文件失败: {err} ({} -> {})",
                        from_path.display(),
                        to_path.display()
                    )
                })?;
            }
        }
    }

    Ok(())
}

fn remove_existing_path(path: &Path) -> Result<(), String> {
    let meta = match fs::symlink_metadata(path) {
        Ok(value) => value,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(err) => return Err(format!("读取路径失败: {err} ({})", path.display())),
    };

    let file_type = meta.file_type();
    if file_type.is_symlink() || file_type.is_file() {
        fs::remove_file(path).map_err(|err| format!("删除文件失败: {err} ({})", path.display()))
    } else if file_type.is_dir() {
        fs::remove_dir_all(path).map_err(|err| format!("删除目录失败: {err} ({})", path.display()))
    } else {
        Ok(())
    }
}

fn is_directory(path: &Path) -> bool {
    fs::metadata(path)
        .map(|meta| meta.is_dir())
        .unwrap_or(false)
}

fn parse_skill_frontmatter(path: &Path) -> Option<ParsedSkillFrontmatter> {
    let content = fs::read_to_string(path).ok()?;
    let mut lines = content.lines();

    if lines.next()?.trim() != "---" {
        return None;
    }

    let mut name = None;
    let mut description = None;

    for line in lines {
        let trimmed = line.trim();
        if trimmed == "---" {
            break;
        }

        if name.is_none() {
            if let Some(value) = trimmed.strip_prefix("name:") {
                name = normalize_frontmatter_value(value);
                continue;
            }
        }

        if description.is_none() {
            if let Some(value) = trimmed.strip_prefix("description:") {
                description = normalize_frontmatter_value(value);
            }
        }
    }

    Some(ParsedSkillFrontmatter {
        name: name?,
        description: description.unwrap_or_default(),
    })
}

fn normalize_frontmatter_value(raw: &str) -> Option<String> {
    let value = raw.trim();
    if value.is_empty() {
        return None;
    }

    let unquoted = strip_surrounding_quotes(value);
    if unquoted.is_empty() {
        return None;
    }

    Some(unquoted.to_string())
}

fn strip_surrounding_quotes(value: &str) -> &str {
    if value.len() >= 2 {
        let first = value.as_bytes()[0];
        let last = value.as_bytes()[value.len() - 1];
        if (first == b'"' && last == b'"') || (first == b'\'' && last == b'\'') {
            return value[1..value.len() - 1].trim();
        }
    }
    value
}

fn normalize_user_values(values: &[String]) -> Vec<String> {
    let mut result = Vec::new();
    let mut seen = BTreeSet::new();

    for value in values {
        let trimmed = value.trim();
        if trimmed.is_empty() {
            continue;
        }

        let normalized = trimmed.to_lowercase();
        if seen.insert(normalized) {
            result.push(trimmed.to_string());
        }
    }

    result
}

fn resolve_git_executable() -> String {
    #[cfg(target_os = "macos")]
    {
        if Path::new("/usr/bin/git").exists() {
            "/usr/bin/git".to_string()
        } else {
            "git".to_string()
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        "git".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::{
        is_generated_temp_source_dir, resolve_install_name_hint,
        should_treat_skill_names_as_sources,
    };

    #[test]
    fn should_detect_source_like_skill_names() {
        assert!(should_treat_skill_names_as_sources(&[
            "vercel-labs/agent-browser".to_string()
        ]));
        assert!(!should_treat_skill_names_as_sources(&[
            "agent-browser".to_string()
        ]));
        assert!(!should_treat_skill_names_as_sources(&["*".to_string()]));
    }

    #[test]
    fn should_use_frontmatter_name_for_generated_temp_source_dir() {
        assert!(is_generated_temp_source_dir(
            "devhaven-skill-source-b3346c7f-cc3d-47bd-b6aa-0b7fd9fa49c6"
        ));
        assert_eq!(
            resolve_install_name_hint("devhaven-skill-source-123", "agent-browser"),
            "agent-browser"
        );
        assert_eq!(
            resolve_install_name_hint("composition-patterns", "composition-patterns"),
            "composition-patterns"
        );
    }
}
