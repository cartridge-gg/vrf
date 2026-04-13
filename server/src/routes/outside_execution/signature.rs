// Delegates SNIP-12 message hashing to account_sdk:
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution.rs
// https://github.com/cartridge-gg/controller-rs/blob/main/account_sdk/src/account/outside_execution_v2.rs

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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::routes::outside_execution::types::{Call, OutsideExecutionV2};
    use cainome_cairo_serde::ContractAddress;
    use starknet::macros::{felt, selector};
    use starknet::signers::SigningKey;

    const TEST_CHAIN_ID: Felt = felt!("0x57505f4b4154414e41"); // WP_KATANA
    const TEST_CALLER: ContractAddress = ContractAddress(felt!("0x414e595f43414c4c4552"));
    const TEST_SIGNER_ADDRESS: Felt = felt!("0x123");

    fn test_signing_key() -> SigningKey {
        SigningKey::from_secret_scalar(felt!("0xbeef"))
    }

    fn test_signer() -> LocalWallet {
        LocalWallet::from_signing_key(test_signing_key())
    }

    fn test_calls() -> Vec<Call> {
        vec![
            Call {
                to: felt!("0x888").into(),
                selector: selector!("request_random"),
                calldata: vec![felt!("0x111"), felt!("0x0"), felt!("0x222")],
            },
            Call {
                to: felt!("0x111").into(),
                selector: selector!("dice"),
                calldata: vec![],
            },
        ]
    }

    fn test_outside_execution_v2() -> OutsideExecution {
        OutsideExecution::V2(OutsideExecutionV2 {
            caller: TEST_CALLER,
            nonce: felt!("0x1"),
            execute_after: 0,
            execute_before: 3000000000,
            calls: test_calls(),
        })
    }

    #[tokio::test]
    async fn sign_v2_produces_valid_signature() {
        let oe = test_outside_execution_v2();
        let sig =
            sign_outside_execution(&oe, TEST_CHAIN_ID, TEST_SIGNER_ADDRESS, test_signer()).await;

        assert_eq!(sig.len(), 2, "signature should have r and s components");

        let hash = oe.get_message_hash_rev_1(TEST_CHAIN_ID, TEST_SIGNER_ADDRESS);
        let public_key = test_signing_key().verifying_key().scalar();

        assert!(
            starknet_crypto::verify(&public_key, &hash, &sig[0], &sig[1]).unwrap(),
            "V2 signature should be valid"
        );
    }
}
