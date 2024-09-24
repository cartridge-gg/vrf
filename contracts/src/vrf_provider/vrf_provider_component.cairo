use starknet::ContractAddress;
use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

#[starknet::interface]
trait IVrfProvider<TContractState> {
    fn request_random(ref self: TContractState) -> felt252;
    fn submit_random(ref self: TContractState, seed: felt252, proof: Proof);
    //
    fn submit_random_no_proof(ref self: TContractState, seed: felt252, random: felt252);
    //
    fn get_next_seed(self: @TContractState, caller: ContractAddress,) -> felt252;
    //
    fn consume_random(ref self: TContractState, caller: ContractAddress) -> felt252;
    fn assert_consumed(ref self: TContractState, seed: felt252);
    //
    fn get_public_key(self: @TContractState) -> PublicKey;
    fn set_public_key(ref self: TContractState, new_pubkey: PublicKey);
}

//
//
//

fn get_seed(caller: ContractAddress, nonce: felt252, chain_id: felt252) -> felt252 {
    core::poseidon::poseidon_hash_span(array![nonce, caller.into(), chain_id].span())
}


#[derive(Drop, Copy, Clone, Serde, starknet::Store)]
pub struct PublicKey {
    x: felt252,
    y: felt252,
}

impl PublicKeyIntoPoint of Into<PublicKey, Point> {
    fn into(self: PublicKey) -> Point {
        Point { x: self.x, y: self.y }
    }
}

//
//
//

#[starknet::component]
pub mod VrfProviderComponent {
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map
    };

    use openzeppelin::access::ownable::{
        OwnableComponent, OwnableComponent::InternalImpl as OwnableInternalImpl
    };

    use super::{PublicKey, get_seed};

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    #[storage]
    struct Storage {
        VrfProvider_pubkey: PublicKey,
        // caller -> nonce
        VrfProvider_nonces: Map<ContractAddress, felt252>,
        // seed -> random
        VrfProvider_random: Map<felt252, felt252>,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicKeyChanged {
        pubkey: PublicKey,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestRandom {
        #[key]
        caller: ContractAddress,
        seed: felt252,
    }

    #[derive(Drop, starknet::Event)]
    struct SubmitRandom {
        #[key]
        seed: felt252,
        proof: Proof,
    }

    #[derive(Drop, starknet::Event)]
    #[event]
    enum Event {
        PublicKeyChanged: PublicKeyChanged,
        RequestRandom: RequestRandom,
        SubmitRandom: SubmitRandom,
    }

    pub mod Errors {
        pub const PUBKEY_ZERO: felt252 = 'VrfProvider: pubkey is zero';
        pub const INVALID_PROOF: felt252 = 'VrfProvider: invalid proof';
        pub const NOT_FULFILLED: felt252 = 'VrfProvider: not fulfilled';
        pub const SEED_MISMATCH: felt252 = 'VrfProvider: seed mismatch';
        pub const NOT_CONSUMED: felt252 = 'VrfProvider: not consumed';
    }

    #[embeddable_as(VrfProviderImpl)]
    impl VrfProvider<
        TContractState,
        +Drop<TContractState>,
        +HasComponent<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IVrfProvider<ComponentState<TContractState>> {
        // directly called by user to request randomness
        fn request_random(ref self: ComponentState<TContractState>) -> felt252 {
            let caller = get_caller_address();
            let nonce = self._increase_nonce(caller);
            let chain_id = starknet::get_execution_info().tx_info.unbox().chain_id;
            let seed = get_seed(caller, nonce, chain_id);

            self.emit(RequestRandom { caller, seed, });

            seed
        }

        // called by vrf providers
        fn submit_random(ref self: ComponentState<TContractState>, seed: felt252, proof: Proof) {
            // verify proof
            let pubkey: Point = self.get_public_key().into();
            let ecvrf = ECVRFImpl::new(pubkey);

            let random = ecvrf
                .verify(proof.clone(), array![seed.clone()].span())
                .expect(Errors::INVALID_PROOF);

            // write random
            self.VrfProvider_random.write(seed, random);

            self.emit(SubmitRandom { seed, proof });
        }


        // for testing purpose
        fn submit_random_no_proof(
            ref self: ComponentState<TContractState>, seed: felt252, random: felt252
        ) {
            assert(
                get_caller_address() == starknet::contract_address_const::<'AUTHORIZED'>(),
                'not AUTHORIZED'
            );
            // write random
            self.VrfProvider_random.write(seed, random);
        }


        //
        //
        //

        // get next seed for a caller address
        fn get_next_seed(
            self: @ComponentState<TContractState>, caller: ContractAddress,
        ) -> felt252 {
            let nonce = self._get_nonce(caller) + 1;
            let chain_id = starknet::get_execution_info().tx_info.unbox().chain_id;
            get_seed(caller, nonce, chain_id)
        }

        // consume randomness
        fn consume_random(
            ref self: ComponentState<TContractState>, caller: ContractAddress
        ) -> felt252 {
            let nonce = self._get_nonce(caller);
            let chain_id = starknet::get_execution_info().tx_info.unbox().chain_id;
            let seed = get_seed(caller, nonce, chain_id);
            let random = self.VrfProvider_random.read(seed);

            assert(random != 0, Errors::NOT_FULFILLED);

            // enforce one time consumtion
            self.VrfProvider_random.write(seed, 0);

            random
        }

        // called by vrf providers
        fn assert_consumed(ref self: ComponentState<TContractState>, seed: felt252) {
            let random = self.VrfProvider_random.read(seed);
            assert(random == 0, Errors::NOT_CONSUMED);
        }


        //
        //
        //

        fn get_public_key(self: @ComponentState<TContractState>) -> PublicKey {
            self.VrfProvider_pubkey.read()
        }

        fn set_public_key(ref self: ComponentState<TContractState>, new_pubkey: PublicKey) {
            let mut ownable_component = get_dep_component_mut!(ref self, Owner);
            ownable_component.assert_only_owner();

            self._set_public_key(new_pubkey);
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>
    > of InternalTrait<TContractState> {
        fn initializer(ref self: ComponentState<TContractState>, pubkey: PublicKey) {
            self._set_public_key(pubkey);
        }

        fn _set_public_key(ref self: ComponentState<TContractState>, new_pubkey: PublicKey) {
            assert(new_pubkey.x != 0 && new_pubkey.y != 0, Errors::PUBKEY_ZERO);
            self.VrfProvider_pubkey.write(new_pubkey);

            self.emit(PublicKeyChanged { pubkey: new_pubkey })
        }

        //
        //
        //

        fn _get_nonce(self: @ComponentState<TContractState>, caller: ContractAddress,) -> felt252 {
            self.VrfProvider_nonces.read(caller)
        }

        fn _increase_nonce(
            ref self: ComponentState<TContractState>, caller: ContractAddress
        ) -> felt252 {
            let nonce = self.VrfProvider_nonces.read(caller);
            let new_nonce = nonce + 1;
            self.VrfProvider_nonces.write(caller, new_nonce);
            new_nonce
        }
    }
}
