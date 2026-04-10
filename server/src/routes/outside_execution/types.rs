use cainome_cairo_serde::CairoSerde;
use serde::{Deserialize, Serialize};
use starknet::macros::selector;
use starknet_crypto::Felt;

// Re-export OutsideExecution types from account_sdk.
pub use account_sdk::abigen::controller::Call;
pub use account_sdk::abigen::controller::OutsideExecutionV3;
pub use account_sdk::account::outside_execution::OutsideExecution;
pub use account_sdk::account::outside_execution_v2::OutsideExecutionV2;

/// Returns the calls from an outside execution.
pub fn get_calls(outside_execution: &OutsideExecution) -> &[Call] {
    match outside_execution {
        OutsideExecution::V2(v2) => &v2.calls,
        OutsideExecution::V3(v3) => &v3.calls,
    }
}

/// Returns the appropriate `execute_from_outside` selector for the version.
pub fn get_selector(outside_execution: &OutsideExecution) -> Felt {
    match outside_execution {
        OutsideExecution::V2(_) => selector!("execute_from_outside_v2"),
        OutsideExecution::V3(_) => selector!("execute_from_outside_v3"),
    }
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct SignedOutsideExecution {
    pub address: Felt,
    pub outside_execution: OutsideExecution,
    pub signature: Vec<Felt>,
}

impl SignedOutsideExecution {
    pub fn build_execute_from_outside_call(&self) -> Call {
        let outside_execution = self.outside_execution.clone();

        let mut calldata = match outside_execution.clone() {
            OutsideExecution::V2(v2) => OutsideExecutionV2::cairo_serialize(&v2),
            OutsideExecution::V3(v3) => OutsideExecutionV3::cairo_serialize(&v3),
        };

        calldata.push(self.signature.len().into());
        calldata.extend(self.signature.clone());

        Call {
            to: self.address.into(),
            selector: get_selector(&outside_execution),
            calldata,
        }
    }
}
