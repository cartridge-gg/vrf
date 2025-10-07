pub mod oracle;
pub mod routes;
pub mod state;
pub mod utils;

use std::sync::{Arc, RwLock};

use axum::{
    routing::{get, post},
    Router,
};
use clap::Parser;
use tokio::signal;
use tower_http::trace::TraceLayer;
use tracing::debug;

use crate::routes::outside_execution::vrf_outside_execution;
use crate::routes::proof::vrf_proof;
use crate::{routes::info::vrf_info, state::AppState};

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
pub struct Args {
    /// Secret key
    #[arg(short, long, required = true)]
    secret_key: u64,

    /// Account Address
    #[arg(long, required = true)]
    account_address: String,

    /// Account Private Key
    #[arg(long, required = true)]
    account_private_key: String,

    /// Account Private Key
    #[arg(long, required = true)]
    rpc_url: String,
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let app_state = AppState::from_args().await;
    let shared_state = Arc::new(RwLock::new(app_state));

    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    async fn index() -> &'static str {
        "OK"
    }

    let app = Router::new()
        .route("/", get(index))
        .route("/info", get(vrf_info))
        .route("/proof", post(vrf_proof))
        .route("/outside_execution", post(vrf_outside_execution))
        .layer(TraceLayer::new_for_http())
        .with_state(Arc::clone(&shared_state));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000")
        .await
        .expect("Failed to bind to port 3000, port already in use by another process. Change the port or terminate the other process.");

    debug!("Server started on http://0.0.0.0:3000");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

async fn shutdown_signal() {
    let ctrl_c = async {
        signal::ctrl_c()
            .await
            .expect("failed to install Ctrl+C handler");
    };

    #[cfg(unix)]
    let terminate = async {
        signal::unix::signal(signal::unix::SignalKind::terminate())
            .expect("failed to install signal handler")
            .recv()
            .await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}
