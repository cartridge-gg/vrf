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

use super::common::{setup, SetupResult, CONSUMER, submit_random_no_proof, proof_predict_7};

#[test]
fn test_dice_no_commit__multiple_throw() {
    let setup = setup();

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'dice_no_commit';
    let calldata = array![];

    // CALLER request_random
    start_cheat_caller_address(setup.provider.contract_address, CALLER());
    let (_key, seed) = setup.provider.request_random(consumer, entrypoint, calldata.clone(),);
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 111);

    // CALLER request again
    start_cheat_caller_address(setup.provider.contract_address, CALLER());
    let (key, seed) = setup.provider.request_random(consumer, entrypoint, calldata.clone(),);
    stop_cheat_caller_address(setup.provider.contract_address);

    // provider give random
    submit_random_no_proof(setup.provider, seed, 222);

    // CALLER consume 2nd throw
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());
    let rand = setup.provider.get_random(seed);
    assert(rand == 222, 'rand should be 222');
    setup.consumer.dice_no_commit();
    let commit = setup.provider.get_commit(CONSUMER(), key);
    assert(commit == 0, 'commit should be 0');
    stop_cheat_caller_address(setup.consumer.contract_address);
}

