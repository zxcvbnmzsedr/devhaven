use std::collections::BTreeSet;
use std::env;
use std::net::TcpListener as StdTcpListener;
use std::path::{Component, Path, PathBuf};
use std::str::FromStr;
use std::sync::{Arc, Mutex};

use axum::body::Body;
use axum::extract::{Path as AxumPath, Query, State, WebSocketUpgrade, ws::Message, ws::WebSocket};
use axum::http::header::{self, HeaderValue};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use tauri::{AppHandle, Manager};
use tokio::sync::oneshot;
use tower_http::cors::CorsLayer;

use crate::interaction_lock::InteractionLockState;
use crate::models::{
    GitIdentity, GlobalSkillInstallRequest, GlobalSkillUninstallRequest,
    SharedScriptManifestScript, WorktreeInitRetryRequest, WorktreeInitStartRequest,
    WorktreeInitStatusQuery,
};
use crate::quick_command_manager::QuickCommandManager;
use crate::terminal::TerminalState;
use crate::web_event_bus;
use crate::worktree_init::WorktreeInitState;

const DEFAULT_WEB_HOST: &str = "0.0.0.0";
const DEFAULT_WEB_PORT: u16 = 3210;
const DEFAULT_WEB_ENABLED: bool = true;

#[derive(Clone)]
struct WebServerState {
    app: AppHandle,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ApiSuccess<T> {
    ok: bool,
    data: T,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ApiError {
    ok: bool,
    error: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct HealthResponse {
    ok: bool,
    name: String,
    version: String,
}

#[derive(Debug, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct WebSocketQuery {
    window_label: Option<String>,
}

impl WebSocketQuery {
    fn resolved_window_label(&self) -> Option<String> {
        self.window_label
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned)
    }
}

#[derive(Debug, Clone)]
struct PathGuard {
    home_dir: PathBuf,
    allowed_roots: Vec<PathBuf>,
}

#[derive(Debug, Clone)]
struct WebServerConfig {
    enabled: bool,
    host: String,
    port: u16,
}

struct WebServerHandle {
    shutdown_tx: oneshot::Sender<()>,
    bind_addr: String,
}

#[derive(Clone, Default)]
pub struct WebServerRuntime {
    inner: Arc<Mutex<Option<WebServerHandle>>>,
}

pub fn ensure_started(app: AppHandle, runtime: WebServerRuntime) {
    if let Err(error) = apply_config(app, runtime) {
        log::warn!("应用 Web API 配置失败: {}", error);
    }
}

pub fn apply_config(app: AppHandle, runtime: WebServerRuntime) -> Result<(), String> {
    let config = resolve_web_server_config(&app);

    let mut old_handle = {
        let mut guard = runtime
            .inner
            .lock()
            .map_err(|error| format!("锁定 Web 服务状态失败: {}", error))?;
        guard.take()
    };

    if !config.enabled {
        if let Some(old) = old_handle.take() {
            log::info!("停止旧 Web API 监听: http://{}", old.bind_addr);
            let _ = old.shutdown_tx.send(());
        }
        log::info!("Web API 已禁用（热更新生效）");
        return Ok(());
    }

    let bind_addr = format!("{}:{}", config.host, config.port);

    let needs_bind_after_stop = old_handle
        .as_ref()
        .is_some_and(|old| old.bind_addr == bind_addr);

    let prebound_listener = if needs_bind_after_stop {
        None
    } else {
        Some(bind_listener(&bind_addr)?)
    };

    let state = WebServerState { app };
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();
    let bind_addr_for_task = bind_addr.clone();

    let listener = if let Some(listener) = prebound_listener {
        if let Some(old) = old_handle.take() {
            log::info!("停止旧 Web API 监听: http://{}", old.bind_addr);
            let _ = old.shutdown_tx.send(());
        }
        listener
    } else {
        if let Some(old) = old_handle.take() {
            log::info!("停止旧 Web API 监听: http://{}", old.bind_addr);
            let _ = old.shutdown_tx.send(());
        }
        bind_listener(&bind_addr)?
    };

    tauri::async_runtime::spawn(async move {
        let listener = match tokio::net::TcpListener::from_std(listener) {
            Ok(listener) => listener,
            Err(error) => {
                log::warn!("接管 Web API 监听失败 {}: {}", bind_addr_for_task, error);
                return;
            }
        };

        let router = Router::new()
            .route("/api/health", get(handle_health))
            .route("/api/ws", get(handle_websocket_upgrade))
            .route("/api/cmd/{command}", post(handle_command))
            .route("/", get(handle_web_root))
            .route("/{*path}", get(handle_web_asset_or_spa))
            .layer(CorsLayer::permissive())
            .with_state(state.clone());

        log::info!("Web API 已启动: http://{}", bind_addr_for_task);

        let server = axum::serve(listener, router).with_graceful_shutdown(async {
            let _ = shutdown_rx.await;
        });

        if let Err(error) = server.await {
            log::warn!("Web API 服务退出: {}", error);
        }
    });

    {
        let mut guard = runtime
            .inner
            .lock()
            .map_err(|error| format!("锁定 Web 服务状态失败: {}", error))?;
        *guard = Some(WebServerHandle {
            shutdown_tx,
            bind_addr: bind_addr.clone(),
        });
    }

    log::info!("Web API 已热更新生效: http://{}", bind_addr);
    Ok(())
}

fn bind_listener(bind_addr: &str) -> Result<StdTcpListener, String> {
    let std_listener = StdTcpListener::bind(bind_addr)
        .map_err(|error| format!("启动 Web API 监听失败 {}: {}", bind_addr, error))?;
    std_listener
        .set_nonblocking(true)
        .map_err(|error| format!("设置 Web API 非阻塞失败 {}: {}", bind_addr, error))?;
    Ok(std_listener)
}

fn resolve_web_server_config(app: &AppHandle) -> WebServerConfig {
    let mut enabled = DEFAULT_WEB_ENABLED;
    let mut host = DEFAULT_WEB_HOST.to_string();
    let mut port = default_web_port(app);

    if let Ok(raw) = env::var("DEVHAVEN_WEB_ENABLED") {
        match parse_env_bool(&raw) {
            Some(value) => enabled = value,
            None => log::warn!("忽略无效 DEVHAVEN_WEB_ENABLED: {}", raw),
        }
    }

    if let Ok(raw) = env::var("DEVHAVEN_WEB_HOST") {
        let value = raw.trim();
        if value.is_empty() {
            log::warn!("忽略空 DEVHAVEN_WEB_HOST");
        } else {
            host = value.to_string();
        }
    }

    if let Ok(raw) = env::var("DEVHAVEN_WEB_PORT") {
        match parse_port(&raw) {
            Some(value) => port = value,
            None => log::warn!("忽略无效 DEVHAVEN_WEB_PORT: {}", raw),
        }
    }

    WebServerConfig {
        enabled,
        host,
        port,
    }
}

fn parse_port(raw: &str) -> Option<u16> {
    u16::from_str(raw.trim()).ok().filter(|value| *value > 0)
}

fn default_web_port(app: &AppHandle) -> u16 {
    if cfg!(debug_assertions) {
        return DEFAULT_WEB_PORT;
    }

    match crate::load_app_state(app.clone()) {
        Ok(state) if state.settings.vite_dev_port > 0 => state.settings.vite_dev_port,
        Ok(_) => DEFAULT_WEB_PORT,
        Err(error) => {
            log::warn!("读取 app_state 失败，Web API 端口回退默认值: {}", error);
            DEFAULT_WEB_PORT
        }
    }
}

fn parse_env_bool(raw: &str) -> Option<bool> {
    match raw.trim().to_ascii_lowercase().as_str() {
        "1" | "true" | "yes" | "on" => Some(true),
        "0" | "false" | "no" | "off" => Some(false),
        _ => None,
    }
}

async fn handle_health(State(state): State<WebServerState>) -> Json<HealthResponse> {
    let package_info = state.app.package_info();
    Json(HealthResponse {
        ok: true,
        name: package_info.name.clone(),
        version: package_info.version.to_string(),
    })
}

async fn handle_web_root(State(state): State<WebServerState>) -> Response {
    serve_web_asset(&state.app, "index.html")
}

async fn handle_web_asset_or_spa(
    State(state): State<WebServerState>,
    AxumPath(request_path): AxumPath<String>,
) -> Response {
    if request_path.is_empty() {
        return serve_web_asset(&state.app, "index.html");
    }
    if request_path.starts_with("api/") {
        return StatusCode::NOT_FOUND.into_response();
    }

    let normalized_path = normalize_web_asset_path(&request_path);
    if normalized_path.is_empty() {
        return serve_web_asset(&state.app, "index.html");
    }

    let asset_response = serve_web_asset_if_exists(&state.app, &normalized_path);
    if asset_response.status() != StatusCode::NOT_FOUND {
        return asset_response;
    }

    // 无扩展名路径按 SPA 路由回退到 index.html；静态资源仍保持 404。
    if normalized_path.contains('.') {
        return asset_response;
    }

    serve_web_asset(&state.app, "index.html")
}

fn normalize_web_asset_path(raw_path: &str) -> String {
    let mut normalized = PathBuf::new();
    for component in Path::new(raw_path).components() {
        match component {
            Component::Normal(value) => normalized.push(value),
            Component::CurDir => {}
            _ => return String::new(),
        }
    }
    normalized
        .to_string_lossy()
        .replace('\\', "/")
        .trim_start_matches('/')
        .to_string()
}

fn serve_web_asset(app: &AppHandle, path: &str) -> Response {
    let response = serve_web_asset_if_exists(app, path);
    if response.status() == StatusCode::NOT_FOUND {
        return (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiError {
                ok: false,
                error: format!("前端资源缺失: {}", path),
            }),
        )
            .into_response();
    }
    response
}

fn serve_web_asset_if_exists(app: &AppHandle, path: &str) -> Response {
    let asset_path = path.trim().trim_start_matches('/');
    let asset_path = if asset_path.is_empty() {
        "index.html"
    } else {
        asset_path
    };

    let Some(asset) = app.asset_resolver().get(asset_path.to_string()) else {
        return StatusCode::NOT_FOUND.into_response();
    };

    let mut response = Response::new(Body::from(asset.bytes));
    *response.status_mut() = StatusCode::OK;

    if let Ok(content_type) = HeaderValue::from_str(&asset.mime_type) {
        response
            .headers_mut()
            .insert(header::CONTENT_TYPE, content_type);
    }

    if let Some(csp_header) = asset.csp_header {
        if let Ok(csp) = HeaderValue::from_str(&csp_header) {
            response
                .headers_mut()
                .insert(header::CONTENT_SECURITY_POLICY, csp);
        }
    }

    response
}

async fn handle_command(
    State(state): State<WebServerState>,
    AxumPath(command): AxumPath<String>,
    Json(payload): Json<Value>,
) -> impl IntoResponse {
    let app = state.app.clone();
    let dispatch_result =
        tokio::task::spawn_blocking(move || dispatch_command(&app, &command, payload)).await;

    match dispatch_result {
        Ok(Ok(data)) => (StatusCode::OK, Json(ApiSuccess { ok: true, data })).into_response(),
        Ok(Err(error)) => (StatusCode::OK, Json(ApiError { ok: false, error })).into_response(),
        Err(error) => (
            StatusCode::INTERNAL_SERVER_ERROR,
            Json(ApiError {
                ok: false,
                error: format!("后台命令执行失败: {}", error),
            }),
        )
            .into_response(),
    }
}

async fn handle_websocket_upgrade(
    ws: WebSocketUpgrade,
    Query(query): Query<WebSocketQuery>,
    State(_state): State<WebServerState>,
) -> impl IntoResponse {
    let Some(window_label) = query.resolved_window_label() else {
        return (
            StatusCode::BAD_REQUEST,
            Json(ApiError {
                ok: false,
                error: "缺少 windowLabel 查询参数".to_string(),
            }),
        )
            .into_response();
    };
    ws.on_upgrade(move |socket| handle_websocket(socket, Some(window_label)))
        .into_response()
}

async fn handle_websocket(mut socket: WebSocket, window_label: Option<String>) {
    let mut rx = web_event_bus::subscribe();

    loop {
        tokio::select! {
            result = rx.recv() => {
                let Ok(event) = result else {
                    continue;
                };
                if !should_send_event_to_ws_client(&event, window_label.as_deref()) {
                    continue;
                }
                let text = match serde_json::to_string(&event) {
                    Ok(text) => text,
                    Err(error) => {
                        log::warn!("序列化 WS 事件失败: {}", error);
                        continue;
                    }
                };
                if socket.send(Message::Text(text.into())).await.is_err() {
                    break;
                }
            }
            incoming = socket.recv() => {
                match incoming {
                    Some(Ok(Message::Close(_))) | None => break,
                    Some(Ok(_)) => {}
                    Some(Err(_)) => break,
                }
            }
        }
    }
}

fn dispatch_command(app: &AppHandle, command: &str, payload: Value) -> Result<Value, String> {
    let guard = PathGuard::from_app(app)?;

    match command {
        "load_app_state" => to_json(crate::load_app_state(app.clone())),
        "save_app_state" => {
            let state = required::<crate::models::AppStateFile>(&payload, &["state"])?;
            for directory in &state.directories {
                guard.ensure_under_home_path(directory, "state.directories[]")?;
            }
            for project_path in &state.direct_project_paths {
                guard.ensure_under_home_path(project_path, "state.directProjectPaths[]")?;
            }
            to_json(crate::save_app_state(app.clone(), state))
        }
        "load_projects" => to_json(crate::load_projects(app.clone())),
        "save_projects" => {
            let projects = required::<Vec<crate::models::Project>>(&payload, &["projects"])?;
            to_json(crate::save_projects(app.clone(), projects))
        }
        "discover_projects" => {
            let directories = required::<Vec<String>>(&payload, &["directories"])?;
            for directory in &directories {
                guard.ensure_under_home_path(directory, "directories[]")?;
            }
            to_json(Ok::<_, String>(crate::discover_projects(directories)))
        }
        "build_projects" => {
            let paths = required::<Vec<String>>(&payload, &["paths"])?;
            for path in &paths {
                guard.ensure_under_home_path(path, "paths[]")?;
            }
            let existing = required::<Vec<crate::models::Project>>(&payload, &["existing"])?;
            to_json(Ok::<_, String>(crate::build_projects(paths, existing)))
        }
        "list_global_skills" => to_json(crate::list_global_skills()),
        "install_global_skill" => {
            let request = required::<GlobalSkillInstallRequest>(&payload, &["request"])?;
            to_json(crate::install_global_skill(request))
        }
        "uninstall_global_skill" => {
            let request = required::<GlobalSkillUninstallRequest>(&payload, &["request"])?;
            to_json(crate::uninstall_global_skill(request))
        }
        "list_branches" => {
            let base_path = required::<String>(&payload, &["basePath", "base_path"])?;
            guard.ensure_allowed_path(&base_path, "basePath")?;
            to_json(Ok::<_, String>(crate::list_branches(base_path)))
        }
        "git_is_repo" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(Ok::<_, String>(crate::git_is_repo(path)))
        }
        "git_get_status" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::git_get_status(path))
        }
        "git_get_diff_contents" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            let staged = required::<bool>(&payload, &["staged"])?;
            let old_relative_path =
                optional::<String>(&payload, &["oldRelativePath", "old_relative_path"])?;
            to_json(crate::git_get_diff_contents(
                path,
                relative_path,
                staged,
                old_relative_path,
            ))
        }
        "git_stage_files" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_paths =
                required::<Vec<String>>(&payload, &["relativePaths", "relative_paths"])?;
            to_json(crate::git_stage_files(path, relative_paths))
        }
        "git_unstage_files" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_paths =
                required::<Vec<String>>(&payload, &["relativePaths", "relative_paths"])?;
            to_json(crate::git_unstage_files(path, relative_paths))
        }
        "git_discard_files" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_paths =
                required::<Vec<String>>(&payload, &["relativePaths", "relative_paths"])?;
            to_json(crate::git_discard_files(path, relative_paths))
        }
        "git_commit" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let message = required::<String>(&payload, &["message"])?;
            to_json(crate::git_commit(path, message))
        }
        "git_checkout_branch" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let branch = required::<String>(&payload, &["branch"])?;
            to_json(crate::git_checkout_branch(path, branch))
        }
        "git_delete_branch" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let branch = required::<String>(&payload, &["branch"])?;
            let force = required::<bool>(&payload, &["force"])?;
            to_json(crate::git_delete_branch(path, branch, force))
        }
        "git_worktree_add" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let branch = required::<String>(&payload, &["branch"])?;
            let create_branch = required::<bool>(&payload, &["createBranch", "create_branch"])?;
            let target_path = optional::<String>(&payload, &["targetPath", "target_path"])?;
            if let Some(target_path) = target_path.as_deref() {
                guard.ensure_allowed_path(target_path, "targetPath")?;
            }
            to_json(crate::git_worktree_add(
                path,
                branch,
                create_branch,
                target_path,
            ))
        }
        "git_worktree_list" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::git_worktree_list(path))
        }
        "git_worktree_remove" => {
            let path = required::<String>(&payload, &["path"])?;
            let worktree_path = required::<String>(&payload, &["worktreePath", "worktree_path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            guard.ensure_allowed_path(&worktree_path, "worktreePath")?;
            let force = required::<bool>(&payload, &["force"])?;
            to_json(crate::git_worktree_remove(path, worktree_path, force))
        }
        "get_interaction_lock_state" => {
            let lock_state = app.state::<InteractionLockState>();
            to_json(Ok::<_, String>(crate::get_interaction_lock_state(
                lock_state,
            )))
        }
        "apply_web_server_config" => {
            let runtime = app.state::<WebServerRuntime>();
            to_json(apply_config(app.clone(), runtime.inner().clone()))
        }
        "worktree_init_start" => {
            let state = app.state::<WorktreeInitState>();
            let request = required::<WorktreeInitStartRequest>(&payload, &["request"])?;
            guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
            to_json(crate::worktree_init_start(app.clone(), state, request))
        }
        "worktree_init_create" => {
            let state = app.state::<WorktreeInitState>();
            let interaction_lock = app.state::<InteractionLockState>();
            let request = required::<WorktreeInitStartRequest>(&payload, &["request"])?;
            guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
            to_json(crate::worktree_init_create(
                app.clone(),
                state,
                interaction_lock,
                request,
            ))
        }
        "worktree_init_create_blocking" => {
            let state = app.state::<WorktreeInitState>();
            let interaction_lock = app.state::<InteractionLockState>();
            let request = required::<WorktreeInitStartRequest>(&payload, &["request"])?;
            guard.ensure_allowed_path(&request.project_path, "request.projectPath")?;
            to_json(crate::worktree_init_create_blocking(
                app.clone(),
                state,
                interaction_lock,
                request,
            ))
        }
        "worktree_init_cancel" => {
            let state = app.state::<WorktreeInitState>();
            let job_id = required::<String>(&payload, &["jobId", "job_id"])?;
            to_json(crate::worktree_init_cancel(app.clone(), state, job_id))
        }
        "worktree_init_retry" => {
            let state = app.state::<WorktreeInitState>();
            let request = required::<WorktreeInitRetryRequest>(&payload, &["request"])?;
            to_json(crate::worktree_init_retry(app.clone(), state, request))
        }
        "worktree_init_status" => {
            let state = app.state::<WorktreeInitState>();
            let query = optional::<WorktreeInitStatusQuery>(&payload, &["query"])?;
            if let Some(project_path) = query.as_ref().and_then(|item| item.project_path.as_ref()) {
                guard.ensure_allowed_path(project_path, "query.projectPath")?;
            }
            to_json(crate::worktree_init_status(state, query))
        }
        "open_in_finder" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::open_in_finder(path))
        }
        "resolve_home_dir" => to_json(crate::resolve_home_dir(app.clone())),
        "copy_to_clipboard" => {
            let content = required::<String>(&payload, &["content"])?;
            to_json(crate::copy_to_clipboard(app.clone(), content))
        }
        "list_shared_scripts" => {
            let root = optional::<String>(&payload, &["root"])?;
            if let Some(root) = root.as_deref() {
                guard.ensure_allowed_path(root, "root")?;
            }
            to_json(crate::list_shared_scripts(app.clone(), root))
        }
        "save_shared_scripts_manifest" => {
            let root = optional::<String>(&payload, &["root"])?;
            if let Some(root) = root.as_deref() {
                guard.ensure_allowed_path(root, "root")?;
            }
            let scripts = required::<Vec<SharedScriptManifestScript>>(&payload, &["scripts"])?;
            to_json(crate::save_shared_scripts_manifest(
                app.clone(),
                root,
                scripts,
            ))
        }
        "restore_shared_script_presets" => {
            let root = optional::<String>(&payload, &["root"])?;
            if let Some(root) = root.as_deref() {
                guard.ensure_allowed_path(root, "root")?;
            }
            to_json(crate::restore_shared_script_presets(app.clone(), root))
        }
        "read_shared_script_file" => {
            let root = optional::<String>(&payload, &["root"])?;
            if let Some(root) = root.as_deref() {
                guard.ensure_allowed_path(root, "root")?;
            }
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            to_json(crate::read_shared_script_file(
                app.clone(),
                root,
                relative_path,
            ))
        }
        "write_shared_script_file" => {
            let root = optional::<String>(&payload, &["root"])?;
            if let Some(root) = root.as_deref() {
                guard.ensure_allowed_path(root, "root")?;
            }
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            let content = required::<String>(&payload, &["content"])?;
            to_json(crate::write_shared_script_file(
                app.clone(),
                root,
                relative_path,
                content,
            ))
        }
        "read_project_notes" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::read_project_notes(path))
        }
        "read_project_notes_previews" => {
            let paths = required::<Vec<String>>(&payload, &["paths"])?;
            for path in &paths {
                guard.ensure_allowed_path(path, "paths[]")?;
            }
            to_json(Ok::<_, String>(crate::read_project_notes_previews(paths)))
        }
        "write_project_notes" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let notes = optional::<String>(&payload, &["notes"])?;
            to_json(crate::write_project_notes(path, notes))
        }
        "read_project_todo" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::read_project_todo(path))
        }
        "write_project_todo" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let todo = optional::<String>(&payload, &["todo"])?;
            to_json(crate::write_project_todo(path, todo))
        }
        "list_project_markdown_files" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            to_json(crate::list_project_markdown_files(path))
        }
        "read_project_markdown_file" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            to_json(crate::read_project_markdown_file(path, relative_path))
        }
        "list_project_dir_entries" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            let show_hidden = required::<bool>(&payload, &["showHidden", "show_hidden"])?;
            to_json(Ok::<_, String>(crate::list_project_dir_entries(
                path,
                relative_path,
                show_hidden,
            )))
        }
        "read_project_file" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            to_json(Ok::<_, String>(crate::read_project_file(
                path,
                relative_path,
            )))
        }
        "write_project_file" => {
            let path = required::<String>(&payload, &["path"])?;
            guard.ensure_allowed_path(&path, "path")?;
            let relative_path = required::<String>(&payload, &["relativePath", "relative_path"])?;
            let content = required::<String>(&payload, &["content"])?;
            to_json(Ok::<_, String>(crate::write_project_file(
                path,
                relative_path,
                content,
            )))
        }
        "collect_git_daily" => {
            let paths = required::<Vec<String>>(&payload, &["paths"])?;
            for path in &paths {
                guard.ensure_allowed_path(path, "paths[]")?;
            }
            let identities =
                optional::<Vec<GitIdentity>>(&payload, &["identities"])?.unwrap_or_default();
            to_json(Ok::<_, String>(crate::collect_git_daily(paths, identities)))
        }
        "load_heatmap_cache" => to_json(crate::load_heatmap_cache(app.clone())),
        "save_heatmap_cache" => {
            let cache = required::<crate::models::HeatmapCacheFile>(&payload, &["cache"])?;
            to_json(crate::save_heatmap_cache(app.clone(), cache))
        }
        "load_terminal_workspace" => {
            let project_path = required::<String>(&payload, &["projectPath", "project_path"])?;
            guard.ensure_allowed_path(&project_path, "projectPath")?;
            to_json(crate::load_terminal_workspace(app.clone(), project_path))
        }
        "save_terminal_workspace" => {
            let project_path = required::<String>(&payload, &["projectPath", "project_path"])?;
            guard.ensure_allowed_path(&project_path, "projectPath")?;
            let workspace = required::<crate::models::TerminalWorkspace>(&payload, &["workspace"])?;
            to_json(crate::save_terminal_workspace(
                app.clone(),
                project_path,
                workspace,
            ))
        }
        "delete_terminal_workspace" => {
            let project_path = required::<String>(&payload, &["projectPath", "project_path"])?;
            guard.ensure_allowed_path(&project_path, "projectPath")?;
            to_json(crate::delete_terminal_workspace(app.clone(), project_path))
        }
        "list_terminal_workspace_summaries" => {
            to_json(crate::list_terminal_workspace_summaries(app.clone()))
        }
        "get_codex_monitor_snapshot" => to_json(crate::get_codex_monitor_snapshot(app.clone())),
        "quick_command_start" => {
            let state = app.state::<QuickCommandManager>();
            let project_id = required::<String>(&payload, &["projectId", "project_id"])?;
            let project_path = required::<String>(&payload, &["projectPath", "project_path"])?;
            guard.ensure_allowed_path(&project_path, "projectPath")?;
            let script_id = required::<String>(&payload, &["scriptId", "script_id"])?;
            let command = required::<String>(&payload, &["command"])?;
            let window_label = optional::<String>(&payload, &["windowLabel", "window_label"])?;
            to_json(Ok::<_, String>(
                crate::quick_command_manager::quick_command_start(
                    app.clone(),
                    state,
                    project_id,
                    project_path,
                    script_id,
                    command,
                    window_label,
                ),
            ))
        }
        "quick_command_stop" => {
            let state = app.state::<QuickCommandManager>();
            let job_id = required::<String>(&payload, &["jobId", "job_id"])?;
            let force = optional::<bool>(&payload, &["force"])?;
            to_json(crate::quick_command_manager::quick_command_stop(
                app.clone(),
                state,
                job_id,
                force,
            ))
        }
        "quick_command_finish" => {
            let state = app.state::<QuickCommandManager>();
            let job_id = required::<String>(&payload, &["jobId", "job_id"])?;
            let exit_code = optional::<i32>(&payload, &["exitCode", "exit_code"])?;
            let error = optional::<String>(&payload, &["error"])?;
            to_json(crate::quick_command_manager::quick_command_finish(
                app.clone(),
                state,
                job_id,
                exit_code,
                error,
            ))
        }
        "quick_command_list" => {
            let state = app.state::<QuickCommandManager>();
            let project_path = optional::<String>(&payload, &["projectPath", "project_path"])?;
            if let Some(project_path) = project_path.as_deref() {
                guard.ensure_allowed_path(project_path, "projectPath")?;
            }
            to_json(Ok::<_, String>(
                crate::quick_command_manager::quick_command_list(state, project_path),
            ))
        }
        "quick_command_snapshot" => {
            let state = app.state::<QuickCommandManager>();
            to_json(Ok::<_, String>(
                crate::quick_command_manager::quick_command_snapshot(state),
            ))
        }
        "terminal_create_session" => {
            let state = app.state::<TerminalState>();
            let project_path = required::<String>(&payload, &["projectPath", "project_path"])?;
            guard.ensure_allowed_path(&project_path, "projectPath")?;
            let cols = required::<u16>(&payload, &["cols"])?;
            let rows = required::<u16>(&payload, &["rows"])?;
            let window_label = required::<String>(&payload, &["windowLabel", "window_label"])?;
            let session_id = optional::<String>(&payload, &["sessionId", "session_id"])?;
            to_json(crate::terminal::terminal_create_session(
                app.clone(),
                state,
                project_path,
                cols,
                rows,
                window_label,
                session_id,
            ))
        }
        "terminal_write" => {
            let state = app.state::<TerminalState>();
            let pty_id = required::<String>(&payload, &["ptyId", "pty_id"])?;
            let data = required::<String>(&payload, &["data"])?;
            to_json(crate::terminal::terminal_write(state, pty_id, data))
        }
        "terminal_resize" => {
            let state = app.state::<TerminalState>();
            let pty_id = required::<String>(&payload, &["ptyId", "pty_id"])?;
            let cols = required::<u16>(&payload, &["cols"])?;
            let rows = required::<u16>(&payload, &["rows"])?;
            to_json(crate::terminal::terminal_resize(state, pty_id, cols, rows))
        }
        "terminal_kill" => {
            let state = app.state::<TerminalState>();
            let pty_id = required::<String>(&payload, &["ptyId", "pty_id"])?;
            to_json(crate::terminal::terminal_kill(state, pty_id))
        }
        _ => Err(format!("未知命令: {}", command)),
    }
}

fn should_send_event_to_ws_client(
    event: &web_event_bus::WebEventEnvelope,
    expected_window_label: Option<&str>,
) -> bool {
    let Some(expected_label) = expected_window_label else {
        return false;
    };

    if event.event != "terminal-output" && event.event != "terminal-exit" {
        if event.event != "quick-command-event" {
            return true;
        }

        return event
            .payload
            .get("job")
            .and_then(|job| job.get("windowLabel"))
            .and_then(Value::as_str)
            .map(|actual| actual == expected_label)
            .unwrap_or(false);
    }

    event
        .payload
        .get("windowLabel")
        .and_then(Value::as_str)
        .map(|actual| actual == expected_label)
        .unwrap_or(false)
}

impl PathGuard {
    fn from_app(app: &AppHandle) -> Result<Self, String> {
        let home_dir = app
            .path()
            .home_dir()
            .map_err(|error| format!("解析用户目录失败: {error}"))?;
        let app_state = crate::load_app_state(app.clone()).unwrap_or_else(|error| {
            log::warn!("加载 app_state 失败，路径校验将使用默认空配置: {}", error);
            crate::models::AppStateFile::default()
        });
        let mut roots = BTreeSet::new();
        for directory in app_state.directories {
            if let Some(path) = normalize_absolute_path(&directory, &home_dir) {
                roots.insert(canonical_or_normalized(path));
            }
        }
        for project_path in app_state.direct_project_paths {
            if let Some(path) = normalize_absolute_path(&project_path, &home_dir) {
                roots.insert(canonical_or_normalized(path));
            }
        }

        // 允许应用自身数据目录（shared scripts/cache/worktrees 等）作为内部可访问根。
        roots.insert(canonical_or_normalized(home_dir.join(".devhaven")));

        Ok(Self {
            home_dir,
            allowed_roots: roots.into_iter().collect(),
        })
    }

    fn ensure_allowed_path(&self, raw: &str, field: &str) -> Result<(), String> {
        let candidate = normalize_absolute_path(raw, &self.home_dir)
            .ok_or_else(|| format!("参数 {field} 非法：路径必须是绝对路径"))?;
        let candidate = canonical_or_normalized(candidate);
        let is_allowed = self
            .allowed_roots
            .iter()
            .any(|root| candidate.starts_with(root));
        if is_allowed {
            return Ok(());
        }

        Err(format!(
            "参数 {field} 越权：路径不在受管目录范围内 ({})",
            candidate.display()
        ))
    }

    fn ensure_under_home_path(&self, raw: &str, field: &str) -> Result<(), String> {
        let candidate = normalize_absolute_path(raw, &self.home_dir)
            .ok_or_else(|| format!("参数 {field} 非法：路径必须是绝对路径"))?;
        let candidate = canonical_or_normalized(candidate);
        if candidate == self.home_dir {
            return Err(format!(
                "参数 {field} 非法：不允许直接使用用户目录根路径 ({})",
                candidate.display()
            ));
        }
        if candidate.starts_with(&self.home_dir) {
            return Ok(());
        }
        Err(format!(
            "参数 {field} 非法：仅允许访问当前用户目录下的路径 ({})",
            candidate.display()
        ))
    }
}

fn normalize_absolute_path(raw: &str, home_dir: &Path) -> Option<PathBuf> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    let expanded = if trimmed == "~" {
        home_dir.to_path_buf()
    } else if let Some(rest) = trimmed.strip_prefix("~/") {
        home_dir.join(rest)
    } else {
        PathBuf::from(trimmed)
    };

    if !expanded.is_absolute() {
        return None;
    }

    Some(normalize_path_components(expanded))
}

fn normalize_path_components(path: PathBuf) -> PathBuf {
    let mut normalized = PathBuf::new();
    for component in path.components() {
        match component {
            Component::CurDir => {}
            Component::ParentDir => {
                normalized.pop();
            }
            other => normalized.push(other.as_os_str()),
        }
    }
    normalized
}

fn canonical_or_normalized(path: PathBuf) -> PathBuf {
    std::fs::canonicalize(&path).unwrap_or(path)
}

fn to_json<T: Serialize>(result: Result<T, String>) -> Result<Value, String> {
    match result {
        Ok(value) => {
            serde_json::to_value(value).map_err(|error| format!("序列化返回值失败: {}", error))
        }
        Err(error) => Err(error),
    }
}

fn required<T: DeserializeOwned>(payload: &Value, keys: &[&str]) -> Result<T, String> {
    let value = find_payload_value(payload, keys).ok_or_else(|| {
        if keys.is_empty() {
            "缺少参数".to_string()
        } else {
            format!("缺少参数: {}", keys[0])
        }
    })?;
    serde_json::from_value(value.clone())
        .map_err(|error| format!("参数解析失败 {}: {}", keys[0], error))
}

fn optional<T: DeserializeOwned>(payload: &Value, keys: &[&str]) -> Result<Option<T>, String> {
    let Some(value) = find_payload_value(payload, keys) else {
        return Ok(None);
    };
    if value.is_null() {
        return Ok(None);
    }
    serde_json::from_value(value.clone())
        .map(Some)
        .map_err(|error| format!("参数解析失败 {}: {}", keys[0], error))
}

fn find_payload_value<'a>(payload: &'a Value, keys: &[&str]) -> Option<&'a Value> {
    let object = payload.as_object()?;
    for key in keys {
        if let Some(value) = object.get(*key) {
            return Some(value);
        }
    }
    None
}
