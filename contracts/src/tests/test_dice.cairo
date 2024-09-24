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
    IVrfConsumerExampleDispatcherTrait
};

use super::common::{setup, SetupResult, CONSUMER1, CONSUMER2, submit_random_no_proof};

#[test]
fn test_dice() {
    let setup = setup();
    let seed = setup.provider.get_next_seed(CALLER());

    // CALLER request_random
    start_cheat_caller_address(setup.provider.contract_address, CALLER());
    setup.provider.request_random();
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider submit_random
    submit_random_no_proof(setup.provider, seed, 222);

    // CALLER consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());

    let dice1 = setup.consumer1.dice();

    assert(dice1 == 1, 'dice1 should be 1');

    stop_cheat_caller_address(setup.consumer1.contract_address);
    setup.provider.assert_consumed(seed);
}

#[test]
#[should_panic(expected: 'VrfProvider: not consumed')]
fn test_not_consuming__must_consume() {
    let setup = setup();
    let seed = setup.provider.get_next_seed(CALLER());

    // CALLER request_random
    start_cheat_caller_address(setup.provider.contract_address, CALLER());
    setup.provider.request_random();
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider submit_random
    submit_random_no_proof(setup.provider, seed, 222);

    // CALLER dont consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());
    setup.consumer1.not_consuming();

    stop_cheat_caller_address(setup.consumer1.contract_address);
    setup.provider.assert_consumed(seed);
}


#[test]
#[should_panic(expected: 'VrfProvider: not fulfilled')]
fn test_dice__cannot_consume_twice() {
    let setup = setup();
    let seed = setup.provider.get_next_seed(CALLER());

    // CALLER request_random
    start_cheat_caller_address(setup.provider.contract_address, CALLER());
    setup.provider.request_random();
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider submit_random
    submit_random_no_proof(setup.provider, seed, 222);

    // CALLER consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());
    start_cheat_caller_address(setup.consumer2.contract_address, CALLER());

    let _dice1 = setup.consumer1.dice();
    let _dice2 = setup.consumer1.dice();
}

