use openzeppelin_testing as utils;
use utils::constants::{OWNER, AUTHORIZED, CALLER};
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

// dec seed: 3032352359757432012563250899565907372094349154944589575541851581834778916567
// hex seed: 6B440283D175E739D7576952E07F8E5F4DCB50CD3306980AB467701EBE036D7

// MUST give seed as hex string
// curl -d '{"seed":["0x6B440283D175E739D7576952E07F8E5F4DCB50CD3306980AB467701EBE036D7"]}' -H "Content-Type: application/json" http://localhost:3000/stark_vrf
// {
//     "result": {
//       "gamma_x": "0x1d62b9f8ca67b4b0be877d129ddcdcfde0155a5770bd10531567a38bc59af7e",
//       "gamma_y": "0x165932086b2c4f6d8aec5dd0e802739d3020a7b82c05f1022f8b62aef408931",
//       "c": "0x71026abfcecc06d527efeed5d13194588ec9824979356f6a1114af203816101",
//       "s": "0x24f3bbd6c66491f75b86da2b84c930e888303c28ff598e925166115378fd5c4",
//       "sqrt_ratio": "0x66d6479b41f2f98f5a333faa24024ece7ccd461298de26d22a7626a1658793d",
//       "rnd": "0x56eb1b9ad115ff980dc40bc05ce5ba2a94393a29a962498e49467af24220cdd"
//     }
//   }

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


#[test]
fn test_setup() {
    let setup = setup();

    // user request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, CALLER());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce);

    println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // user consumer randomness
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
fn test_changed_prediction() {
    let setup = setup();

    // user request_random for predict(params)
    start_cheat_caller_address(setup.provider.contract_address, CALLER());

    let consumer = setup.consumer.contract_address;
    let entrypoint = 'predict';
    let calldata = array![7];
    let nonce = setup.provider.get_nonce(setup.consumer.contract_address, CALLER());

    let seed = setup.provider.request_random(consumer, entrypoint, calldata, nonce);

    println!("seed: {}", seed);
    stop_cheat_caller_address(setup.provider.contract_address);

    // vrf-server provides proof for seed
    start_cheat_caller_address(setup.provider.contract_address, AUTHORIZED());

    let proof = proof_predict_7();
    setup.provider.submit_random(seed, proof);

    stop_cheat_caller_address(setup.provider.contract_address);

    // user consumer randomness
    start_cheat_caller_address(setup.consumer.contract_address, CALLER());

    let random = setup.provider.get_random(seed);
    println!("get_random: {}", random);
    assert(
        random == 0x56eb1b9ad115ff980dc40bc05ce5ba2a94393a29a962498e49467af24220cdd,
        'invalid random'
    );

    // change guess from 7 -> 1
    setup.consumer.predict(PredictParams { value: 1 });
}
