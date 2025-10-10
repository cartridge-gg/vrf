use crate::{create_app, routes::info::InfoResult, state::AppState, Args};
use anyhow::{anyhow, Result};
use axum_test::TestServer;
use cairo_lang_starknet_classes::casm_contract_class::CasmContractClass;
use cairo_lang_starknet_classes::contract_class::ContractClass;
use katana_runner::RunnerCtx;
use starknet::core::types::{
    contract::{CompiledClass, SierraClass},
    FlattenedSierraClass,
};
use starknet_crypto::Felt;
use std::{fs::File, path::PathBuf};

pub async fn new_test_server(args: &Args) -> TestServer {
    let app_state = AppState::from_args(args).await;
    let app = create_app(app_state).await;

    TestServer::builder()
        .expect_success_by_default()
        .mock_transport()
        .build(app)
        .unwrap()
}

// from katana

pub fn prepare_contract_declaration_params(
    artifact_path: &PathBuf,
) -> Result<(FlattenedSierraClass, Felt)> {
    let flattened_class = get_flattened_class(artifact_path)
        .map_err(|e| anyhow!("error flattening the contract class: {e}"))?;
    let compiled_class_hash = get_compiled_class_hash(artifact_path)
        .map_err(|e| anyhow!("error computing compiled class hash: {e}"))?;
    Ok((flattened_class, compiled_class_hash))
}

fn get_flattened_class(artifact_path: &PathBuf) -> Result<FlattenedSierraClass> {
    let file = File::open(artifact_path)?;
    let contract_artifact: SierraClass = serde_json::from_reader(&file)?;
    Ok(contract_artifact.flatten()?)
}

fn get_compiled_class_hash(artifact_path: &PathBuf) -> Result<Felt> {
    let file = File::open(artifact_path)?;
    let casm_contract_class: ContractClass = serde_json::from_reader(file)?;
    let casm_contract =
        CasmContractClass::from_contract_class(casm_contract_class, true, usize::MAX)
            .map_err(|e| anyhow!("CasmContractClass from ContractClass error: {e}"))?;
    let res = serde_json::to_string_pretty(&casm_contract)?;
    let compiled_class: CompiledClass = serde_json::from_str(&res)?;
    Ok(compiled_class.class_hash()?)
}

#[tokio::test(flavor = "multi_thread")]
#[katana_runner::test(accounts = 10)]
async fn test_info(sequencer: &RunnerCtx) {
    let args = Args::default()
        .with_rpc_url(sequencer.url().as_str())
        .with_secret_key(420);
    let server = new_test_server(&args).await;

    let info = server.get("/info").await;
    let result = info.json::<InfoResult>();

    assert!(
        result.public_key_x == "0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4",
        "invalid public_key_x"
    );
    assert!(
        result.public_key_y == "0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232",
        "invalid public_key_y"
    );
}
