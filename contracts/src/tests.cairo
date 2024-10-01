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


#[derive(Drop, Copy, Clone)]
pub struct SetupResult {
    provider: IVrfProviderDispatcher,
    consumer: IVrfConsumerExampleDispatcher,
}


// lauch vrf-server : cargo run -r -- -s 420
// pubkey.x =0x66da5d53168d591c55d4c05f3681663ac51bcdccd5ca09e366b71b0c40ccff4
// pubkey.y =0x6d3eb29920bf55195e5ec76f69e247c0942c7ef85f6640896c058ec75ca2232

// predict(7)
// dec seed: 3032352359757432012563250899565907372094349154944589575541851581834778916567
// hex seed: 6B440283D175E739D7576952E07F8E5F4DCB50CD3306980AB467701EBE036D7

// MUST give seed as hex string
// curl -d '{"seed":["0x6B440283D175E739D7576952E07F8E5F4DCB50CD3306980AB467701EBE036D7"]}' -H
// "Content-Type: application/json" http://localhost:3000/stark_vrf {
//     "result": {
//       "gamma_x": "0x1d62b9f8ca67b4b0be877d129ddcdcfde0155a5770bd10531567a38bc59af7e",
//       "gamma_y": "0x165932086b2c4f6d8aec5dd0e802739d3020a7b82c05f1022f8b62aef408931",
//       "c": "0x71026abfcecc06d527efeed5d13194588ec9824979356f6a1114af203816101",
//       "s": "0x24f3bbd6c66491f75b86da2b84c930e888303c28ff598e925166115378fd5c4",
//       "sqrt_ratio": "0x66d6479b41f2f98f5a333faa24024ece7ccd461298de26d22a7626a1658793d",
//       "rnd": "0x56eb1b9ad115ff980dc40bc05ce5ba2a94393a29a962498e49467af24220cdd"
//     }
//   }

fn proof_predict_7() -> Proof {
    Proof {
        gamma: Point {
            x: 0x1d62b9f8ca67b4b0be877d129ddcdcfde0155a5770bd10531567a38bc59af7e,
            y: 0x165932086b2c4f6d8aec5dd0e802739d3020a7b82c05f1022f8b62aef408931
        },
        c: 0x71026abfcecc06d527efeed5d13194588ec9824979356f6a1114af203816101,
        s: 0x24f3bbd6c66491f75b86da2b84c930e888303c28ff598e925166115378fd5c4,
        sqrt_ratio_hint: 0x66d6479b41f2f98f5a333faa24024ece7ccd461298de26d22a7626a1658793d,
    }
}

// predict_xyz(7)
// dec seed: 3296823651229936910592569470336223802394762194709333112375396103878069910189
// hex seed: 749EFA1A613B8F5498F478B99BE33679FDACAB988418A5EB6994ECDF0FEFAAD

// MUST give seed as hex string
// curl -d '{"seed":["0x749EFA1A613B8F5498F478B99BE33679FDACAB988418A5EB6994ECDF0FEFAAD"]}' -H
// "Content-Type: application/json" http://localhost:3000/stark_vrf {
//     "result":{
//        "gamma_x":"0x66416aa1032b6ce0d7821246d5665600801610f37582fd442d6df0fae0d2711",
//        "gamma_y":"0x27b5c9576c1794394466006eb01140ca5165068dd97f7c40929d2a87c0c9461",
//        "c":"0x148351524abedf607366c9af894985dbd2e811bfa7ae5cc8c0c936844bf4305",
//        "s":"0x35ab74811a59894b492ab6c0fa176b90abca04b358a97080eab88691dc7ba99",
//        "sqrt_ratio":"0x6b8ad3c093cdfb7fac6fb995c4db291f225cfce3da3b1612542f33757dbfb7b",
//        "rnd":"0x15edf1f71b575e3042d869bb4829566e4d7103bdc0b6862d7a658c22eb55497"
//     }
//  }

fn proof_predict_xyz_7() -> Proof {
    Proof {
        gamma: Point {
            x: 0x66416aa1032b6ce0d7821246d5665600801610f37582fd442d6df0fae0d2711,
            y: 0x27b5c9576c1794394466006eb01140ca5165068dd97f7c40929d2a87c0c9461
        },
        c: 0x148351524abedf607366c9af894985dbd2e811bfa7ae5cc8c0c936844bf4305,
        s: 0x35ab74811a59894b492ab6c0fa176b90abca04b358a97080eab88691dc7ba99,
        sqrt_ratio_hint: 0x6b8ad3c093cdfb7fac6fb995c4db291f225cfce3da3b1612542f33757dbfb7b,
    }
}


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
    consumer_calldata.append_serde(OWNER());
    consumer_calldata.append_serde(PROVIDER());

    utils::declare_and_deploy_at("VrfConsumer", CONSUMER(), consumer_calldata);

    SetupResult {
        provider: IVrfProviderDispatcher { contract_address: PROVIDER() },
        consumer: IVrfConsumerExampleDispatcher { contract_address: CONSUMER() },
    }
}


#[test]
fn test_setup() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, CALLER());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce, false);

    println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    let random = setup.provider.get_random(seed);
    println!("get_random: {}", random);
    assert(
        random == 0x56eb1b9ad115ff980dc40bc05ce5ba2a94393a29a962498e49467af24220cdd,
        'invalid random'
    );

    setup.consumer.predict(PredictParams { value: 7 });

    let score = setup.consumer.get_score(CALLER());
    assert(score == 0, 'should be 0');

    let commit = setup.provider.get_commit(CONSUMER(), CALLER());
    assert(commit == 0, 'commit should be 0');

    stop_cheat_caller_address(setup.consumer.contract_address);
}


#[test]
#[should_panic(expected: 'VrfConsumer: commit mismatch')]
fn test_changed_prediction_calldata() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, CALLER());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce, false);
    println!("seed: {}", seed);

    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // CALLER consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    // change guess from 7 -> 1
    setup.consumer.predict(PredictParams { value: 1 });
}


#[test]
#[should_panic(expected: 'VrfConsumer: commit mismatch')]
fn test_changed_prediction_entrypoint() {
    let setup = setup();

    // CALLER request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict_xyz';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, CALLER());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce, false);
    println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_xyz_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // CALLER consumes randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    setup.consumer.predict(PredictParams { value: 7 });
}

//
// predict_as_zero(7) 
//

// 709335980086892452643498776345904172040159484570831869629165509814881453129
// 191784DCD6B85D4EADCE37FB24C24C47C8117FFCB5261C410CF9BF4E7AD8449

// MUST give seed as hex string
// curl -d '{"seed":["0x191784DCD6B85D4EADCE37FB24C24C47C8117FFCB5261C410CF9BF4E7AD8449"]}' -H
// "Content-Type: application/json" http://localhost:3000/stark_vrf {
//     "result": {
//       "gamma_x": "0x513a735be1e86b8227486353849d7e01d314a20d9f472e43f4b39e96eb6b1e4",
//       "gamma_y": "0x1fc1c7af76a6d5c4fa82730de7eff88b0ed557d0612031d741714f59ee0e523",
//       "c": "0x229c3a63d5d0d91e01faf6484ad98decc9ca73b45f63904d715020d87588ec1",
//       "s": "0x78b5db6d42c49d26e072a509c7235ca1aef23d28335b7f8cb4b9dd4c27c775a",
//       "sqrt_ratio": "0xd4403b0a4489e4ac4a0a159ae4362083ae3412aee37c8d7cd67ede20c1eca0",
//       "rnd": "0x24d0b6298519f40a7d8cbde38cbf3d1d51a96e1fea7dd5acac3d6059f21bf10"
//     }
//   }

fn proof_predict_as_zero_7() -> Proof {
    Proof {
        gamma: Point {
            x: 0x513a735be1e86b8227486353849d7e01d314a20d9f472e43f4b39e96eb6b1e4,
            y: 0x1fc1c7af76a6d5c4fa82730de7eff88b0ed557d0612031d741714f59ee0e523
        },
        c: 0x229c3a63d5d0d91e01faf6484ad98decc9ca73b45f63904d715020d87588ec1,
        s: 0x78b5db6d42c49d26e072a509c7235ca1aef23d28335b7f8cb4b9dd4c27c775a,
        sqrt_ratio_hint: 0xd4403b0a4489e4ac4a0a159ae4362083ae3412aee37c8d7cd67ede20c1eca0,
    }
}


#[test]
fn test_request_random_as_zero_consumed_by_other() {
    let setup = setup();

    // CALLER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict_as_zero';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, ZERO());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce, true);

    println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_as_zero_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // OTHER consumes randomness
    start_cheat_caller_address(setup.consumer.contract_address, OTHER());

    setup.consumer.predict_as_zero(PredictParams { value: 7 });

    let commit = setup.provider.get_commit(CONSUMER(), ZERO());
    assert(commit == 0, 'commit should be 0');

    stop_cheat_caller_address(setup.consumer.contract_address);

    // OTHER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, OTHER());
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, ZERO());
    let calldata = array![1];
    let _ = setup.provider.request_random(consumer, entrypoint, calldata, nonce, true);
    stop_cheat_caller_address(setup.provider.contract_address);

}


#[test]
#[should_panic(expected: 'VrfProvider: already committed')]
fn test_request_random_as_zero_cannot_request_random_twice() {
    let setup = setup();

    // CALLER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict_as_zero';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, ZERO());

    let _ = setup.provider.request_random(consumer, entrypoint, calldata, nonce, true);

    stop_cheat_caller_address(setup.provider.contract_address);

    // OTHER request_random for predict_as_zero(params)
    start_cheat_caller_address(setup.provider.contract_address, OTHER());

    let calldata = array![1];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, ZERO());
    let _ = setup.provider.request_random(consumer, entrypoint, calldata, nonce, true);
}
