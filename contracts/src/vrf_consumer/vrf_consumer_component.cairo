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
        PublicKeyIntoPoint
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
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, vrf_provider: ContractAddress) {
            self.set_vrf_provider(vrf_provider);
        }

        fn vrf_provider_disp(self: @ComponentState<TContractState>,) -> IVrfProviderDispatcher {
            IVrfProviderDispatcher { contract_address: self.VrfConsumer_vrf_provider.read() }
        }

        fn get_seed_for_call(
            self: @ComponentState<TContractState>, entrypoint: felt252, calldata: Array<felt252>
        ) -> felt252 {
            let caller = get_caller_address();
            self.vrf_provider_disp().get_seed_for_call(caller, entrypoint, calldata)
        }

        fn get_commit(self: @ComponentState<TContractState>,) -> felt252 {
            let consumer = get_contract_address();
            let caller = get_caller_address();

            self.vrf_provider_disp().get_commit(consumer, caller)
        }

        fn consume_random<T, +Drop<T>, +Serde<T>>(
            self: @ComponentState<TContractState>, entrypoint: felt252, calldata: @T
        ) -> (felt252, felt252) {
            let caller = get_caller_address();
            self.consume_random_for_caller(entrypoint, calldata, caller)
        }

        fn consume_random_for_caller<T, +Drop<T>, +Serde<T>>(
            self: @ComponentState<TContractState>,
            entrypoint: felt252,
            calldata: @T,
            caller: ContractAddress
        ) -> (felt252, felt252) {
            let mut serialized = array![];
            calldata.serialize(ref serialized);

            // get seed for call
            let seed = self.get_seed_for_call(entrypoint, serialized);

            // get committed seed
            let committed = self.get_commit();

            // check call matches commit
            assert(seed == committed, Errors::COMMIT_MISMATCH);

            // consume random & uncommit caller
            let random = self.vrf_provider_disp().consume_random(caller, seed);

            (seed, random)
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
