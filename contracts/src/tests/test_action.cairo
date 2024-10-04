use openzeppelin_testing as utils;
use utils::constants::{OWNER, AUTHORIZED, CALLER, OTHER, ZERO};
use starknet::{ClassHash, ContractAddress, contract_address_const};

use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};

use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

use openzeppelin_utils::serde::SerializedAppend;

use vrf_contracts::vrf_provider::vrf_provider::VrfProvider;
use vrf_contracts::vrf_provider::vrf_provider_component::{
    IVrfProvider, IVrfProviderDispatcher, IVrfProviderDispatcherTrait, PublicKey,
};

use vrf_contracts::vrf_consumer::vrf_consumer_example::{
    VrfConsumer, IVrfConsumerExample, IVrfConsumerExampleDispatcher,
    IVrfConsumerExampleDispatcherTrait, Action, ActionParams
};

use vrf_contracts::utils::{Calldata};

use super::common::{setup, SetupResult, CONSUMER, submit_random_no_proof};

#[test]
fn test_action() {
    let setup = setup();

    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'action';
    let calldata = Calldata::serialize3(
        Action::Fight,
        ActionParams { param0: true, param1: 16, param2: 100000000000000000, },
        array![5, 6, 7]
    );
    let (key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    // println!("key: {}", key);
    // println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    setup
        .consumer
        .action(
            Action::Fight,
            ActionParams { param0: true, param1: 16, param2: 100000000000000000, },
            array![5, 6, 7]
        );

    let commit = setup.provider.get_commit(CONSUMER(), key);
    assert(commit == 0, 'commit should be 0');

    stop_cheat_caller_address(setup.consumer.contract_address);
}

#[test]
#[should_panic(expected: 'VrfConsumer: commit mismatch')]
fn test_action_changed_calldata() {
    let setup = setup();

    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'action';
    let calldata = Calldata::serialize3(
        Action::Fight,
        ActionParams { param0: true, param1: 16, param2: 100000000000000000, },
        array![5, 6, 7]
    );
    let (_key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    // println!("key: {}", key);
    // println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    setup
        .consumer
        .action(
            Action::Fight,
            ActionParams { param0: true, param1: 420, param2: 100000000000000000, },
            array![5, 6, 7]
        );

    stop_cheat_caller_address(setup.consumer.contract_address);
}



