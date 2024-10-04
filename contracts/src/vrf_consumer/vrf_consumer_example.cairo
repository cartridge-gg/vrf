// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.16.0

#[derive(Drop, Copy, Clone, Serde)]
pub enum Action {
    Pay,
    Run,
    Fight
}

#[derive(Drop, Copy, Clone, Serde)]
pub struct ActionParams {
    pub param0: bool,
    pub param1: u32,
    pub param2: u256,
}

#[starknet::interface]
trait IVrfConsumerExample<TContractState> {
    // throw dice as much as you want and consume when you want
    fn dice_no_commit(ref self: TContractState);

    // throw dice then must consume to throw again
    fn dice_with_commit(ref self: TContractState);

    // any caller can throw dice as much as he want and any caller can consume
    fn shared_dice_no_commit(ref self: TContractState);

    // any caller can throw dice then any caller must consume to throw again
    fn shared_dice_with_commit(ref self: TContractState);

    // commit on a number prediction
    fn predict(ref self: TContractState, value: u32);

    // commit on an action with multiple params
    fn action(
        ref self: TContractState, action: Action, params: ActionParams, extra: Array<felt252>
    );

    // admin
    fn set_vrf_provider(ref self: TContractState, new_vrf_provider: starknet::ContractAddress);
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

    use vrf_contracts::utils::{Hashoor, Calldata};
    use super::{Action, ActionParams};

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
        pub const action: felt252 = 'action';
    }


    #[abi(embed_v0)]
    impl ConsumerImpl of super::IVrfConsumerExample<ContractState> {
        // throw dice as much as you want and consume when you want
        fn dice_no_commit(ref self: ContractState) {
            // retrieve key
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::dice_no_commit, array![], caller);

            let _random = self.vrf_consumer.consume_random(key);
        }

        // throw dice then must consume to throw again
        fn dice_with_commit(ref self: ContractState) {
            // retrieve key
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::dice_with_commit, array![], caller);

            // check if can consume_random
            self.vrf_consumer.assert_matching_commit(key);
            let _random = self.vrf_consumer.consume_random(key);
        }

        // any caller can throw dice as much as he want and any caller can consume
        fn shared_dice_no_commit(ref self: ContractState) {
            // retrieve key
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::shared_dice_no_commit, array![], caller);

            let _random = self.vrf_consumer.consume_random(key);
        }


        // any caller can throw dice then any caller must consume to throw again
        fn shared_dice_with_commit(ref self: ContractState) {
            // retrieve key
            let caller = get_caller_address();
            let key = self.get_key_for_call(Entrypoints::shared_dice_with_commit, array![], caller);

            // check if can consume_random
            self.vrf_consumer.assert_matching_commit(key);
            let _random = self.vrf_consumer.consume_random(key);
        }


        fn predict(ref self: ContractState, value: u32) {
            // retrieve key
            let caller = get_caller_address();
            let calldata = Calldata::serialize1(value);
            let key = self.get_key_for_call(Entrypoints::predict, calldata, caller);

            // check if can consume_random
            self.vrf_consumer.assert_matching_commit(key);
            let _random = self.vrf_consumer.consume_random(key);
        }

        // commit on an action with multiple params
        fn action(
            ref self: ContractState, action: Action, params: ActionParams, extra: Array<felt252>
        ) {
            // retrieve key
            let caller = get_caller_address();
            let calldata = Calldata::serialize3(action, params, extra);
            let key = self.get_key_for_call(Entrypoints::action, calldata, caller);

            // check if can consume_random
            self.vrf_consumer.assert_matching_commit(key);
            let _random = self.vrf_consumer.consume_random(key);
        }


        fn set_vrf_provider(ref self: ContractState, new_vrf_provider: ContractAddress) {
            // should be restricted
            self.vrf_consumer.set_vrf_provider(new_vrf_provider);
        }
    }


    #[abi(embed_v0)]
    impl VrfConsumerHelperImpl of IVrfConsumerCallbackHelpers<ContractState> {
        fn get_key_for_call(
            self: @ContractState,
            entrypoint: felt252,
            calldata: Array<felt252>,
            caller: ContractAddress,
        ) -> felt252 {
            if entrypoint == Entrypoints::dice_no_commit {
                return Hashoor::hash3(entrypoint, caller, calldata);
            };
            if entrypoint == Entrypoints::dice_with_commit {
                return Hashoor::hash3(entrypoint, caller, calldata);
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                return Hashoor::hash3(entrypoint, 0, calldata);
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                return Hashoor::hash3(entrypoint, 0, calldata);
            };
            if entrypoint == Entrypoints::predict {
                return Hashoor::hash3(entrypoint, caller, calldata);
            };
            if entrypoint == Entrypoints::action {
                return Hashoor::hash3(entrypoint, caller, calldata);
            };

            panic!("unhandled entrypoint")
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
                return self.vrf_consumer.assert_not_committed(key);
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                return;
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                return self.vrf_consumer.assert_not_committed(key);
            };
            if entrypoint == Entrypoints::predict {
                return self.vrf_consumer.assert_not_committed(key);
            };
            if entrypoint == Entrypoints::action {
                return self.vrf_consumer.assert_not_committed(key);
            };
        }


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
                let key = self.get_key_for_call(entrypoint, array![], caller);
                return !self.vrf_consumer.is_committed(key);
            };
            if entrypoint == Entrypoints::shared_dice_no_commit {
                return true;
            };
            if entrypoint == Entrypoints::shared_dice_with_commit {
                let key = self.get_key_for_call(entrypoint, array![], caller);
                return !self.vrf_consumer.is_committed(key);
            };
            if entrypoint == Entrypoints::predict {
                let key = self.get_key_for_call(entrypoint, calldata, caller);
                return !self.vrf_consumer.is_committed(key);
            };
            if entrypoint == Entrypoints::action {
                let key = self.get_key_for_call(entrypoint, calldata, caller);
                return !self.vrf_consumer.is_committed(key);
            };

            false
        }
    }

    #[generate_trait]
    impl ConsumerInternal of InternalTrait {}
}
