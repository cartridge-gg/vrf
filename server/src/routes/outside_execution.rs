use crate::utils::format_felt;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::Json;
use cainome::cairo_serde::{deserialize_from_hex, serialize_as_hex, ContractAddress};
use cainome::cairo_serde_derive::CairoSerde;
use cainome_cairo_serde::CairoSerde;
use chrono::Utc;
use num::{BigInt, Num};
use serde::{Deserialize, Serialize};
use stark_vrf::{BaseField, StarkVRF};
use starknet::core::types::BlockId;
use starknet::macros::felt;
use starknet::providers::{Provider, ProviderError};
use starknet::signers::{LocalWallet, Signer, SigningKey};
use starknet::{core::types::Felt, macros::selector};
use starknet_crypto::{pedersen_hash, poseidon_hash_many, PoseidonHasher};
use std::str::FromStr;
use tracing::debug;

use crate::state::SharedState;

// https://github.com/neotheprogramist/starknet-hive/blob/48d4446b2e8ccf4194242cbe0102107f9df8e26d/openrpc-testgen/src/utils/outside_execution.rs#L20

pub const STARKNET_DOMAIN_TYPE_HASH: Felt =
    Felt::from_hex_unchecked("0x1ff2f602e42168014d405a94f75e8a93d640751d71d16311266e140d8b0a210");
pub const CALL_TYPE_HASH: Felt =
    Felt::from_hex_unchecked("0x3635c7f2a7ba93844c0d064e18e487f35ab90f7c39d00f186a781fc3f0c2ca9");
pub const OUTSIDE_EXECUTION_TYPE_HASH: Felt =
    Felt::from_hex_unchecked("0x312b56c05a7965066ddbda31c016d8d05afc305071c0ca3cdc2192c3c2f1f0f");

#[derive(Debug, CairoSerde)]
pub struct StarknetDomain {
    pub name: Felt,
    pub version: Felt,
    pub chain_id: Felt,
    pub revision: Felt,
}

pub fn get_starknet_domain_hash(chain_id: Felt) -> Felt {
    let domain = StarknetDomain {
        name: Felt::from_bytes_be_slice(b"Account.execute_from_outside"),
        version: Felt::TWO,
        chain_id,
        revision: Felt::ONE,
    };

    let domain_vec = vec![
        STARKNET_DOMAIN_TYPE_HASH,
        domain.name,
        domain.version,
        domain.chain_id,
        domain.revision,
    ];
    poseidon_hash_many(&domain_vec)
}

pub fn get_outside_execution_hash(outside_execution: &OutsideExecution) -> Felt {
    let calls_vec = outside_execution.calls().clone();
    let mut hashed_calls = Vec::<Felt>::new();

    for call in calls_vec {
        hashed_calls.push(get_call_hash(call));
    }

    let mut hasher_outside_execution = PoseidonHasher::new();
    hasher_outside_execution.update(OUTSIDE_EXECUTION_TYPE_HASH);
    hasher_outside_execution.update(outside_execution.caller());
    hasher_outside_execution.update(outside_execution.nonce());
    hasher_outside_execution.update(Felt::from(outside_execution.execute_after()));
    hasher_outside_execution.update(Felt::from(outside_execution.execute_before()));
    hasher_outside_execution.update(poseidon_hash_many(&hashed_calls));

    hasher_outside_execution.finalize()
}

pub fn get_call_hash(call: Call) -> Felt {
    let mut hasher_call = PoseidonHasher::new();
    hasher_call.update(CALL_TYPE_HASH);
    hasher_call.update(call.to);
    hasher_call.update(call.selector);
    hasher_call.update(poseidon_hash_many(&call.calldata));
    hasher_call.finalize()
}

pub async fn sign_outside_execution(
    outside_execution: &OutsideExecution,
    chain_id: Felt,
    signer_address: Felt,
    signer: LocalWallet,
) -> Vec<Felt> {
    let mut final_hasher = PoseidonHasher::new();
    final_hasher.update(Felt::from_bytes_be_slice(b"StarkNet Message"));
    final_hasher.update(get_starknet_domain_hash(chain_id));
    final_hasher.update(signer_address);
    final_hasher.update(get_outside_execution_hash(outside_execution));

    let hash = final_hasher.finalize();

    let signature = signer.sign_hash(&hash).await.unwrap();

    vec![signature.r, signature.s]
}

//
//
//

/// A single call to be executed as part of an outside execution.
#[derive(Clone, CairoSerde, Serialize, Deserialize, PartialEq, Debug)]
pub struct Call {
    /// Contract address to call.
    pub to: Felt,
    /// Function selector to invoke.
    pub selector: Felt,
    /// Arguments to pass to the function.
    pub calldata: Vec<Felt>,
}

impl From<Call> for starknet::core::types::Call {
    fn from(val: Call) -> Self {
        starknet::core::types::Call {
            to: val.to,
            selector: val.selector,
            calldata: val.calldata,
        }
    }
}
impl From<starknet::core::types::Call> for Call {
    fn from(val: starknet::core::types::Call) -> Self {
        Call {
            to: val.to,
            selector: val.selector,
            calldata: val.calldata,
        }
    }
}

/// Nonce channel
#[derive(Clone, CairoSerde, PartialEq, Debug, Serialize, Deserialize)]
pub struct NonceChannel(
    Felt,
    #[serde(
        serialize_with = "serialize_as_hex",
        deserialize_with = "deserialize_from_hex"
    )]
    u128,
);

/// Outside execution version 2 (SNIP-9 standard).
#[derive(Clone, CairoSerde, Serialize, Deserialize, PartialEq, Debug)]
pub struct OutsideExecutionV2 {
    /// Address allowed to initiate execution ('ANY_CALLER' for unrestricted).
    pub caller: Felt,
    /// Unique nonce to prevent signature reuse.
    pub nonce: Felt,
    /// Timestamp after which execution is valid.
    #[serde(
        serialize_with = "serialize_as_hex",
        deserialize_with = "deserialize_from_hex"
    )]
    pub execute_after: u64,
    /// Timestamp before which execution is valid.
    #[serde(
        serialize_with = "serialize_as_hex",
        deserialize_with = "deserialize_from_hex"
    )]
    pub execute_before: u64,
    /// Calls to execute in order.
    pub calls: Vec<Call>,
}

/// Non-standard extension of the [`OutsideExecutionV2`] supported by the Cartridge Controller.
#[derive(Clone, CairoSerde, Serialize, Deserialize, PartialEq, Debug)]
pub struct OutsideExecutionV3 {
    /// Address allowed to initiate execution ('ANY_CALLER' for unrestricted).
    pub caller: Felt,
    /// Nonce.
    pub nonce: NonceChannel,
    /// Timestamp after which execution is valid.
    #[serde(
        serialize_with = "serialize_as_hex",
        deserialize_with = "deserialize_from_hex"
    )]
    pub execute_after: u64,
    /// Timestamp before which execution is valid.
    #[serde(
        serialize_with = "serialize_as_hex",
        deserialize_with = "deserialize_from_hex"
    )]
    pub execute_before: u64,
    /// Calls to execute in order.
    pub calls: Vec<Call>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
// #[serde(untagged)]
pub enum OutsideExecution {
    /// SNIP-9 standard version.
    V2(OutsideExecutionV2),
    /// Cartridge/Controller extended version.
    V3(OutsideExecutionV3),
}

impl OutsideExecution {
    fn calls(self: &OutsideExecution) -> Vec<Call> {
        match self {
            OutsideExecution::V2(outside_execution_v2) => outside_execution_v2.calls.clone(),
            OutsideExecution::V3(outside_execution_v3) => outside_execution_v3.calls.clone(),
        }
    }
    fn selector(self: &OutsideExecution) -> Felt {
        match self {
            OutsideExecution::V2(_) => selector!("execute_from_outside_v2"),
            OutsideExecution::V3(_) => selector!("execute_from_outside_v3"),
        }
    }
    fn caller(self: &OutsideExecution) -> Felt {
        match self {
            OutsideExecution::V2(outside_execution_v2) => outside_execution_v2.caller,
            OutsideExecution::V3(outside_execution_v3) => outside_execution_v3.caller,
        }
    }
    fn nonce(self: &OutsideExecution) -> Felt {
        match self {
            OutsideExecution::V2(outside_execution_v2) => outside_execution_v2.nonce,
            OutsideExecution::V3(_) => {
                unreachable!()
            }
        }
    }
    fn execute_after(self: &OutsideExecution) -> u64 {
        match self {
            OutsideExecution::V2(outside_execution_v2) => outside_execution_v2.execute_after,
            OutsideExecution::V3(outside_execution_v3) => outside_execution_v3.execute_after,
        }
    }
    fn execute_before(self: &OutsideExecution) -> u64 {
        match self {
            OutsideExecution::V2(outside_execution_v2) => outside_execution_v2.execute_before,
            OutsideExecution::V3(outside_execution_v3) => outside_execution_v3.execute_before,
        }
    }
}

impl SignedOutsideExecution {
    pub fn build_execute_from_outside_call(self: &SignedOutsideExecution) -> Call {
        let outside_execution = self.outside_execution.clone();

        let mut calldata = match outside_execution.clone() {
            OutsideExecution::V2(outside_execution_v2) => {
                OutsideExecutionV2::cairo_serialize(&outside_execution_v2)
            }
            OutsideExecution::V3(outside_execution_v3) => {
                OutsideExecutionV3::cairo_serialize(&outside_execution_v3)
            }
        };

        calldata.push(self.signature.len().into());
        calldata.extend(self.signature.clone());

        Call {
            to: self.address,
            selector: outside_execution.selector(),
            calldata,
        }
    }
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct SignedOutsideExecution {
    pub address: Felt,
    pub outside_execution: OutsideExecution,
    pub signature: Vec<Felt>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OutsideExecutionRequest {
    pub request: SignedOutsideExecution,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct OutsideExecutionResult {
    pub result: SignedOutsideExecution,
}

// VRF

#[derive(Clone, CairoSerde, Serialize, Deserialize, Debug)]
pub enum Source {
    Nonce(ContractAddress),
    Salt(Felt),
}

#[derive(Clone, CairoSerde, Serialize, Deserialize, Debug)]
pub struct RequestRandom {
    pub caller: ContractAddress,
    pub source: Source,
}

impl RequestRandom {
    fn get_request_random_call(outside_execution: &OutsideExecution) -> (Option<Call>, usize) {
        let calls = outside_execution.calls();

        let position = calls
            .iter()
            .position(|call| call.selector == selector!("request_random"));

        match position {
            Some(position) => (Option::Some(calls.get(position).unwrap().clone()), position),
            None => (Option::None, 0),
        }
    }

    async fn compute_seed(self: &RequestRandom, state: &SharedState) -> Result<Felt, Errors> {
        let caller = self.caller.0;
        let chain_id = state.read().unwrap().chain_id;

        let seed = match self.source {
            Source::Nonce(contract_address) => {
                let provider = state.read().unwrap().provider.clone();
                let vrf_account_address = state.read().unwrap().vrf_account_address;

                let key = pedersen_hash(&selector!("VrfProvider_nonces"), &contract_address.0);
                let nonce = provider
                    .get_storage_at(
                        vrf_account_address.0,
                        key,
                        BlockId::Tag(starknet::core::types::BlockTag::PreConfirmed),
                    )
                    .await?;

                poseidon_hash_many(&[nonce, contract_address.0, caller, chain_id])
            }
            Source::Salt(felt) => poseidon_hash_many(&[felt, caller, chain_id]),
        };

        Ok(seed)
    }
}

pub fn build_submit_random_call(state: &SharedState, seed: Felt) -> Call {
    let secret_key = &state.read().unwrap().secret_key;
    let public_key = state.read().unwrap().public_key;
    let vrf_account_address = state.read().unwrap().vrf_account_address;

    let seed_vec: Vec<_> = [seed]
        .iter()
        .map(|x| {
            let x = x.to_hex_string();
            let dec_string = BigInt::from_str_radix(&x[2..], 16).unwrap().to_string();
            BaseField::from_str(&dec_string).unwrap()
        })
        .collect();

    let ecvrf = StarkVRF::new(public_key).unwrap();
    let proof = ecvrf
        .prove(&secret_key.parse().unwrap(), seed_vec.as_slice())
        .unwrap();
    let sqrt_ratio_hint = ecvrf.hash_to_sqrt_ratio_hint(seed_vec.as_slice());
    // let rnd = ecvrf.proof_to_hash(&proof).unwrap();

    Call {
        to: vrf_account_address.0,
        selector: selector!("submit_random"),
        calldata: vec![
            seed,
            format_felt(proof.0.x),
            format_felt(proof.0.y),
            format_felt(proof.1),
            format_felt(proof.2),
            format_felt(sqrt_ratio_hint),
        ],
    }
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

const ANY_CALLER: Felt = felt!("0x414e595f43414c4c4552"); // ANY_CALLER

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
