use openzeppelin_testing as utils;
use utils::constants::{OWNER, AUTHORIZED, CALLER, OTHER, ZERO};
use starknet::{ClassHash, ContractAddress, contract_address_const};

use snforge_std::{start_cheat_caller_address, stop_cheat_caller_address};

use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

use openzeppelin_utils::serde::SerializedAppend;

use cartridge_vrf::vrf_provider::vrf_provider::VrfProvider;
use cartridge_vrf::vrf_provider::vrf_provider_component::{
    IVrfProvider, IVrfProviderDispatcher, IVrfProviderDispatcherTrait, PublicKey, Source
};

use cartridge_vrf::vrf_consumer::vrf_consumer_example::{
    VrfConsumer, IVrfConsumerExample, IVrfConsumerExampleDispatcher,
    IVrfConsumerExampleDispatcherTrait
};

use super::common::{setup, submit_random, SetupResult, CONSUMER1, CONSUMER2, PLAYER1};

// private key: 420
// {"public_key_x":"0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4","public_key_y":"0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232"}

const SEED: felt252 = 0x334b8c0ea68406b183b5affd81ce11bec1a0807d3fd68a54ee75ec148053b09;

// curl -X POST -H "Content-Type: application/json" -d '{"seed": ["0x334b8c0ea68406b183b5affd81ce11bec1a0807d3fd68a54ee75ec148053b09"]}' http://0.0.0.0:3000/stark_vrf
pub fn proof() -> Proof {
    Proof {
        gamma: Point {
            x: 0xf010d3727eb8aee76c7bc81f399805f4c2c39708451d933ef4d7f909248a6d,
            y: 0x18a8fab3c58608505953d0fa0376ab454907d6e88db83702a36294faa937ac8
        },
        c: 0x10e06538fdb8d943ecbf03e519500e258a83248d5a457ff2803c54c583f6302,
        s: 0x150f672c657e116cd3966b74a2320e600c853801612b56f3a9cb31063f763c6,
        sqrt_ratio_hint: 0x8b09cf018201f7702d638b23d3cd10f577f7973369e79e5974ab33c1d64e01,
    }
}

const SEED_FROM_SALT: felt252 = 0x767EBFD1241683397A6CB06FDE012811BB27FD6E768D7A4BB8670ED10DF95C0;

// curl -X POST -H "Content-Type: application/json" -d '{"seed": ["0x767EBFD1241683397A6CB06FDE012811BB27FD6E768D7A4BB8670ED10DF95C0"]}' http://0.0.0.0:3000/stark_vrf
pub fn proof_from_salt() -> Proof {
    Proof {
        gamma: Point {
            x: 0x28473f4cad1406e83a766a1137281340b93600661af4eda228d5f73ae4e0fe9,
            y: 0x36bf0d2884aa739d5e419f1eb9fdf4af61c489169830d748ae0bbc7707b95ae
        },
        c: 0x137ed85cd1ae3b25d6f9c2e3e23912cde001696fb4c0caba403967ecdab4bb4,
        s: 0x74b0e76d8cfffc8a4755f4bcdefd3b1339d68e2c06b1072b36cfb2661fd4a27,
        sqrt_ratio_hint: 0x29523a3636251c7085188108d8912577076ab6337892a3aa492dea4015d3a0c,
    }
}

#[test]
fn test_dice() {
    let setup = setup();

    setup.provider.request_random(CONSUMER1(), Source::Nonce(PLAYER1()));

    submit_random(setup.provider, SEED, proof(),);

    // PLAYER1 call dice, CONSUMER1 is caller of consume_random
    start_cheat_caller_address(setup.consumer1.contract_address, PLAYER1());
    let dice1 = setup.consumer1.dice();
    assert(dice1 == 3, 'dice1 should be 3');
    stop_cheat_caller_address(setup.consumer1.contract_address);

    setup.provider.assert_consumed(SEED);
}

#[test]
#[should_panic(expected: 'VrfProvider: not consumed')]
fn test_not_consuming__must_consume() {
    let setup = setup();

    // noop just here for example
    setup.provider.request_random(CONSUMER1(), Source::Nonce(PLAYER1()));

    submit_random(setup.provider, SEED, proof(),);

    // PLAYER1 dont consume
    start_cheat_caller_address(setup.consumer1.contract_address, PLAYER1());
    setup.consumer1.not_consuming();

    stop_cheat_caller_address(setup.consumer1.contract_address);
    setup.provider.assert_consumed(SEED);
}

#[test]
#[should_panic(expected: 'VrfProvider: not fulfilled')]
fn test_dice__cannot_consume_twice() {
    let setup = setup();

    // noop just here for example
    setup.provider.request_random(CONSUMER1(), Source::Nonce(PLAYER1()));

    // provider submit_random
    submit_random(setup.provider, SEED, proof(),);

    // PLAYER1 consume twice
    start_cheat_caller_address(setup.consumer1.contract_address, PLAYER1());
    start_cheat_caller_address(setup.consumer2.contract_address, PLAYER1());

    let _dice1 = setup.consumer1.dice();
    let _dice2 = setup.consumer1.dice();
}

#[test]
fn test_dice_with_salt() {
    let setup = setup();

    // noop just here for example
    setup.provider.request_random(CONSUMER1(), Source::Salt('salt'));

    submit_random(setup.provider, SEED_FROM_SALT, proof_from_salt(),);

    // PLAYER1 call dice_with_salt, CONSUMER1 is caller of consume_random
    start_cheat_caller_address(setup.consumer1.contract_address, PLAYER1());
    let dice1 = setup.consumer1.dice_with_salt();
    assert(dice1 == 2, 'dice1 should be 2');
    stop_cheat_caller_address(setup.consumer1.contract_address);

    setup.provider.assert_consumed(SEED);
}

#[test]
#[should_panic(expected: 'VrfProvider: not fulfilled')]
fn test_dice_with_salt__wrong_proof() {
    let setup = setup();

    // noop just here for example
    setup.provider.request_random(CONSUMER1(), Source::Salt('salt'));

    submit_random(setup.provider, SEED, proof(),);

    // PLAYER1 consume
    start_cheat_caller_address(setup.consumer1.contract_address, PLAYER1());
    let _dice1 = setup.consumer1.dice_with_salt();
}
