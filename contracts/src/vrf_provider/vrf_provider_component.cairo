use starknet::ContractAddress;
use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

#[starknet::interface]
trait IVrfProvider<TContractState> {
    fn request_random(
        ref self: TContractState,
        consumer: ContractAddress,
        entrypoint: felt252,
        calldata: Array<felt252>,
        nonce: felt252,
        as_zero: bool,
    ) -> felt252;

    fn submit_random(ref self: TContractState, seed: felt252, proof: Proof);

    fn consume_random(ref self: TContractState, caller: ContractAddress, seed: felt252) -> felt252;

    fn get_random(self: @TContractState, seed: felt252) -> felt252;

    fn get_nonce(
        self: @TContractState, consumer: ContractAddress, caller: ContractAddress,
    ) -> felt252;

    fn get_seed_for_call(
        self: @TContractState,
        caller: ContractAddress,
        entrypoint: felt252,
        calldata: Array<felt252>,
    ) -> felt252;

    fn get_commit(
        self: @TContractState, consumer: ContractAddress, caller: ContractAddress
    ) -> felt252;

    fn is_fulfilled(self: @TContractState, seed: felt252) -> bool;

    fn get_public_key(self: @TContractState) -> PublicKey;
    fn set_public_key(ref self: TContractState, new_pubkey: PublicKey);
}


//
//
//

#[derive(Debug, Drop, Clone, Serde)]
pub struct Request {
    consumer: ContractAddress,
    caller: ContractAddress,
    entrypoint: felt252,
    calldata: Array<felt252>,
    nonce: felt252,
}

#[generate_trait]
impl RequestImpl of RequestTrait {
    fn hash(self: @Request) -> felt252 {
        let mut keys: Array<felt252> = array![];
        self.serialize(ref keys);

        core::poseidon::poseidon_hash_span(keys.span())
    }
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

    use super::{Request, RequestImpl, RequestTrait, PublicKey};

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    #[storage]
    struct Storage {
        VrfProvider_pubkey: PublicKey,
        // (contract_address, caller_address) -> nonce
        VrfProvider_nonces: Map<(ContractAddress, ContractAddress), felt252>,
        // (contract_address, caller_address) -> salt
        VrfProvider_commit: Map<(ContractAddress, ContractAddress), felt252>,
        // seed -> random
        VrfProvider_request_random: Map<felt252, felt252>,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicKeyChanged {
        pubkey: PublicKey,
    }

    #[derive(Drop, starknet::Event)]
    struct RequestRandom {
        #[key]
        consumer: ContractAddress,
        #[key]
        caller: ContractAddress,
        entrypoint: felt252,
        calldata: Array<felt252>,
        nonce: felt252,
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
        pub const INVALID_NONCE: felt252 = 'VrfProvider: invalid nonce';
        pub const ALREADY_COMMITTED: felt252 = 'VrfProvider: already committed';
        pub const ALREADY_FULFILLED: felt252 = 'VrfProvider: already fulfilled';
        pub const REQUEST_NOT_FULFILLED: felt252 = 'VrfConsumer: not fulfilled';
        pub const INVALID_PROOF: felt252 = 'VrfConsumer: invalid proof';
    }

    #[embeddable_as(VrfProviderImpl)]
    impl VrfProvider<
        TContractState,
        +Drop<TContractState>,
        +HasComponent<TContractState>,
        impl Owner: OwnableComponent::HasComponent<TContractState>,
    > of super::IVrfProvider<ComponentState<TContractState>> {
        fn get_nonce(
            self: @ComponentState<TContractState>,
            consumer: ContractAddress,
            caller: ContractAddress,
        ) -> felt252 {
            self.VrfProvider_nonces.read((consumer, caller)) + 1
        }

        // directly called by user to request randomness for a consumer / entrypoint / calldata
        fn request_random(
            ref self: ComponentState<TContractState>,
            consumer: ContractAddress,
            entrypoint: felt252,
            calldata: Array<felt252>,
            nonce: felt252, // allow off-chain computation, must be valid
            as_zero: bool, // request as zero address
        ) -> felt252 {
            let caller = if as_zero {
                starknet::contract_address_const::<0>()
            } else {
                get_caller_address()
            };

            // revert if user already requesting
            let is_committed = self.is_committed(consumer, caller);
            assert(!is_committed, Errors::ALREADY_COMMITTED);

            let mut curr_nonce = self.VrfProvider_nonces.read((consumer, caller));
            curr_nonce += 1;
            // check submitted nonce matches
            assert(nonce == curr_nonce, Errors::INVALID_NONCE);
            self.VrfProvider_nonces.write((consumer, caller), nonce);

            let request = Request { consumer, caller, entrypoint, calldata, nonce };

            let seed = request.hash();

            self.commit(consumer, caller, seed);

            // println!("request_random: {:?}", request);
            // println!("seed: {:?}", seed);

            self
                .emit(
                    RequestRandom {
                        consumer: request.consumer,
                        caller: request.caller,
                        entrypoint: request.entrypoint,
                        calldata: request.calldata,
                        nonce: request.nonce,
                        seed,
                    }
                );

            seed
        }

        // called by executors
        fn submit_random(ref self: ComponentState<TContractState>, seed: felt252, proof: Proof) {
            // check status
            assert(!self.is_fulfilled(seed),Errors::ALREADY_FULFILLED);

            // verify proof
            let pubkey: Point = self.get_public_key().into();
            let ecvrf = ECVRFImpl::new(pubkey);

            let random = ecvrf.verify(proof.clone(), array![seed.clone()].span()).expect(Errors::INVALID_PROOF);

            // write random
            self.VrfProvider_request_random.write(seed, random);

            self.emit(SubmitRandom { seed, proof });
        }

        // note: consumer contract can consume for any caller
        fn consume_random(
            ref self: ComponentState<TContractState>, caller: ContractAddress, seed: felt252
        ) -> felt252 {
            // check if request is fulfilled
            assert(self.is_fulfilled(seed), Errors::REQUEST_NOT_FULFILLED);

            let consumer = get_caller_address();

            // clear caller commit for a consumer
            self.clear_commit(consumer, caller);

            let random = self.VrfProvider_request_random.read(seed);

            random
        }

        // called by consumer contract to retrieve current seed for for a consumer / entrypoint /
        // calldata / caller
        fn get_seed_for_call(
            self: @ComponentState<TContractState>,
            caller: ContractAddress,
            entrypoint: felt252,
            calldata: Array<felt252>,
        ) -> felt252 {
            let consumer = get_caller_address();

            let nonce = self.VrfProvider_nonces.read((consumer, caller));
            let request = Request { consumer, caller, entrypoint, calldata, nonce };

            let seed = request.hash();

            // println!("get_seed_for_call: {:?}", request);
            // println!("seed: {:?}", seed);

            seed
        }

        fn get_commit(
            self: @ComponentState<TContractState>,
            consumer: ContractAddress,
            caller: ContractAddress
        ) -> felt252 {
            self.VrfProvider_commit.read((consumer, caller))
        }

        fn is_fulfilled(self: @ComponentState<TContractState>, seed: felt252) -> bool {
            self.get_random(seed) != 0
        }

        fn get_random(self: @ComponentState<TContractState>, seed: felt252) -> felt252 {
            self.VrfProvider_request_random.read(seed)
        }

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

        fn is_committed(
            self: @ComponentState<TContractState>,
            consumer: ContractAddress,
            caller: ContractAddress
        ) -> bool {
            self.VrfProvider_commit.read((consumer, caller)) != 0
        }

        fn commit(
            ref self: ComponentState<TContractState>,
            consumer: ContractAddress,
            caller: ContractAddress,
            seed: felt252
        ) {
            self.VrfProvider_commit.write((consumer, caller), seed)
        }

        fn clear_commit(
            ref self: ComponentState<TContractState>,
            consumer: ContractAddress,
            caller: ContractAddress,
        ) {
            self.VrfProvider_commit.write((consumer, caller), 0)
        }
    }
}
