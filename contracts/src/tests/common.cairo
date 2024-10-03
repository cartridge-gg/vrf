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

pub fn PROVIDER() -> ContractAddress {
    contract_address_const::<'PROVIDER'>()
}

pub fn CONSUMER() -> ContractAddress {
    contract_address_const::<'CONSUMER'>()
}

pub fn CONSUMER2() -> ContractAddress {
    contract_address_const::<'CONSUMER2'>()
}


#[derive(Drop, Copy, Clone)]
pub struct SetupResult {
    provider: IVrfProviderDispatcher,
    consumer: IVrfConsumerExampleDispatcher,
    // consumer2: IVrfConsumerExampleDispatcher,
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

    utils::declare_and_deploy_at("VrfConsumer", CONSUMER(), consumer_calldata.clone());
    // utils::declare_and_deploy_at("VrfConsumer", CONSUMER2(), consumer_calldata);

    SetupResult {
        provider: IVrfProviderDispatcher { contract_address: PROVIDER() },
        consumer: IVrfConsumerExampleDispatcher { contract_address: CONSUMER() },
        // consumer2: IVrfConsumerExampleDispatcher { contract_address: CONSUMER2() },
    }
}

pub fn submit_random_no_proof(provider: IVrfProviderDispatcher, seed: felt252, rand: felt252) {
    // vrf-server provides randomness
    start_cheat_caller_address(provider.contract_address, AUTHORIZED());
    provider.submit_random_no_proof(seed, rand);
    stop_cheat_caller_address(provider.contract_address);
}

// predict(7)
// dec seed: 607585265598880350269282576347946563989976446860791137567692418838919592956
// hex seed: 157E18E0AD1D332DBDE4FB45EC4217D18C2F173E319C265D3B855732AB33BFC

// MUST give seed as hex string
// curl -d '{"seed":["0x157E18E0AD1D332DBDE4FB45EC4217D18C2F173E319C265D3B855732AB33BFC"]}' -H "Content-Type: application/json" http://localhost:3000/stark_vrf {
    // {
    //     "result": {
    //       "gamma_x": "0x3837ccc52fe0b144283639352c4dc3844c36807872b2a26b3150d05eea97253",
    //       "gamma_y": "0x5cac1899a943a983c27e04b6070276626fbaa7c7f1a80dcd37354e1f8745c50",
    //       "c": "0x6087428da46028cd8c5db5b079ace75231356cb1deb8c5732f5dceedd79cb58",
    //       "s": "0x783fdaa82650f20b9282a57ee6da96ebd9ab2c2319a03c063dc79a4593f5086",
    //       "sqrt_ratio": "0xe3e8f4efbfb55a8d9c6e39f299bcf15c07bfe8d7e9e53cbc06c6f4a2b4d18a",
    //       "rnd": "0xf21be835daefd29c6a9d66fd0194ca058c4d12b0fdd77c0596601c5f5c338a"
    //     }
    //   }

fn proof_predict_7() -> (Proof, felt252) {
    (
        Proof {
            gamma: Point {
                x: 0x3837ccc52fe0b144283639352c4dc3844c36807872b2a26b3150d05eea97253,
                y: 0x5cac1899a943a983c27e04b6070276626fbaa7c7f1a80dcd37354e1f8745c50
            },
            c: 0x6087428da46028cd8c5db5b079ace75231356cb1deb8c5732f5dceedd79cb58,
            s: 0x783fdaa82650f20b9282a57ee6da96ebd9ab2c2319a03c063dc79a4593f5086,
            sqrt_ratio_hint: 0xe3e8f4efbfb55a8d9c6e39f299bcf15c07bfe8d7e9e53cbc06c6f4a2b4d18a,
        },
        0xf21be835daefd29c6a9d66fd0194ca058c4d12b0fdd77c0596601c5f5c338a
    )
}
