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
    IVrfConsumerExampleDispatcherTrait, PredictParams
};

use super::common::{setup, SetupResult, CONSUMER, proof_predict_7, submit_random_no_proof};

#[test]
fn test_predict() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let (key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    // println!("key: {}", key);
    // println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let (proof, rand) = proof_predict_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    let random = setup.provider.get_random(seed);
    // println!("get_random: {}", random);
    assert(random == rand, 'invalid random');

    setup.consumer.predict(PredictParams { value: 7 });

    let commit = setup.provider.get_commit(CONSUMER(), key);
    assert(commit == 0, 'commit should be 0');

    stop_cheat_caller_address(setup.consumer.contract_address);
}

#[test]
#[should_panic(expected: 'commit mismatch')]
fn test_predict_changed_calldata() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let (_key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());
    // change guess from 7 -> 1
    setup.consumer.predict(PredictParams { value: 1 });
}

#[test]
#[should_panic(expected: 'commit mismatch')]
fn test_predict_changed_entrypoint() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let (_key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // CALLER consumes randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());
    setup.consumer.predict_as_zero(PredictParams { value: 7 });
}


#[test]
fn test_predict_as_zero_consumed_by_other() {
    let setup = setup();

    // CALLER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict_as_zero';
    let calldata = array![5];
    let (key, seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // OTHER consumes randomness
    start_cheat_caller_address(setup.consumer.contract_address, OTHER());

    setup.consumer.predict_as_zero(PredictParams { value: 5 });

    let commit = setup.provider.get_commit(CONSUMER(), key);
    assert(commit == 0, 'commit should be 0');

    stop_cheat_caller_address(setup.consumer.contract_address);

    // OTHER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, OTHER());
    let calldata = array![1];
    let (_key, _seed) = setup.provider.request_random(consumer, entrypoint, calldata,);
    stop_cheat_caller_address(setup.provider.contract_address);
}

#[test]
#[should_panic(expected: 'already committed')]
fn test_predict_as_zero_cannot_request_random_twice() {
    let setup = setup();

    // CALLER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict_as_zero';
    let calldata = array![7];
    let (_key, _seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

    stop_cheat_caller_address(setup.provider.contract_address);

    // OTHER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, OTHER());

    let calldata = array![7];
    let (_key, _seed) = setup.provider.request_random(consumer, entrypoint, calldata,);

}

