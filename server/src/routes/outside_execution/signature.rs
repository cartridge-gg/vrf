// Delegates SNIP-12 message hashing to account_sdk:
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution.rs
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution_v2.rs
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution_v3.rs

use account_sdk::hash::MessageHashRev1;
use starknet::signers::{LocalWallet, Signer};
use starknet_crypto::Felt;

use crate::routes::outside_execution::types::OutsideExecution;

pub async fn sign_outside_execution(
    outside_execution: &OutsideExecution,
    chain_id: Felt,
    signer_address: Felt,
    signer: LocalWallet,
) -> Vec<Felt> {
    let hash = outside_execution.get_message_hash_rev_1(chain_id, signer_address);

    let signature = signer.sign_hash(&hash).await.unwrap();

    vec![signature.r, signature.s]
}
