use starknet::ContractAddress;
use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};
use vrf_contracts::vrf_provider::vrf_provider_component::PublicKey;

#[starknet::interface]
trait IVrfConsumer<TContractState> {
    fn get_vrf_provider(self: @TContractState) -> ContractAddress;
    fn get_vrf_provider_public_key(self: @TContractState) -> PublicKey;
}

#[starknet::component]
pub mod VrfConsumerComponent {
    use starknet::{
        ContractAddress, contract_address::ContractAddressZeroable, get_caller_address,
        get_contract_address
    };
    use starknet::storage::Map;

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    use vrf_contracts::vrf_provider::vrf_provider_component::{
        IVrfProvider, IVrfProviderDispatcher, IVrfProviderDispatcherTrait, PublicKey,
        PublicKeyIntoPoint, IVrfConsumerCallback, IVrfConsumerCallbackHelpers, get_seed_from_key
    };

    #[storage]
    struct Storage {
        VrfConsumer_vrf_provider: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct VrfProviderChanged {
        address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    #[event]
    enum Event {
        VrfProviderChanged: VrfProviderChanged,
    }

    pub mod Errors {
        pub const ADDRESS_ZERO: felt252 = 'VrfConsumer: address is zero';
        pub const COMMIT_MISMATCH: felt252 = 'VrfConsumer: commit mismatch';
        pub const ALREADY_COMMITED: felt252 = 'VrfConsumer: already committed';
        pub const INVALID_CALLER: felt252 = 'VrfConsumer: invalid caller';
    }

    #[embeddable_as(VrfConsumerCallbackImpl)]
    impl VrfConsumerCallback<
        TContractState,
        +Drop<TContractState>,
        +HasComponent<TContractState>,
        +IVrfConsumerCallbackHelpers<TContractState>
    > of IVrfConsumerCallback<ComponentState<TContractState>> {
        fn on_request_random(
            ref self: ComponentState<TContractState>,
            entrypoint: felt252,
            calldata: Array<felt252>,
            caller: ContractAddress,
        ) -> felt252 {
            // check caller is vrf_provider
            self.assert_called_by_vrf_provider();

            // retrieve key for call
            let contract = HasComponent::get_contract(@self);
            let key = contract.get_key_for_call(entrypoint, calldata.clone(), caller,);

            // check if allowed to request
            contract.assert_can_request_random(entrypoint, calldata, caller, key);

            key
        }
    }

    #[embeddable_as(VrfConsumerImpl)]
    impl VrfConsumer<
        TContractState, +Drop<TContractState>, +HasComponent<TContractState>,
    > of super::IVrfConsumer<ComponentState<TContractState>> {
        fn get_vrf_provider(self: @ComponentState<TContractState>) -> ContractAddress {
            self.VrfConsumer_vrf_provider.read()
        }

        fn get_vrf_provider_public_key(self: @ComponentState<TContractState>) -> PublicKey {
            IVrfProviderDispatcher { contract_address: self.VrfConsumer_vrf_provider.read() }
                .get_public_key()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +IVrfConsumerCallbackHelpers<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, vrf_provider: ContractAddress) {
            self.set_vrf_provider(vrf_provider);
        }

        fn assert_called_by_vrf_provider(self: @ComponentState<TContractState>,) {
            let caller = get_caller_address();
            let vrf_provider = self.VrfConsumer_vrf_provider.read();
            assert(caller == vrf_provider, Errors::INVALID_CALLER);
        }

        fn vrf_provider_disp(self: @ComponentState<TContractState>,) -> IVrfProviderDispatcher {
            IVrfProviderDispatcher { contract_address: self.VrfConsumer_vrf_provider.read() }
        }

        fn get_commit(self: @ComponentState<TContractState>, key: felt252) -> felt252 {
            let consumer = get_contract_address();
            self.vrf_provider_disp().get_commit(consumer, key)
        }

        fn is_committed(self: @ComponentState<TContractState>, key: felt252) -> bool {
            let consumer = get_contract_address();
            self.vrf_provider_disp().is_committed(consumer, key)
        }

        fn assert_not_committed(self: @ComponentState<TContractState>, key: felt252) {
            let is_committed = self.is_committed(key);
            assert(!is_committed, Errors::ALREADY_COMMITED);
        }

        fn assert_matching_commit(self: @ComponentState<TContractState>, key: felt252) {
            let consumer = get_contract_address();
            let nonce = self.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            let committed = self.get_commit(key);
            assert(committed == seed, Errors::COMMIT_MISMATCH);
        }

        fn consume_random(self: @ComponentState<TContractState>, key: felt252,) -> felt252 {
            self.vrf_provider_disp().consume_random(key)
        }

        fn get_random(self: @ComponentState<TContractState>, key: felt252) -> felt252 {
            let consumer = get_contract_address();
            let nonce = self.get_nonce(key);
            let seed = get_seed_from_key(consumer, key, nonce);

            self.vrf_provider_disp().get_random(seed)
        }

        fn get_nonce(self: @ComponentState<TContractState>, key: felt252) -> felt252 {
            let consumer = get_contract_address();
            self.vrf_provider_disp().get_nonce(consumer, key)
        }

        fn set_vrf_provider(
            ref self: ComponentState<TContractState>, new_vrf_provider: ContractAddress
        ) {
            assert(new_vrf_provider != ContractAddressZeroable::zero(), Errors::ADDRESS_ZERO);
            self.VrfConsumer_vrf_provider.write(new_vrf_provider);

            self.emit(VrfProviderChanged { address: new_vrf_provider })
        }
    }
}
