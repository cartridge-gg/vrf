// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.16.0

#[derive(Drop, Copy, Clone, Serde)]
pub struct PredictParams {
    value: u32,
}

#[starknet::interface]
trait IVrfConsumerExample<TContractState> {
    fn predict(ref self: TContractState, params: PredictParams);
    fn get_score(self: @TContractState, player: starknet::ContractAddress) -> u32;
}

#[starknet::contract]
mod VrfConsumer {
    use starknet::{ClassHash, ContractAddress, get_caller_address};
    use starknet::storage::Map;

    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::upgrades::UpgradeableComponent;
    use openzeppelin::upgrades::interface::IUpgradeable;

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    use vrf_contracts::vrf_consumer::vrf_consumer_component::{VrfConsumerComponent, RequestStatus};

    use super::PredictParams;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: VrfConsumerComponent, storage: vrf_consumer, event: VrfConsumerEvent);

    #[abi(embed_v0)]
    impl OwnableMixinImpl = OwnableComponent::OwnableMixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl VrfConsumerImpl = VrfConsumerComponent::VrfConsumerImpl<ContractState>;

    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl VrfConsumerInternalImpl = VrfConsumerComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        vrf_consumer: VrfConsumerComponent::Storage,
        scores: Map<ContractAddress, u32>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        VrfConsumerEvent: VrfConsumerComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, vrf_provider: ContractAddress) {
        self.ownable.initializer(owner);
        self.vrf_consumer.initializer(vrf_provider);
    }


    #[abi(embed_v0)]
    impl ConsumerImpl of super::IVrfConsumerExample<ContractState> {

        // - with controller & paymaster :
        // retrieve caller nonce with vrf_provider.get_nonce(caller)
        // then in a multicall :
        // [
        //   vrf_provider.request_random( consumer_contract, entrypoint, calldata, nonce)
        //   consumer_contract.entrypoint(calldata)
        // ]

        // - without controller & paymaster
        // retrieve caller nonce with vrf_provider.get_nonce(caller)
        // call vrf_provider.request_random( consumer_contract, entrypoint, calldata, nonce)
        // wait for request to be fulfilled 
        // call consumer_contract.entrypoint(calldata)

        fn predict(ref self: ContractState, params: PredictParams) {
            // check if call match with commit
            let seed = self.vrf_consumer.assert_call_match_commit('predict', params);
            // retrieve random & clear commit
            let random = self.vrf_consumer.assert_fulfilled_and_consume(seed);

            let random: u256 = random.into();
            let value: u32 = (random % 10).try_into().unwrap();

            if params.value == value {
                let caller = get_caller_address();
                let score = self.scores.read(caller);
                self.scores.write(caller, score + 1);
            }
        }

        fn get_score(self: @ContractState, player: ContractAddress) -> u32 {
            self.scores.read(player)
        }
    }

    #[generate_trait]
    impl ConsumerInternal of InternalTrait {}
}
