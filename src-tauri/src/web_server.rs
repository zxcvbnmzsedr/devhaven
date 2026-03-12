use std::env;
use std::net::TcpListener as StdTcpListener;
use std::path::{Component, Path, PathBuf};
use std::str::FromStr;
use std::sync::{Arc, Mutex};
use std::collections::HashSet;

use axum::body::Body;
use axum::extract::rejection::JsonRejection;
use axum::extract::{Path as AxumPath, Query, State, WebSocketUpgrade, ws::Message, ws::WebSocket};
use axum::http::StatusCode;
use axum::http::header::{self, HeaderValue};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde::Serialize;
use serde_json::Value;
use tauri::AppHandle;
use tokio::sync::oneshot;
use tower_http::cors::CorsLayer;

use crate::command_catalog::{WebApiError, dispatch_web_command};
use crate::web_event_bus;

const DEFAULT_WEB_HOST: &str = "0.0.0.0";
const DEFAULT_WEB_PORT: u16 = 3210;
const DEFAULT_WEB_ENABLED: bool = true;

#[derive(Clone)]
struct WebServerState {
    app: AppHandle,
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
        return WebApiError::internal("asset_missing", format!("前端资源缺失: {}", path))
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
    payload: Result<Json<Value>, JsonRejection>,
) -> Response {
    let payload = match payload {
        Ok(Json(payload)) => payload,
        Err(error) => {
            return WebApiError::bad_request(
                "invalid_json",
                format!("请求体不是合法 JSON: {}", error.body_text()),
            )
            .into_response();
        }
    };
    let app = state.app.clone();
    let dispatch_result =
        tokio::task::spawn_blocking(move || dispatch_web_command(&app, &command, payload)).await;

    match dispatch_result {
        Ok(Ok(data)) => (StatusCode::OK, Json(data)).into_response(),
        Ok(Err(error)) => error.into_response(),
        Err(error) => WebApiError::internal(
            "command_dispatch_failed",
            format!("后台命令执行失败: {}", error),
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
        return WebApiError::bad_request(
            "missing_window_label",
            "缺少 windowLabel 查询参数",
        )
        .into_response();
    };
    ws.on_upgrade(move |socket| handle_websocket(socket, Some(window_label)))
        .into_response()
}

async fn handle_websocket(mut socket: WebSocket, window_label: Option<String>) {
    let mut rx = web_event_bus::subscribe();
    let mut subscribed_events: HashSet<String> = HashSet::new();

    loop {
        tokio::select! {
            result = rx.recv() => {
                let Ok(event) = result else {
                    continue;
                };
                if !should_send_event_to_ws_client(&event, window_label.as_deref(), &subscribed_events) {
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
                    Some(Ok(Message::Text(text))) => {
                        if let Ok(message) = serde_json::from_str::<serde_json::Value>(&text) {
                            if message.get("type").and_then(|value| value.as_str()) == Some("subscribe") {
                                subscribed_events.clear();
                                if let Some(events) = message.get("events").and_then(|value| value.as_array()) {
                                    subscribed_events.extend(events.iter().filter_map(|value| value.as_str().map(|item| item.to_string())));
                                }
                            }
                        }
                    }
                    Some(Ok(_)) => {}
                    Some(Err(_)) => break,
                }
            }
        }
    }
}


fn should_send_event_to_ws_client(
    event: &web_event_bus::WebEventEnvelope,
    _expected_window_label: Option<&str>,
    subscribed_events: &HashSet<String>,
) -> bool {
    subscribed_events.contains(&event.event)
}

#[cfg(test)]
mod tests {
    use super::should_send_event_to_ws_client;
    use crate::web_event_bus::WebEventEnvelope;
    use serde_json::json;
    use std::collections::HashSet;

    fn envelope(event: &str) -> WebEventEnvelope {
        WebEventEnvelope {
            event: event.to_string(),
            payload: json!({}),
            ts: 0,
        }
    }

    #[test]
    fn websocket_client_requires_explicit_subscription_for_scoped_events() {
        let subscribed_events = HashSet::from([
            "terminal-pane-output:session-1".to_string(),
            "quick-command-state-changed".to_string(),
        ]);

        assert!(should_send_event_to_ws_client(
            &envelope("terminal-pane-output:session-1"),
            Some("main"),
            &subscribed_events,
        ));
        assert!(should_send_event_to_ws_client(
            &envelope("quick-command-state-changed"),
            Some("main"),
            &subscribed_events,
        ));
        assert!(!should_send_event_to_ws_client(
            &envelope("terminal-output"),
            Some("main"),
            &subscribed_events,
        ));
        assert!(!should_send_event_to_ws_client(
            &envelope("quick-command-event"),
            Some("main"),
            &subscribed_events,
        ));
    }

    #[test]
    fn websocket_client_without_subscriptions_does_not_receive_runtime_events() {
        let subscribed_events = HashSet::new();
        assert!(!should_send_event_to_ws_client(
            &envelope("terminal-pane-output:session-1"),
            Some("main"),
            &subscribed_events,
        ));
        assert!(!should_send_event_to_ws_client(
            &envelope("quick-command-state-changed"),
            Some("main"),
            &subscribed_events,
        ));
    }
}
