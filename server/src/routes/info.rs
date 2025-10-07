use crate::{state::SharedState, utils::format};
use axum::{extract::State, Json};
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct InfoResult {
    public_key_x: String,
    public_key_y: String,
}

// curl http://0.0.0.0:3000/info

pub async fn vrf_info(State(state): State<SharedState>) -> Json<InfoResult> {
    let public_key = state.read().unwrap().public_key;

    Json(InfoResult {
        public_key_x: format(public_key.x),
        public_key_y: format(public_key.y),
    })
}
