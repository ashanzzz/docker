//! onedrive-multisync — Rust (Tokio + Axum) Supervisor & Self-Healing Gateway
//! Compiles to a ~4MB static musl binary designed to sit directly inside `driveone/onedrive:alpine`.

use axum::{
    extract::{Path as AxumPath, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use chrono::Utc;
use nix::sys::signal::{self, Signal};
use nix::unistd::Pid;
use regex::Regex;
use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    env,
    path::PathBuf,
    process::Stdio,
    sync::Arc,
    time::{Duration, Instant},
};
use tokio::{
    fs,
    io::{AsyncBufReadExt, BufReader},
    process::Command,
    sync::{Notify, RwLock},
};
use tracing::info;

const BACKOFF_SCHEDULE: [u64; 4] = [30, 60, 120, 300];
const MAX_TRANSIENT_RETRIES: u32 = 10;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum SyncStatus {
    Initializing,
    Syncing,
    Idle,
    DegradedRetrying,
    NetworkDown,
    AuthRequired,
    ErrorBlocked,
}

#[derive(Debug, Clone, Serialize)]
pub struct AccountSnapshot {
    pub account_id: String,
    pub sync_dir: String,
    pub status: SyncStatus,
    pub last_sync_time: Option<String>,
    pub retry_count: u32,
    pub error_message: Option<String>,
    #[serde(skip_serializing)]
    pub auth_url: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct HealthResponse {
    pub status: &'static str,
    pub uptime_seconds: u64,
}

#[derive(Debug, Serialize)]
pub struct AccountsListResponse {
    pub total: usize,
    pub healthy: usize,
    pub accounts: Vec<AccountSnapshot>,
}

#[derive(Debug, Serialize)]
pub struct AuthUrlResponse {
    pub account_id: String,
    pub auth_url: String,
}

#[derive(Debug, Deserialize)]
pub struct AuthCallbackRequest {
    pub response_url: String,
}

pub struct WorkerControl {
    pub snapshot: RwLock<AccountSnapshot>,
    pub config_dir: PathBuf,
    pub wake_notify: Notify,
    pub stop_notify: Notify,
}

pub struct AppState {
    pub start_instant: Instant,
    pub config_root: PathBuf,
    pub data_root: PathBuf,
    pub onedrive_bin: String,
    pub proxy_url: String,
    pub tg_bot_token: String,
    pub tg_chat_id: String,
    pub workers: RwLock<HashMap<String, Arc<WorkerControl>>>,
}

impl AppState {
    pub async fn reload_accounts(self: &Arc<Self>) -> (Vec<String>, Vec<String>) {
        let _ = fs::create_dir_all(&self.config_root).await;
        let _ = fs::create_dir_all(&self.data_root).await;

        let mut discovered = Vec::new();
        if let Ok(mut entries) = fs::read_dir(&self.config_root).await {
            while let Ok(Some(entry)) = entries.next_entry().await {
                if let Ok(ft) = entry.file_type().await {
                    if ft.is_dir() {
                        let name = entry.file_name().to_string_lossy().to_string();
                        if !name.starts_with('.') {
                            discovered.push(name);
                        }
                    }
                }
            }
        }
        discovered.sort();

        let mut added = Vec::new();
        let mut removed = Vec::new();
        let mut map = self.workers.write().await;

        let existing_keys: Vec<String> = map.keys().cloned().collect();
        for key in existing_keys {
            if !discovered.contains(&key) {
                if let Some(ctrl) = map.remove(&key) {
                    ctrl.stop_notify.notify_waiters();
                    removed.push(key);
                }
            }
        }

        for acc_id in discovered {
            if !map.contains_key(&acc_id) {
                let config_dir = self.config_root.join(&acc_id);
                let sync_dir = self.data_root.join(format!("OneDrive-{}", acc_id));
                let ctrl = Arc::new(WorkerControl {
                    snapshot: RwLock::new(AccountSnapshot {
                        account_id: acc_id.clone(),
                        sync_dir: sync_dir.to_string_lossy().to_string(),
                        status: SyncStatus::Initializing,
                        last_sync_time: None,
                        retry_count: 0,
                        error_message: None,
                        auth_url: None,
                    }),
                    config_dir,
                    wake_notify: Notify::new(),
                    stop_notify: Notify::new(),
                });
                map.insert(acc_id.clone(), ctrl.clone());
                let state_clone = self.clone();
                tokio::spawn(async move {
                    run_account_worker(state_clone, ctrl).await;
                });
                added.push(acc_id);
            }
        }

        (added, removed)
    }

    pub async fn send_telegram_alert(&self, account_id: &str, status: &str, detail: &str, auth_url: Option<&str>) {
        if self.tg_bot_token.is_empty() || self.tg_chat_id.is_empty() {
            return;
        }
        let mut text = format!(
            "🚨 *[OneDrive-MultiSync 状态告警]*\n• *账号 ID*: `{}`\n• *状态*: `{}`\n• *详情*: `{}`",
            account_id, status, detail
        );
        if let Some(url) = auth_url {
            text.push_str(&format!(
                "\n\n👉 [点击直达微软官方登录授权]({})\n回调提交接口: `POST /api/v1/accounts/{}/auth-callback`",
                url, account_id
            ));
        }
        let api_url = format!("https://api.telegram.org/bot{}/sendMessage", self.tg_bot_token);
        let mut client_builder = reqwest::Client::builder().timeout(Duration::from_secs(10));
        if !self.proxy_url.is_empty() {
            if let Ok(proxy) = reqwest::Proxy::all(&self.proxy_url) {
                client_builder = client_builder.proxy(proxy);
            }
        }
        if let Ok(client) = client_builder.build() {
            let _ = client
                .post(&api_url)
                .json(&serde_json::json!({
                    "chat_id": self.tg_chat_id,
                    "text": text,
                    "parse_mode": "Markdown",
                    "disable_web_page_preview": true
                }))
                .send()
                .await;
        }
    }
}

async fn run_account_worker(app: Arc<AppState>, ctrl: Arc<WorkerControl>) {
    let acc_id = { ctrl.snapshot.read().await.account_id.clone() };
    let sync_dir = PathBuf::from(&ctrl.snapshot.read().await.sync_dir);

    if let Err(e) = fs::create_dir_all(&ctrl.config_dir).await.and(fs::create_dir_all(&sync_dir).await) {
        let mut snap = ctrl.snapshot.write().await;
        snap.status = SyncStatus::ErrorBlocked;
        snap.error_message = Some(format!("Filesystem initialization error: {}", e));
        return;
    }

    let cfg_file = ctrl.config_dir.join("config");
    if !cfg_file.exists() {
        let mut cfg_content = format!(
            "sync_dir = \"{}\"\nmonitor_interval = \"45\"\nskip_dotfiles = \"true\"\ncheck_nosync = \"true\"\n",
            sync_dir.display()
        );
        if !app.proxy_url.is_empty() {
            cfg_content.push_str(&format!("http_proxy = \"{}\"\n", app.proxy_url));
        }
        let _ = fs::write(&cfg_file, cfg_content).await;
    }

    let auth_re = Regex::new(r"(?i)(401\s+Unauthorized|invalid_grant|AADSTS|token\s+expired|Enter\s+the\s+response\s+uri)").unwrap();
    let net_re = Regex::new(r"(?i)(50[0234]\s+|429\s+Too\s+Many|Could\s+not\s+resolve|Connection\s+timed\s+out|proxy\s+error)").unwrap();
    let disk_re = Regex::new(r"(?i)(No\s+space\s+left|Read-only\s+file\s+system|Permission\s+denied|SQLite\s+error:\s+disk\s+I/O)").unwrap();

    loop {
        let auth_url_file = ctrl.config_dir.join(".auth_url");
        let resp_url_file = ctrl.config_dir.join(".response_url");
        let auth_files_arg = format!("{}:{}", auth_url_file.display(), resp_url_file.display());

        let mut cmd = Command::new(&app.onedrive_bin);
        cmd.arg("--monitor")
            .arg("--confdir")
            .arg(&ctrl.config_dir)
            .arg("--syncdir")
            .arg(&sync_dir)
            .arg("--auth-files")
            .arg(&auth_files_arg)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        if !app.proxy_url.is_empty() {
            cmd.env("HTTP_PROXY", &app.proxy_url)
                .env("HTTPS_PROXY", &app.proxy_url)
                .env("NO_PROXY", "localhost,127.0.0.1,192.168.0.0/16,10.0.0.0/8");
        }

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                let mut snap = ctrl.snapshot.write().await;
                snap.status = SyncStatus::ErrorBlocked;
                snap.error_message = Some(format!("Failed to spawn onedrive binary: {}", e));
                return;
            }
        };

        if let Some(stdout) = child.stdout.take() {
            let mut reader = BufReader::new(stdout).lines();
            loop {
                tokio::select! {
                    _ = ctrl.stop_notify.notified() => {
                        if let Some(pid) = child.id() {
                            let _ = signal::kill(Pid::from_raw(pid as i32), Signal::SIGTERM);
                        }
                        let _ = child.wait().await;
                        return;
                    }
                    line_res = reader.next_line() => {
                        match line_res {
                            Ok(Some(line)) => {
                                if disk_re.is_match(&line) {
                                    let mut snap = ctrl.snapshot.write().await;
                                    snap.status = SyncStatus::ErrorBlocked;
                                    snap.error_message = Some(line);
                                } else if auth_re.is_match(&line) {
                                    let url_opt = fs::read_to_string(&auth_url_file).await.ok().map(|s| s.trim().to_string());
                                    let already_auth = {
                                        let mut snap = ctrl.snapshot.write().await;
                                        let was_auth = snap.status == SyncStatus::AuthRequired;
                                        snap.status = SyncStatus::AuthRequired;
                                        snap.retry_count = 0;
                                        if !was_auth {
                                            snap.error_message = Some("Token expired (invalid_grant)".to_string());
                                        }
                                        if url_opt.is_some() {
                                            snap.auth_url = url_opt.clone();
                                        }
                                        was_auth
                                    };
                                    if !already_auth {
                                        app.send_telegram_alert(&acc_id, "AUTH_REQUIRED", "Token expired (invalid_grant)", url_opt.as_deref()).await;
                                    }
                                } else if net_re.is_match(&line) {
                                    let mut snap = ctrl.snapshot.write().await;
                                    snap.error_message = Some(line);
                                } else if line.contains("Sync with Microsoft OneDrive is complete") {
                                    let mut snap = ctrl.snapshot.write().await;
                                    snap.status = SyncStatus::Idle;
                                    snap.retry_count = 0;
                                    snap.error_message = None;
                                    snap.last_sync_time = Some(Utc::now().to_rfc3339());
                                } else if line.contains("Starting a sync") || line.contains("Uploading") || line.contains("Downloading") {
                                    let mut snap = ctrl.snapshot.write().await;
                                    snap.status = SyncStatus::Syncing;
                                    snap.retry_count = 0;
                                    snap.error_message = None;
                                    snap.last_sync_time = Some(Utc::now().to_rfc3339());
                                }
                            }
                            _ => break,
                        }
                    }
                }
            }
        }

        let _ = child.wait().await;
        let current_status = { ctrl.snapshot.read().await.status };
        if current_status == SyncStatus::ErrorBlocked {
            return;
        }
        if current_status == SyncStatus::AuthRequired {
            ctrl.wake_notify.notified().await;
            continue;
        }

        let (delay_secs, hit_net_down, retry_cnt, err_str) = {
            let mut snap = ctrl.snapshot.write().await;
            snap.retry_count += 1;
            let err_s = snap.error_message.clone().unwrap_or_else(|| "Transient connection failure".to_string());
            if snap.retry_count > MAX_TRANSIENT_RETRIES {
                snap.status = SyncStatus::NetworkDown;
                (BACKOFF_SCHEDULE[BACKOFF_SCHEDULE.len() - 1], true, snap.retry_count, err_s)
            } else {
                snap.status = SyncStatus::DegradedRetrying;
                let idx = (snap.retry_count as usize - 1).min(BACKOFF_SCHEDULE.len() - 1);
                (BACKOFF_SCHEDULE[idx], false, snap.retry_count, err_s)
            }
        };

        if hit_net_down {
            app.send_telegram_alert(&acc_id, "NETWORK_DOWN", &format!("Retries={} ({})", retry_cnt, err_str), None).await;
        }

        tokio::select! {
            _ = tokio::time::sleep(Duration::from_secs(delay_secs)) => {}
            _ = ctrl.wake_notify.notified() => {}
            _ = ctrl.stop_notify.notified() => return,
        }
    }
}

async fn health_handler(State(app): State<Arc<AppState>>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        uptime_seconds: app.start_instant.elapsed().as_secs(),
    })
}

async fn list_accounts_handler(State(app): State<Arc<AppState>>) -> Json<AccountsListResponse> {
    let map = app.workers.read().await;
    let mut accounts = Vec::with_capacity(map.len());
    let mut healthy = 0;
    for ctrl in map.values() {
        let snap = ctrl.snapshot.read().await.clone();
        if matches!(snap.status, SyncStatus::Syncing | SyncStatus::Idle) {
            healthy += 1;
        }
        accounts.push(snap);
    }
    accounts.sort_by(|a, b| a.account_id.cmp(&b.account_id));
    Json(AccountsListResponse {
        total: accounts.len(),
        healthy,
        accounts,
    })
}

async fn get_auth_url_handler(
    AxumPath(account_id): AxumPath<String>,
    State(app): State<Arc<AppState>>,
) -> Result<Json<AuthUrlResponse>, (StatusCode, Json<serde_json::Value>)> {
    let map = app.workers.read().await;
    let Some(ctrl) = map.get(&account_id) else {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({"error": "Account not found"}))));
    };
    let snap = ctrl.snapshot.read().await;
    let auth_url = snap.auth_url.clone().unwrap_or_else(|| {
        "https://login.microsoftonline.com/common/oauth2/v2.0/authorize?client_id=d50ca740-c83f-4d1b-b616-12c519384f0c&scope=Files.ReadWrite%20Files.ReadWrite.All%20Sites.ReadWrite.All%20offline_access&response_type=code&prompt=login&redirect_uri=https://login.microsoftonline.com/common/oauth2/nativeclient".to_string()
    });
    Ok(Json(AuthUrlResponse { account_id, auth_url }))
}

async fn post_auth_callback_handler(
    AxumPath(account_id): AxumPath<String>,
    State(app): State<Arc<AppState>>,
    Json(payload): Json<AuthCallbackRequest>,
) -> Result<Json<serde_json::Value>, (StatusCode, Json<serde_json::Value>)> {
    if !payload.response_url.contains("code=") {
        return Err((StatusCode::BAD_REQUEST, Json(serde_json::json!({"error": "Missing code= parameter"}))));
    }
    let map = app.workers.read().await;
    let Some(ctrl) = map.get(&account_id) else {
        return Err((StatusCode::NOT_FOUND, Json(serde_json::json!({"error": "Account not found"}))));
    };
    let tmp_file = ctrl.config_dir.join(".response_url.tmp");
    let resp_file = ctrl.config_dir.join(".response_url");
    let _ = fs::write(&tmp_file, format!("{}\n", payload.response_url.trim())).await;
    let _ = fs::rename(&tmp_file, &resp_file).await;
    ctrl.wake_notify.notify_waiters();
    Ok(Json(serde_json::json!({"account_id": account_id, "status": "accepted"})))
}

async fn reload_handler(State(app): State<Arc<AppState>>) -> Json<serde_json::Value> {
    let (added, removed) = app.reload_accounts().await;
    Json(serde_json::json!({
        "status": "reloaded",
        "added": added,
        "removed": removed,
    }))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    let app_state = Arc::new(AppState {
        start_instant: Instant::now(),
        config_root: PathBuf::from(env::var("CONFIG_DIR").unwrap_or_else(|_| "/config".to_string())),
        data_root: PathBuf::from(env::var("DATA_DIR").unwrap_or_else(|_| "/data".to_string())),
        onedrive_bin: env::var("ONEDRIVE_BIN").unwrap_or_else(|_| "onedrive".to_string()),
        proxy_url: env::var("HTTPS_PROXY").unwrap_or_else(|_| "http://192.168.8.11:7890".to_string()),
        tg_bot_token: env::var("TG_BOT_TOKEN").unwrap_or_default(),
        tg_chat_id: env::var("TG_CHAT_ID").unwrap_or_default(),
        workers: RwLock::new(HashMap::new()),
    });

    app_state.reload_accounts().await;

    let app = Router::new()
        .route("/health", get(health_handler))
        .route("/api/v1/accounts", get(list_accounts_handler))
        .route("/api/v1/accounts/:account_id/auth-url", get(get_auth_url_handler))
        .route("/api/v1/accounts/:account_id/auth-callback", post(post_auth_callback_handler))
        .route("/api/v1/reload", post(reload_handler))
        .with_state(app_state.clone());

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await.unwrap();
    info!("onedrive-multisync (Rust/Axum) listening on 0.0.0.0:8080");
    axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            let _ = tokio::signal::ctrl_c().await;
            info!("Graceful shutdown signal received; notifying all onedrive workers...");
            let map = app_state.workers.read().await;
            for ctrl in map.values() {
                ctrl.stop_notify.notify_waiters();
            }
            tokio::time::sleep(Duration::from_secs(2)).await;
        })
        .await
        .unwrap();
}
