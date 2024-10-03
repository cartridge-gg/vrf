// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.16.0

#[derive(Drop, Copy, Clone, Serde)]
pub struct PredictParams {
    value: u32,
}

#[starknet::interface]
trait IVrfConsumerExample<TContractState> {
    // // one draw by lottery_id
    // fn lottery(ref self: TContractState, lottery_id: felt252);

    // throw dice as much as you want and consume when you want
    fn dice_no_commit(ref self: TContractState);

    // throw dice then must consume to throw again
    fn dice_with_commit(ref self: TContractState);

    // any caller can throw dice as much as he want and any caller can consume
    fn shared_dice_no_commit(ref self: TContractState);

    // any caller can throw dice then any caller must consume to throw again
    fn shared_dice_with_commit(ref self: TContractState);

    fn predict(ref self: TContractState, params: PredictParams);
    fn predict_as_zero(ref self: TContractState, params: PredictParams);

    fn set_vrf_provider(ref self: TContractState, new_vrf_provider: starknet::ContractAddress);
}

// pub mod Hashoor {
//     pub fn hash<T, +Drop<T>, +Serde<T>>(mut span: Span<T>) -> felt252 {
//         let mut arr = super::Calldata::serialize(span);
//         core::poseidon::poseidon_hash_span(arr.span())
//     }
// }

pub mod Calldata {
    pub fn serialize<T, +Drop<T>, +Serde<T>>(mut span: Span<T>) -> Array<felt252> {
        let mut arr = array![];

        while let Option::Some(v) = span.pop_front() {
            v.serialize(ref arr);
        };

        println!("serialize: {:?}", arr);
        arr
    }
}


#[starknet::contract]
mod VrfConsumer {
    use starknet::{ClassHash, ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::Map;

    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    use vrf_contracts::vrf_consumer::vrf_consumer_component::{VrfConsumerComponent};
    use vrf_contracts::vrf_provider::vrf_provider_component::{
        IVrfConsumerCallback, IVrfConsumerCallbackHelpers, get_seed_from_key
    };

    use super::PredictParams;


    component!(path: VrfConsumerComponent, storage: vrf_consumer, event: VrfConsumerEvent);

    #[abi(embed_v0)]
    impl VrfConsumerImpl = VrfConsumerComponent::VrfConsumerImpl<ContractState>;
    #[abi(embed_v0)]
    impl VrfConsumerCallbackImpl =
        VrfConsumerComponent::VrfConsumerCallbackImpl<ContractState>;

    impl VrfConsumerInternalImpl = VrfConsumerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        vrf_consumer: VrfConsumerComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        VrfConsumerEvent: VrfConsumerComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, vrf_provider: ContractAddress) {
        self.vrf_consumer.initializer(vrf_provider);
    }

    pub mod Entrypoints {
        pub const dice_no_commit: felt252 = 'dice_no_commit';
        pub const dice_with_commit: felt252 = 'dice_with_commit';
        pub const shared_dice_no_commit: felt252 = 'shared_dice_no_commit';
        pub const shared_dice_with_commit: felt252 = 'shared_dice_with_commit';
        pub const predict: felt252 = 'predict';
        pub const predict_as_zero: felt252 = 'predict_as_zero';
    }


    #[abi(embed_v0)]
    impl ConsumerImpl of super::IVrfConsumerExample<ContractState> {
        // throw dice as much as you want and consume when you want
        fn dice_no_commit(ref self: ContractState) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::dice_no_commit, array![], caller);

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let _value: u32 = (random % 6).try_into().unwrap() + 1;
        }

        // throw dice then must consume to throw again
        fn dice_with_commit(ref self: ContractState) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let consumer = get_contract_address();
            let key = self.get_key_for_call(Entrypoints::dice_with_commit, array![], caller);
            let nonce = self.vrf_consumer.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            // check if can consume_random
            let committed = self.vrf_consumer.get_commit(key);
            assert(committed == seed, 'commit mismatch');

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let _value: u32 = (random % 6).try_into().unwrap() + 1;
        }

        // any caller can throw dice as much as he want and any caller can consume
        fn shared_dice_no_commit(ref self: ContractState) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::shared_dice_no_commit, array![], caller);

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let _value: u32 = (random % 6).try_into().unwrap() + 1;
        }


        // any caller can throw dice then any caller must consume to throw again
        fn shared_dice_with_commit(ref self: ContractState) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let consumer = get_contract_address();
            let key = self.get_key_for_call(Entrypoints::shared_dice_with_commit, array![], caller);
            let nonce = self.vrf_consumer.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            // check if can consume_random
            let committed = self.vrf_consumer.get_commit(key);
            assert(committed == seed, 'commit mismatch');

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let _value: u32 = (random % 6).try_into().unwrap() + 1;
        }


        fn predict(ref self: ContractState, params: PredictParams) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let consumer = get_contract_address();
            let calldata = super::Calldata::serialize(array![params].span());
            let key = self.get_key_for_call(Entrypoints::predict, calldata, caller);
            let nonce = self.vrf_consumer.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            // check if can consume_random
            let committed = self.vrf_consumer.get_commit(key);
            assert(committed == seed, 'commit mismatch');

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let value: u32 = (random % 10).try_into().unwrap();

            if params.value == value {
                let _caller = get_caller_address();
            }
        }

        fn predict_as_zero(ref self: ContractState, params: PredictParams) {
            // retrieve key, nonce & seed for call
            let caller = get_caller_address();
            let consumer = get_contract_address();
            let calldata = super::Calldata::serialize(array![params].span());
            let key = self.get_key_for_call(Entrypoints::predict_as_zero, calldata, caller);
            let nonce = self.vrf_consumer.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            // check if can consume_random
            let committed = self.vrf_consumer.get_commit(key);
            assert(committed == seed, 'commit mismatch');

            let random = self.vrf_consumer.consume_random(key);

            let random: u256 = random.into();
            let value: u32 = (random % 10).try_into().unwrap();

            if params.value == value {
                let _caller = get_caller_address();
            }
        }

        fn set_vrf_provider(ref self: ContractState, new_vrf_provider: ContractAddress) {
            // should be restricted
            self.vrf_consumer.set_vrf_provider(new_vrf_provider);
        }
    }


    #[abi(embed_v0)]
    impl VrfConsumerHelperImpl of IVrfConsumerCallbackHelpers<ContractState> {
        fn should_request_random(
            self: @ContractState,
            entrypoint: felt252,
            calldata: Array<felt252>,
            caller: ContractAddress,
        ) -> bool {
            if entrypoint == Entrypoints::dice_no_commit {
                return true;
            };
            if entrypoint == Entrypoints::dice_with_commit {
                return true;
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                return true;
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                return true;
            };
            if entrypoint == Entrypoints::predict {
                return true;
            };
            if entrypoint == Entrypoints::predict_as_zero {
                return true;
            };

            false
        }

        fn assert_can_request_random(
            self: @ContractState,
            entrypoint: felt252,
            calldata: Array<felt252>,
            caller: ContractAddress,
            key: felt252,
        ) {
            if entrypoint == Entrypoints::dice_no_commit {
                return;
            };
            if entrypoint == Entrypoints::dice_with_commit {
                let is_committed = self.vrf_consumer.is_committed(key);
                assert(!is_committed, 'already committed');
                return;
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                return;
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                let is_committed = self.vrf_consumer.is_committed(key);
                assert(!is_committed, 'already committed');
                return;
            };
            if entrypoint == Entrypoints::predict {
                let is_committed = self.vrf_consumer.is_committed(key);
                assert(!is_committed, 'already committed');
                return;
            };
            if entrypoint == Entrypoints::predict_as_zero {
                let is_committed = self.vrf_consumer.is_committed(key);
                assert(!is_committed, 'already committed');
                return;
            };
        }

        fn get_key_for_call(
            self: @ContractState,
            entrypoint: felt252,
            calldata: Array<felt252>,
            caller: ContractAddress,
        ) -> felt252 {
            if entrypoint == Entrypoints::dice_no_commit {
                let mut keys: Array<felt252> = array![entrypoint, caller.into()];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            if entrypoint == Entrypoints::dice_with_commit {
                let mut keys: Array<felt252> = array![entrypoint, caller.into()];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                let mut keys: Array<felt252> = array![entrypoint, 0];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                let mut keys: Array<felt252> = array![entrypoint, 0];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            if entrypoint == Entrypoints::predict {
                let mut keys: Array<felt252> = array![entrypoint, caller.into()];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            if entrypoint == Entrypoints::predict_as_zero {
                let mut keys: Array<felt252> = array![entrypoint, 0];
                calldata.serialize(ref keys);

                return core::poseidon::poseidon_hash_span(keys.span());
            };
            panic!("unhandled entrypoint")
        }
    }

    #[generate_trait]
    impl ConsumerInternal of InternalTrait {}
}
