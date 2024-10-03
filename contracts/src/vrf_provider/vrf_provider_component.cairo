use starknet::ContractAddress;
use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

#[starknet::interface]
trait IVrfProvider<TContractState> {
    fn request_random(
        ref self: TContractState,
        consumer: ContractAddress,
        entrypoint: felt252,
        calldata: Array<felt252>,
    ) -> (felt252, felt252);
    fn submit_random(ref self: TContractState, seed: felt252, proof: Proof);
    fn submit_random_no_proof(ref self: TContractState, seed: felt252, random: felt252);
    fn consume_random(ref self: TContractState, key: felt252) -> felt252;
    //
    fn get_nonce(self: @TContractState, consumer: ContractAddress, key: felt252,) -> felt252;
    fn get_random(self: @TContractState, seed: felt252) -> felt252;
    fn is_fulfilled(self: @TContractState, seed: felt252) -> bool;
    //
    fn get_commit(self: @TContractState, consumer: ContractAddress, key: felt252) -> felt252;
    fn is_committed(self: @TContractState, consumer: ContractAddress, key: felt252) -> bool;
    fn clear_commit(ref self: TContractState, key: felt252);
    //
    fn get_public_key(self: @TContractState) -> PublicKey;
    fn set_public_key(ref self: TContractState, new_pubkey: PublicKey);
}


#[starknet::interface]
trait IVrfConsumerCallback<TContractState> {
    // must check its called by VrfProvider and return a key
    fn on_request_random(
        ref self: TContractState,
        entrypoint: felt252,
        calldata: Array<felt252>,
        caller: ContractAddress,
    ) -> felt252;
}

#[starknet::interface]
trait IVrfConsumerCallbackHelpers<TContractState> {
    // helper to check if a request_random call should included in a multicall
    fn should_request_random(
        self: @TContractState,
        entrypoint: felt252,
        calldata: Array<felt252>,
        caller: ContractAddress,
    ) -> bool;

    fn assert_can_request_random(
        self: @TContractState,
        entrypoint: felt252,
        calldata: Array<felt252>,
        caller: ContractAddress,
        key: felt252,
    );

    // generate a key for a call
    fn get_key_for_call(
        self: @TContractState,
        entrypoint: felt252,
        calldata: Array<felt252>,
        caller: ContractAddress,
    ) -> felt252;
}

//
//
//

fn get_seed_from_key(consumer: ContractAddress, key: felt252, nonce: felt252) -> felt252 {
    core::poseidon::poseidon_hash_span(array![key, consumer.into(), nonce].span())
}


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

    use super::{Request, RequestImpl, RequestTrait, PublicKey, get_seed_from_key};
    use super::{
        IVrfConsumerCallback, IVrfConsumerCallbackDispatcher, IVrfConsumerCallbackDispatcherTrait
    };

    use stark_vrf::ecvrf::{Point, Proof, ECVRF, ECVRFImpl};

    #[storage]
    struct Storage {
        VrfProvider_pubkey: PublicKey,
        // (consumer, key) -> nonce
        VrfProvider_nonces: Map<(ContractAddress, felt252), felt252>,
        // seed -> random
        VrfProvider_random: Map<felt252, felt252>,
        // (consumer, key) -> seed
        VrfProvider_commit: Map<(ContractAddress, felt252), felt252>,
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
        key: felt252,
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
        // directly called by user to request randomness for a consumer / entrypoint / calldata
        fn request_random(
            ref self: ComponentState<TContractState>,
            consumer: ContractAddress,
            entrypoint: felt252,
            calldata: Array<felt252>,
        ) -> (felt252, felt252) {
            let caller = get_caller_address();

            let key = IVrfConsumerCallbackDispatcher { contract_address: consumer }
                .on_request_random(entrypoint, calldata.clone(), caller);

        
            let nonce = self._increase_nonce(consumer, key);
            let seed = get_seed_from_key(consumer, key, nonce);

            self._commit(consumer, key, seed);

            self.emit(RequestRandom { consumer, caller, entrypoint, calldata, key, seed, });

            (key, seed)
        }

        // called by vrf providers
        fn submit_random(ref self: ComponentState<TContractState>, seed: felt252, proof: Proof) {
            // check status
            assert(!self.is_fulfilled(seed), Errors::ALREADY_FULFILLED);

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

        fn consume_random(ref self: ComponentState<TContractState>, key: felt252) -> felt252 {
            let consumer = get_caller_address();
            let nonce = self.get_nonce(consumer, key);
            let seed = get_seed_from_key(consumer, key, nonce);

            // println!("consumer: {:?}", consumer);
            // println!("nonce: {}", nonce);
            // println!("key: {}", key);
            // println!("seed: {}", seed);

            // check if request is fulfilled
            assert(self.is_fulfilled(seed), Errors::REQUEST_NOT_FULFILLED);

            // clear caller commit for a consumer
            self._clear_commit(consumer, key);

            let random = self.VrfProvider_random.read(seed);

            random
        }

        //
        //
        //

        fn get_nonce(
            self: @ComponentState<TContractState>, consumer: ContractAddress, key: felt252,
        ) -> felt252 {
            self.VrfProvider_nonces.read((consumer, key))
        }

        fn get_random(self: @ComponentState<TContractState>, seed: felt252) -> felt252 {
            self.VrfProvider_random.read(seed)
        }

        fn is_fulfilled(self: @ComponentState<TContractState>, seed: felt252) -> bool {
            self.get_random(seed) != 0
        }
        //
        //
        //

        fn get_commit(
            self: @ComponentState<TContractState>, consumer: ContractAddress, key: felt252
        ) -> felt252 {
            self.VrfProvider_commit.read((consumer, key))
        }

        fn is_committed(
            self: @ComponentState<TContractState>, consumer: ContractAddress, key: felt252
        ) -> bool {
            self.VrfProvider_commit.read((consumer, key)) != 0
        }

        fn clear_commit(ref self: ComponentState<TContractState>, key: felt252) {
            let consumer = get_caller_address();
            // clear caller commit for a consumer
            self._clear_commit(consumer, key);
            // // ??

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


        fn _commit(
            ref self: ComponentState<TContractState>,
            consumer: ContractAddress,
            key: felt252,
            seed: felt252,
        ) {
            self.VrfProvider_commit.write((consumer, key), seed)
        }

        fn _clear_commit(
            ref self: ComponentState<TContractState>, consumer: ContractAddress, key: felt252
        ) {
            self.VrfProvider_commit.write((consumer, key), 0)
        }

        fn _increase_nonce(
            ref self: ComponentState<TContractState>, consumer: ContractAddress, key: felt252
        ) -> felt252 {
            let nonce = self.VrfProvider_nonces.read((consumer, key));
            let new_nonce = nonce + 1;
            self.VrfProvider_nonces.write((consumer, key), new_nonce);
            new_nonce
        }
    }
}
