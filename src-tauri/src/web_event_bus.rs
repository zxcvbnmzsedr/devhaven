use std::sync::OnceLock;

use chrono::Utc;
use serde::Serialize;
use serde_json::Value;
use tokio::sync::broadcast;

const WEB_EVENT_CHANNEL_SIZE: usize = 1024;

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WebEventEnvelope {
    pub event: String,
    pub payload: Value,
    pub ts: i64,
}

fn event_sender() -> &'static broadcast::Sender<WebEventEnvelope> {
    static EVENT_SENDER: OnceLock<broadcast::Sender<WebEventEnvelope>> = OnceLock::new();
    EVENT_SENDER.get_or_init(|| {
        let (tx, _rx) = broadcast::channel(WEB_EVENT_CHANNEL_SIZE);
        tx
    })
}

/// 发布一个 Web 事件到全局广播总线。
pub fn publish<T: Serialize>(event: &str, payload: T) {
    let payload = match serde_json::to_value(payload) {
        Ok(value) => value,
        Err(error) => {
            log::warn!("序列化 Web 事件失败 event={}: {}", event, error);
            return;
        }
    };

    let envelope = WebEventEnvelope {
        event: event.to_string(),
        payload,
        ts: Utc::now().timestamp_millis(),
    };

    let _ = event_sender().send(envelope);
}

/// 订阅 Web 事件总线。
pub fn subscribe() -> broadcast::Receiver<WebEventEnvelope> {
    event_sender().subscribe()
}
