mod oracle;

use axum::{
    extract,
    routing::{get, post},
    Json, Router,
};
use clap::Parser;
use num::{BigInt, BigUint, Num};
use oracle::*;
use serde::{Deserialize, Serialize};
use stark_vrf::{generate_public_key, BaseField, StarkVRF};
use std::str::FromStr;
use tokio::signal;
use tower_http::trace::TraceLayer;
use tracing::debug;

#[derive(Parser, Debug)]
#[command(version, about, long_about = None)]
struct Args {
    /// Secret key
    #[arg(short, long, required = true, help = "Secret key as hex string")]
    secret_key: String,

    /// Port
    #[arg(short, long, default_value = "3003")]
    port: u16,
}

fn format<T: std::fmt::Display>(v: T) -> String {
    let int = BigInt::from_str(&format!("{v}")).unwrap();
    format!("0x{}", int.to_str_radix(16))
}

#[derive(Debug, Serialize, Deserialize)]
struct InfoResult {
    public_key_x: String,
    public_key_y: String,
}

fn get_secret_key() -> BigUint {
    let args = Args::parse();
    BigUint::from_str_radix(
        args.secret_key
            .trim_start_matches("0x")
            .trim_start_matches("0X"),
        16,
    )
    .expect("unable to parse secret_key")
}

async fn vrf_info() -> Json<InfoResult> {
    let secret_key = get_secret_key();
    let public_key = generate_public_key(secret_key.into());

    Json(InfoResult {
        public_key_x: format(public_key.x),
        public_key_y: format(public_key.y),
    })
}

#[derive(Debug, Serialize, Deserialize)]
struct JsonResult {
    result: StarkVrfProof,
}

async fn stark_vrf(extract::Json(payload): extract::Json<StarkVrfRequest>) -> Json<JsonResult> {
    debug!("received payload {payload:?}");
    let secret_key = get_secret_key();
    let public_key = generate_public_key(secret_key.clone().into());

    println!("public key {public_key}");

    let seed: Vec<_> = payload
        .seed
        .iter()
        .map(|x| {
            let dec_string = BigInt::from_str_radix(&x[2..], 16).unwrap().to_string();
            println!("seed string {dec_string}");
            BaseField::from_str(&dec_string).unwrap()
        })
        .collect();

    let ecvrf = StarkVRF::new(public_key).unwrap();
    let proof = ecvrf.prove(&secret_key.into(), seed.as_slice()).unwrap();
    let sqrt_ratio_hint = ecvrf.hash_to_sqrt_ratio_hint(seed.as_slice());
    let rnd = ecvrf.proof_to_hash(&proof).unwrap();

    println!("proof gamma: {}", proof.0);
    println!("proof c: {}", proof.1);
    println!("proof s: {}", proof.2);
    println!("proof verify hint: {}", sqrt_ratio_hint);

    let result = StarkVrfProof {
        gamma_x: format(proof.0.x),
        gamma_y: format(proof.0.y),
        c: format(proof.1),
        s: format(proof.2),
        sqrt_ratio: format(sqrt_ratio_hint),
        rnd: format(rnd),
    };

    println!("result {result:?}");

    //let n = (payload.n as f64).sqrt() as u64;
    Json(JsonResult { result })
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args = Args::parse();

    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::DEBUG)
        .init();

    async fn index() -> &'static str {
        "OK"
    }

    let app = Router::new()
        .route("/", get(index))
        .route("/info", get(vrf_info))
        .route("/stark_vrf", post(stark_vrf))
        .layer(TraceLayer::new_for_http());

    let listener = tokio::net::TcpListener::bind(format!("0.0.0.0:{}", &args.port))
        .await
        .unwrap_or_else(|_| panic!("Failed to bind to port {}, port already in use by another process. Change the port or terminate the other process.", &args.port));

    debug!("Server started on http://0.0.0.0:{}", &args.port);

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
