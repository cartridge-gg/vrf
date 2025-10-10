pub mod signature;
pub mod types;
pub mod vrf_types;

use crate::routes::outside_execution::signature::sign_outside_execution;
use crate::routes::outside_execution::types::{
    Call, NonceChannel, OutsideExecution, OutsideExecutionV2, OutsideExecutionV3,
    SignedOutsideExecution,
};
use crate::routes::outside_execution::vrf_types::{build_submit_random_call, RequestRandom};
use crate::state::SharedState;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use cainome_cairo_serde::CairoSerde;
use chrono::Utc;
use serde::{Deserialize, Serialize};
use starknet::core::types::Felt;
use starknet::macros::{felt, selector};
use starknet::providers::ProviderError;
use starknet::signers::{LocalWallet, SigningKey};
use tracing::debug;

const ANY_CALLER: Felt = felt!("0x414e595f43414c4c4552"); // ANY_CALLER

#[derive(Debug, Serialize, Deserialize)]
pub struct OutsideExecutionRequest {
    pub request: SignedOutsideExecution,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OutsideExecutionResult {
    pub result: SignedOutsideExecution,
}

// receive an OutsideExecution
// check for request_random
// build call [submit_random , execute_from_outside ]
// return signed OutsideExecution

pub async fn vrf_outside_execution(
    State(state): State<SharedState>,
    Json(payload): Json<OutsideExecutionRequest>,
) -> Result<Json<OutsideExecutionResult>, Errors> {
    debug!("received payload {payload:?}");

    let signed_outside_execution = payload.request.clone();
    let outside_execution = signed_outside_execution.outside_execution.clone();

    let (maybe_request_random_call, position) =
        RequestRandom::get_request_random_call(&outside_execution);

    if maybe_request_random_call.is_none() {
        return Err(Errors::NoRequestRandom);
    }
    if position == outside_execution.calls().len() {
        return Err(Errors::NoCallAfterRequestRandom);
    }

    let request_random_call = maybe_request_random_call.unwrap();
    let request_random = RequestRandom::cairo_deserialize(&request_random_call.calldata, 0)?;

    let seed = request_random.compute_seed(&state).await?;

    let sumbit_random_call = build_submit_random_call(&state, seed);
    let execute_from_outside_call = signed_outside_execution.build_execute_from_outside_call();

    debug!("request_random: {:?}", request_random);
    debug!("seed: {:?}", seed);

    let calls = vec![sumbit_random_call, execute_from_outside_call];
    let chain_id = state.read().unwrap().chain_id;
    let signer_address = state.read().unwrap().vrf_account_address;
    let signer = state.read().unwrap().vrf_signer.clone();

    let signed_outside_execution =
        build_signed_outside_execution_v2(signer_address.0, signer, chain_id, calls).await;

    Ok(Json(OutsideExecutionResult {
        result: signed_outside_execution,
    }))
}

pub async fn build_signed_outside_execution_v2(
    account_address: Felt,
    signer: LocalWallet,
    chain_id: Felt,
    calls: Vec<Call>,
) -> SignedOutsideExecution {
    let outside_execution = build_outside_execution_v2(calls);

    let signature =
        sign_outside_execution(&outside_execution, chain_id, account_address, signer).await;

    SignedOutsideExecution {
        address: account_address,
        outside_execution,
        signature,
    }
}
pub fn build_outside_execution_v2(calls: Vec<Call>) -> OutsideExecution {
    let now = Utc::now().timestamp() as u64;
    OutsideExecution::V2(OutsideExecutionV2 {
        caller: ANY_CALLER,
        execute_after: 0,
        execute_before: now + 600,
        calls,
        nonce: SigningKey::from_random().secret_scalar(),
    })
}

#[derive(Debug)]
pub enum Errors {
    NoRequestRandom,
    NoCallAfterRequestRandom,
    ProviderError(String),
    CairoSerdeError(String),
}

impl IntoResponse for Errors {
    fn into_response(self) -> axum::response::Response {
        match self {
            Errors::NoRequestRandom => (
                StatusCode::NOT_FOUND,
                Json("No request_random call".to_string()),
            )
                .into_response(),
            Errors::NoCallAfterRequestRandom => (
                StatusCode::NOT_FOUND,
                Json("No call after request_random".to_string()),
            )
                .into_response(),
            Errors::ProviderError(msg) => (
                StatusCode::NOT_FOUND,
                Json(format!("Provider error: {msg}").to_string()),
            )
                .into_response(),
            Errors::CairoSerdeError(msg) => (
                StatusCode::NOT_FOUND,
                Json(format!("Cairo serde error: {msg}").to_string()),
            )
                .into_response(),
        }
    }
}

impl From<ProviderError> for Errors {
    fn from(value: ProviderError) -> Self {
        Errors::ProviderError(value.to_string())
    }
}

impl From<cainome_cairo_serde::Error> for Errors {
    fn from(value: cainome_cairo_serde::Error) -> Self {
        Errors::CairoSerdeError(value.to_string())
    }
}

// curl -X POST -H "Content-Type: application/json" -d '{"request" : {"address":"0x111","outside_execution":{"V3":{"caller":"0x414e595f43414c4c4552","calls":[{"calldata":["0x111","0x0","0x222"],"selector":"0x12a5a2e008479001f8f1a5f6c61ab6536d5ce46571fcdc0c9300dca0a9e532f","to":"0x888"},{"calldata":[],"selector":"0x1f9ca87172ecd8343d776bdd6024a4028f5596c76320882abd93e3bd1c724eb","to":"0x111"}],"execute_after":"0x0","execute_before":"0xb2d05e00","nonce":["0x564b73282b2fb5f201cf2070bf0ca2526871cb7daa06e0e805521ef5d907b33","0xa"]}},"signature":["0x12345","0x67890"]}}' http://0.0.0.0:3000/outside_execution

#[test]
fn outside_execution_serialization() {
    let signed_outside_execution = SignedOutsideExecution {
        address: felt!("0x111"),
        outside_execution: OutsideExecution::V3(OutsideExecutionV3 {
            caller: ANY_CALLER,
            execute_after: 0,
            execute_before: 3000000000,
            calls: vec![
                Call {
                    to: felt!("0x888"), // VRF_ACCOUNT
                    selector: selector!("request_random"),
                    calldata: vec![
                        felt!("0x111"), // CONSUMER
                        felt!("0x0"),   // Source::Nonce
                        felt!("0x222"), // address
                    ],
                },
                Call {
                    to: felt!("0x111"),
                    selector: selector!("dice"),
                    calldata: vec![],
                },
            ],
            nonce: NonceChannel(
                felt!("0x564b73282b2fb5f201cf2070bf0ca2526871cb7daa06e0e805521ef5d907b33"),
                10,
            ),
        }),
        signature: vec![felt!("0x12345"), felt!("0x67890")],
    };

    let serialized = serde_json::to_value(signed_outside_execution).unwrap();

    println!("{serialized}");
}
