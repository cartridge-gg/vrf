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

use super::common::{setup, submit_random, SetupResult, CONSUMER1, CONSUMER2};

// private key: 420
// {"public_key_x":"0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4","public_key_y":"0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232"}
// seed: 0x334b8c0ea68406b183b5affd81ce11bec1a0807d3fd68a54ee75ec148053b09
// curl -X POST -H "Content-Type: application/json" -d '{"seed": ["0x334b8c0ea68406b183b5affd81ce11bec1a0807d3fd68a54ee75ec148053b09"]}' http://0.0.0.0:3000/stark_vrf
// {
//     "result": {
//         "gamma_x": "0xf010d3727eb8aee76c7bc81f399805f4c2c39708451d933ef4d7f909248a6d",
//         "gamma_y": "0x18a8fab3c58608505953d0fa0376ab454907d6e88db83702a36294faa937ac8",
//         "c": "0x10e06538fdb8d943ecbf03e519500e258a83248d5a457ff2803c54c583f6302",
//         "s": "0x150f672c657e116cd3966b74a2320e600c853801612b56f3a9cb31063f763c6",
//         "sqrt_ratio": "0x8b09cf018201f7702d638b23d3cd10f577f7973369e79e5974ab33c1d64e01",
//         "rnd": "0x735e9c275caf267880ec4e5967fde13ca084244384c03c739fcc54ac23789a4"
//     }
// }

const SEED: felt252 = 0x334b8c0ea68406b183b5affd81ce11bec1a0807d3fd68a54ee75ec148053b09;

#[test]
fn test_dice() {
    let setup = setup();

    setup.provider.request_random(CALLER(), Option::None);

    submit_random(
        setup.provider,
        SEED,
        Proof {
            gamma: Point {
                x: 0xf010d3727eb8aee76c7bc81f399805f4c2c39708451d933ef4d7f909248a6d,
                y: 0x18a8fab3c58608505953d0fa0376ab454907d6e88db83702a36294faa937ac8
            },
            c: 0x10e06538fdb8d943ecbf03e519500e258a83248d5a457ff2803c54c583f6302,
            s: 0x150f672c657e116cd3966b74a2320e600c853801612b56f3a9cb31063f763c6,
            sqrt_ratio_hint: 0x8b09cf018201f7702d638b23d3cd10f577f7973369e79e5974ab33c1d64e01,
        },
    );

    // CALLER consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());
    let dice1 = setup.consumer1.dice();
    assert(dice1 == 3, 'dice1 should be 3');
    stop_cheat_caller_address(setup.consumer1.contract_address);

    setup.provider.assert_consumed(SEED);
}

#[test]
#[should_panic(expected: 'VrfProvider: not consumed')]
fn test_not_consuming__must_consume() {
    let setup = setup();

    setup.provider.request_random(CALLER(), Option::None);

    submit_random(
        setup.provider,
        SEED,
        Proof {
            gamma: Point {
                x: 0xf010d3727eb8aee76c7bc81f399805f4c2c39708451d933ef4d7f909248a6d,
                y: 0x18a8fab3c58608505953d0fa0376ab454907d6e88db83702a36294faa937ac8
            },
            c: 0x10e06538fdb8d943ecbf03e519500e258a83248d5a457ff2803c54c583f6302,
            s: 0x150f672c657e116cd3966b74a2320e600c853801612b56f3a9cb31063f763c6,
            sqrt_ratio_hint: 0x8b09cf018201f7702d638b23d3cd10f577f7973369e79e5974ab33c1d64e01,
        },
    );

    // CALLER dont consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());
    setup.consumer1.not_consuming();

    stop_cheat_caller_address(setup.consumer1.contract_address);
    setup.provider.assert_consumed(SEED);
}

#[test]
#[should_panic(expected: 'VrfProvider: not fulfilled')]
fn test_dice__cannot_consume_twice() {
    let setup = setup();

    setup.provider.request_random(CALLER(), Option::None);

    // provider submit_random
    submit_random(
        setup.provider,
        SEED,
        Proof {
            gamma: Point {
                x: 0xf010d3727eb8aee76c7bc81f399805f4c2c39708451d933ef4d7f909248a6d,
                y: 0x18a8fab3c58608505953d0fa0376ab454907d6e88db83702a36294faa937ac8
            },
            c: 0x10e06538fdb8d943ecbf03e519500e258a83248d5a457ff2803c54c583f6302,
            s: 0x150f672c657e116cd3966b74a2320e600c853801612b56f3a9cb31063f763c6,
            sqrt_ratio_hint: 0x8b09cf018201f7702d638b23d3cd10f577f7973369e79e5974ab33c1d64e01,
        },
    );

    // CALLER consume
    start_cheat_caller_address(setup.consumer1.contract_address, CALLER());
    start_cheat_caller_address(setup.consumer2.contract_address, CALLER());

    let _dice1 = setup.consumer1.dice();
    let _dice2 = setup.consumer1.dice();
}
