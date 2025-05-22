//! A simple VRF contract provider to be used in upstream projects like Katana.
//!
//! Before running `cargo build`, first run `scarb build` to generate the contract classes
//! and copy them into `classes/` directory.
//!
//! The `NoFeeCheck` version is the one used in Katana, where the fee check to avoid revealing
//! the VRF value when estimating the fee is disabled.
use lazy_static::lazy_static;
use starknet::core::types::Felt;
use starknet::macros::felt;
use std::collections::HashMap;

#[derive(Clone, Copy, PartialEq, Eq, Hash)]
pub enum Version {
    NoFeeCheck,
}

#[derive(Clone, Copy)]
pub struct ContractClass {
    pub content: &'static str,
    pub hash: Felt,
    pub casm_hash: Felt,
}

unsafe impl Sync for ContractClass {}

lazy_static! {
    pub static ref CONTRACTS: HashMap<Version, ContractClass> = {
        let mut m = HashMap::new();
        m.insert(
            Version::NoFeeCheck,
            ContractClass {
                content: include_str!(
                    "../classes/cartridge_vrf_VrfProvider_NoFeeCheck.contract_class.json"
                ),
                hash: felt!("0x07007ea60938ff539f1c0772a9e0f39b4314cfea276d2c22c29a8b64f2a87a58"),
                casm_hash: felt!(
                    "0x06eed837842af28269a8d4a712cf187ca11852c67cc85469304dbbfb55edfab3"
                ),
            },
        );

        m
    };
}
