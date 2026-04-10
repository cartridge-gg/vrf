// Delegates SNIP-12 message hashing to account_sdk:
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution.rs
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution_v2.rs
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution_v3.rs

use account_sdk::account::outside_execution::OutsideExecution as SdkOutsideExecution;
use account_sdk::account::outside_execution_v2::OutsideExecutionV2 as SdkOutsideExecutionV2;
use account_sdk::hash::MessageHashRev1;
use cainome_cairo_serde::ContractAddress;
use starknet::signers::{LocalWallet, Signer};
use starknet_crypto::Felt;

use crate::routes::outside_execution::types::OutsideExecution;

/// Convert local OutsideExecution to account_sdk's type for hashing.
fn to_sdk_outside_execution(outside_execution: &OutsideExecution) -> SdkOutsideExecution {
    match outside_execution {
        OutsideExecution::V2(v2) => SdkOutsideExecution::V2(SdkOutsideExecutionV2 {
            caller: ContractAddress(v2.caller),
            nonce: v2.nonce,
            execute_after: v2.execute_after,
            execute_before: v2.execute_before,
            calls: v2
                .calls
                .iter()
                .map(|c| {
                    let starknet_call: starknet::core::types::Call = c.clone().into();
                    starknet_call.into()
                })
                .collect(),
        }),
        OutsideExecution::V3(v3) => {
            SdkOutsideExecution::V3(account_sdk::abigen::controller::OutsideExecutionV3 {
                caller: ContractAddress(v3.caller),
                nonce: (v3.nonce.0, v3.nonce.1),
                execute_after: v3.execute_after,
                execute_before: v3.execute_before,
                calls: v3
                    .calls
                    .iter()
                    .map(|c| {
                        let starknet_call: starknet::core::types::Call = c.clone().into();
                        starknet_call.into()
                    })
                    .collect(),
            })
        }
    }
}

pub async fn sign_outside_execution(
    outside_execution: &OutsideExecution,
    chain_id: Felt,
    signer_address: Felt,
    signer: LocalWallet,
) -> Vec<Felt> {
    let sdk_outside_execution = to_sdk_outside_execution(outside_execution);
    let hash = sdk_outside_execution.get_message_hash_rev_1(chain_id, signer_address);

    let signature = signer.sign_hash(&hash).await.unwrap();

    vec![signature.r, signature.s]
}
