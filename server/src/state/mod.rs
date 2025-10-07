use crate::Args;
use ark_ec::short_weierstrass::Affine;
use cainome_cairo_serde::ContractAddress;
use clap::Parser;
use stark_vrf::{generate_public_key, StarkCurve};
use starknet::providers::Provider;
use starknet::signers::{LocalWallet, SigningKey};
use starknet::{
    core::types::Felt,
    providers::{
        jsonrpc::{HttpTransport, JsonRpcClient},
        Url,
    },
};
use std::sync::{Arc, RwLock};
pub type SharedState = Arc<RwLock<AppState>>;

#[derive(Clone)]
pub struct AppState {
    pub secret_key: String,
    pub public_key: Affine<StarkCurve>,
    pub provider: JsonRpcClient<HttpTransport>,
    pub chain_id: Felt,
    pub vrf_account_address: ContractAddress,
    pub vrf_signer: LocalWallet,
}

impl AppState {
    pub async fn from_args() -> AppState {
        let args = Args::parse();

        let secret_key = args.secret_key.to_string();
        let public_key = generate_public_key(secret_key.parse().unwrap());

        let vrf_account_address =
            ContractAddress::from(Felt::from_hex(&args.account_address).unwrap());
        let vrf_signer = LocalWallet::from(SigningKey::from_secret_scalar(
            Felt::from_hex(&args.account_private_key).unwrap(),
        ));

        let provider = JsonRpcClient::new(HttpTransport::new(Url::parse(&args.rpc_url).unwrap()));
        let chain_id = provider.chain_id().await.expect("unable to get chain_id");

        AppState {
            secret_key,
            public_key,
            provider,
            chain_id,
            vrf_account_address,
            vrf_signer,
        }
    }
}
