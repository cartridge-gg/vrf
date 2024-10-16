use openzeppelin_testing as utils;
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address, cheat_max_fee_global};
use starknet::{ContractAddress, contract_address_const};
use stark_vrf::ecvrf::Proof;
use utils::constants::{AUTHORIZED, OWNER};

use cartridge_vrf::vrf_provider::vrf_provider::VrfProvider;
use cartridge_vrf::vrf_provider::vrf_provider_component::{
    IVrfProvider, IVrfProviderDispatcher, IVrfProviderDispatcherTrait, PublicKey,
};

use cartridge_vrf::mocks::vrf_consumer_mock::{
    VrfConsumer, IVrfConsumerMock, IVrfConsumerMockDispatcher, IVrfConsumerMockDispatcherTrait
};

pub fn PROVIDER() -> ContractAddress {
    contract_address_const::<'PROVIDER'>()
}

pub fn CONSUMER1() -> ContractAddress {
    contract_address_const::<'CONSUMER1'>()
}

pub fn CONSUMER2() -> ContractAddress {
    contract_address_const::<'CONSUMER2'>()
}

pub fn PLAYER1() -> ContractAddress {
    contract_address_const::<'PLAYER1'>()
}

#[derive(Drop, Copy, Clone)]
pub struct SetupResult {
    provider: IVrfProviderDispatcher,
    consumer1: IVrfConsumerMockDispatcher,
    consumer2: IVrfConsumerMockDispatcher,
}

// lauch vrf-server : cargo run -r -- -s 420
// pubkey.x =0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4
// pubkey.y =0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232

pub fn setup() -> SetupResult {
    let mut provider_calldata = array![];
    provider_calldata.append_serde(OWNER());
    provider_calldata
        .append_serde(
            PublicKey {
                x: 0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4,
                y: 0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232,
            }
        );

    utils::declare_and_deploy_at("VrfProvider", PROVIDER(), provider_calldata);

    let mut consumer_calldata = array![];
    consumer_calldata.append_serde(PROVIDER());

    utils::declare_and_deploy_at("VrfConsumer", CONSUMER1(), consumer_calldata.clone());
    utils::deploy_another_at(CONSUMER1(), CONSUMER2(), consumer_calldata);

    cheat_max_fee_global(10000000000000000);

    SetupResult {
        provider: IVrfProviderDispatcher { contract_address: PROVIDER() },
        consumer1: IVrfConsumerMockDispatcher { contract_address: CONSUMER1() },
        consumer2: IVrfConsumerMockDispatcher { contract_address: CONSUMER2() },
    }
}

pub fn submit_random(provider: IVrfProviderDispatcher, seed: felt252, proof: Proof) {
    start_cheat_caller_address(provider.contract_address, AUTHORIZED());
    provider.submit_random(seed, proof);
    stop_cheat_caller_address(provider.contract_address);
}
