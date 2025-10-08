use cainome_cairo_serde::{ClassHash, ContractAddress};
use dojo_utils::TransactionWaiter;
use katana_runner::RunnerCtx;
use num::FromPrimitive;
use starknet::{
    accounts::{Account, SingleOwnerAccount},
    core::{
        types::{BlockId, Call, FunctionCall},
        utils::get_udc_deployed_address,
    },
    macros::{felt, selector},
    providers::{jsonrpc::HttpTransport, JsonRpcClient, Provider},
    signers::{LocalWallet, SigningKey},
};
use starknet_crypto::Felt;
use std::{path::PathBuf, sync::Arc};

use crate::{
    routes::outside_execution::{
        build_signed_outside_execution_v2, OutsideExecutionRequest, OutsideExecutionResult,
    },
    tests::test_setup::{new_test_server, prepare_contract_declaration_params},
    Args,
};

pub const UDC_ADDRESS: Felt =
    felt!("0x41a78e741e5af2fec34b695679bc6891742439f7afb8484ecd7766661ad02bf");

pub const STRK_ADDRESS: Felt =
    felt!("0x4718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d");

pub const ACCOUNT_MOCK_ARTIFACT: &str =
    "../target/dev/cartridge_vrf_AccountMock.contract_class.json";
pub const ACCOUNT_MOCK_PUBLIC_KEY: Felt =
    felt!("0x4c339f18b9d1b95b64a6d378abd1480b2e0d5d5bd33cd0828cbce4d65c27284");
pub const ACCOUNT_MOCK_PRIVATE_KEY: Felt =
    felt!("0x1c9053c053edf324aec366a34c6901b1095b07af69495bffec7d7fe21effb1b");

pub const VRF_ACCOUNT_ARTIFACT: &str = "../target/dev/cartridge_vrf_VrfAccount.contract_class.json";
pub const VRF_CONSUMER_ARTIFACT: &str =
    "../target/dev/cartridge_vrf_VrfConsumer.contract_class.json";

pub const VRF_ACCOUNT_PRIVATE_KEY: &str = "0x111";
pub const VRF_ACCOUNT_PUBLIC_KEY: Felt =
    felt!("0x14584bef56c98fbb91aba84c20724937d5b5d2d6e5a49b60e6c3a19696fad5f");

pub const VRF_SECRET_KEY: u64 = 420;
pub const VRF_PUBLIC_KEY: [Felt; 2] = [
    felt!("0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4"),
    felt!("0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232"),
];

pub type StarknetAccount = SingleOwnerAccount<JsonRpcClient<HttpTransport>, LocalWallet>;

pub async fn declare(sequencer: &RunnerCtx, artifact: &str) -> ClassHash {
    let account = sequencer.account(0);

    let (sierra_class, casm_class_hash) =
        prepare_contract_declaration_params(&PathBuf::from(artifact)).unwrap();

    let declare_result = account
        .declare_v3(Arc::new(sierra_class), casm_class_hash)
        .send()
        .await
        .unwrap();

    let class_hash = declare_result.class_hash;

    let _declare_receipt =
        TransactionWaiter::new(declare_result.transaction_hash, sequencer.provider())
            .await
            .unwrap();

    class_hash.into()
}
pub async fn declare_and_deploy(
    sequencer: &RunnerCtx,
    artifact: &str,
    constructor_calldata: Vec<Felt>,
) -> (ContractAddress, ClassHash) {
    let account = sequencer.account(0);

    let class_hash = declare(sequencer, artifact).await;

    let mut calldata = vec![
        class_hash.0,
        felt!("0x0"),                                          // salt
        felt!("0x0"),                                          // unique
        Felt::from_usize(constructor_calldata.len()).unwrap(), // calldata len
    ];

    calldata.extend(constructor_calldata.clone()); // calldata

    let deploy_result = account
        .execute_v3(vec![Call {
            to: UDC_ADDRESS,
            selector: selector!("deployContract"),
            calldata,
        }])
        .send()
        .await
        .unwrap();

    let _deploy_receipt =
        TransactionWaiter::new(deploy_result.transaction_hash, sequencer.provider())
            .await
            .unwrap();

    let contract_address = get_udc_deployed_address(
        felt!("0x0"), // salt
        class_hash.0,
        &starknet::core::utils::UdcUniqueness::NotUnique,
        &constructor_calldata,
    );

    (contract_address.into(), class_hash)
}

#[tokio::test(flavor = "multi_thread")]
#[katana_runner::test(accounts = 10, chain_id = Felt::from_hex_unchecked("0x57505f4b4154414e41"))] // WP_KATANA
async fn test_outside_execution(sequencer: &RunnerCtx) {
    let chain_id = sequencer.provider().chain_id().await.unwrap();
    let account = sequencer.account(0);

    let (vrf_account_address, _) = declare_and_deploy(
        sequencer,
        VRF_ACCOUNT_ARTIFACT,
        vec![VRF_ACCOUNT_PUBLIC_KEY],
    )
    .await;

    let vrf_signer = LocalWallet::from_signing_key(SigningKey::from_secret_scalar(
        Felt::from_hex(VRF_ACCOUNT_PRIVATE_KEY).unwrap(),
    ));
    let vrf_account = SingleOwnerAccount::new(
        sequencer.provider(),
        vrf_signer,
        vrf_account_address.0,
        chain_id,
        starknet::accounts::ExecutionEncoding::New,
    );

    // transfer strk to vrf_account
    let transfer_tx_result = account
        .execute_v3(vec![Call {
            to: STRK_ADDRESS,
            selector: selector!("transfer"),
            calldata: vec![
                vrf_account_address.0,
                Felt::from_u128(10 * 10_u128.pow(18)).unwrap(),
                Felt::ZERO,
            ],
        }])
        .send()
        .await
        .unwrap();

    TransactionWaiter::new(transfer_tx_result.transaction_hash, sequencer.provider())
        .await
        .unwrap();

    // set_vrf_public_key
    let set_vrf_public_key_tx_result = vrf_account
        .execute_v3(vec![Call {
            to: vrf_account_address.0,
            selector: selector!("set_vrf_public_key"),
            calldata: VRF_PUBLIC_KEY.into(),
        }])
        .send()
        .await
        .unwrap();

    TransactionWaiter::new(
        set_vrf_public_key_tx_result.transaction_hash,
        sequencer.provider(),
    )
    .await
    .unwrap();

    let (consumer_address, _) = declare_and_deploy(
        sequencer,
        VRF_CONSUMER_ARTIFACT,
        vec![vrf_account_address.0],
    )
    .await;

    // MUST USE ACCOUNT SUPPORTING OUTSIDE_EXECUTION
    let (user_account_address, _) = declare_and_deploy(
        sequencer,
        ACCOUNT_MOCK_ARTIFACT,
        vec![ACCOUNT_MOCK_PUBLIC_KEY],
    )
    .await;

    let user_account_signer =
        LocalWallet::from_signing_key(SigningKey::from_secret_scalar(ACCOUNT_MOCK_PRIVATE_KEY));
    let user_account = SingleOwnerAccount::new(
        sequencer.provider(),
        user_account_signer.clone(),
        user_account_address.0,
        chain_id,
        starknet::accounts::ExecutionEncoding::New,
    );

    let user_calls = vec![
        Call {
            to: vrf_account_address.0,
            selector: selector!("request_random"),
            calldata: vec![
                consumer_address.0,
                felt!("0x0"), // Source::Nonce
                user_account.address(),
            ],
        }
        .into(),
        Call {
            to: consumer_address.0,
            selector: selector!("dice"),
            calldata: vec![],
        }
        .into(),
    ];

    let signed_outside_execution = build_signed_outside_execution_v2(
        user_account.address(),
        user_account_signer,
        chain_id,
        user_calls,
    )
    .await;

    // println!("signed_outisde_execution: {:?}", signed_outside_execution);

    let args = Args::default()
        .with_account_address(&vrf_account_address.0.to_hex_string())
        .with_account_private_key(VRF_ACCOUNT_PRIVATE_KEY)
        .with_secret_key(VRF_SECRET_KEY)
        .with_rpc_url(sequencer.url().as_str());

    let server = new_test_server(&args).await;

    let signed_outisde_execution_request_json = serde_json::to_value(&OutsideExecutionRequest {
        request: signed_outside_execution,
    })
    .unwrap();

    // println!(
    //     "signed_outisde_execution_request_json: {}",
    //     signed_outisde_execution_request_json
    // );

    let response = server
        .post("/outside_execution")
        .json(&signed_outisde_execution_request_json)
        .await;

    // println!("response: {:?}", response);
    let outside_execution_result = response.json::<OutsideExecutionResult>();
    let final_outside_execution = outside_execution_result.result;
    // println!("final_outside_execution: {:?}", final_outside_execution);

    let execution_call = final_outside_execution.build_execute_from_outside_call();

    // println!("execution_call: {:?}", execution_call);

    let executor_account = sequencer.account(2);

    let _dice_value = sequencer
        .provider()
        .call(
            FunctionCall {
                contract_address: consumer_address.0,
                entry_point_selector: selector!("get_dice_value"),
                calldata: vec![],
            },
            BlockId::Tag(starknet::core::types::BlockTag::PreConfirmed),
        )
        .await
        .unwrap();
    // println!("dice_value_before: {:?}", dice_value);

    let execute_result = executor_account
        .execute_v3(vec![execution_call.into()])
        .send()
        .await
        .unwrap();

    let _execute_receipt =
        TransactionWaiter::new(execute_result.transaction_hash, sequencer.provider())
            .await
            .unwrap();

    // println!("execute_receipt: {:?}", execute_receipt);

    let dice_value = sequencer
        .provider()
        .call(
            FunctionCall {
                contract_address: consumer_address.0,
                entry_point_selector: selector!("get_dice_value"),
                calldata: vec![],
            },
            BlockId::Tag(starknet::core::types::BlockTag::PreConfirmed),
        )
        .await
        .unwrap();

    println!("dice_value_after: {:?}", dice_value);
    assert!(dice_value[0] == felt!("0x6"), "dice should be 6")
}
