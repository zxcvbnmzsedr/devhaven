use std::sync::{
    Arc, Mutex,
    atomic::{AtomicUsize, Ordering},
};

use tauri::{AppHandle, Emitter};

use crate::models::InteractionLockPayload;

pub const INTERACTION_LOCK_EVENT: &str = "interaction-lock";

/// 全局交互锁：用于在关键流程（例如 worktree 创建）期间拦截所有窗口交互与关闭请求。
///
/// - 支持嵌套锁（计数器 > 0 即视为锁定）
/// - 锁定/解锁时向所有窗口广播 `interaction-lock` 事件
#[derive(Clone, Default)]
pub struct InteractionLockState {
    counter: Arc<AtomicUsize>,
    reason: Arc<Mutex<Option<String>>>,
}

pub struct InteractionLockGuard {
    state: InteractionLockState,
    app: AppHandle,
}

impl InteractionLockState {
    pub fn is_locked(&self) -> bool {
        self.counter.load(Ordering::SeqCst) > 0
    }

    pub fn snapshot(&self) -> InteractionLockPayload {
        let locked = self.is_locked();
        let reason = self.reason.lock().ok().and_then(|value| value.clone());
        InteractionLockPayload { locked, reason }
    }

    pub fn lock(&self, app: &AppHandle, reason: Option<String>) -> InteractionLockGuard {
        let previous = self.counter.fetch_add(1, Ordering::SeqCst);
        if previous == 0 {
            if let Ok(mut stored) = self.reason.lock() {
                *stored = reason.clone();
            }
            let payload = InteractionLockPayload {
                locked: true,
                reason,
            };
            if let Err(error) = app.emit(INTERACTION_LOCK_EVENT, payload) {
                log::warn!("发送 interaction-lock 失败: {}", error);
            }
        }

        InteractionLockGuard {
            state: self.clone(),
            app: app.clone(),
        }
    }

    fn unlock_inner(&self, app: &AppHandle) {
        let current = self.counter.load(Ordering::SeqCst);
        if current == 0 {
            return;
        }

        let previous = self.counter.fetch_sub(1, Ordering::SeqCst);
        if previous != 1 {
            return;
        }

        if let Ok(mut stored) = self.reason.lock() {
            stored.take();
        }

        let payload = InteractionLockPayload {
            locked: false,
            reason: None,
        };
        if let Err(error) = app.emit(INTERACTION_LOCK_EVENT, payload) {
            log::warn!("发送 interaction-lock 失败: {}", error);
        }
    }
}

impl Drop for InteractionLockGuard {
    fn drop(&mut self) {
        self.state.unlock_inner(&self.app);
    }
}
