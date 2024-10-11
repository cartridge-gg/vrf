#[starknet::interface]
trait IVrfConsumerTemplate<T> {
    fn dice(ref self: T);
}

#[dojo::contract]
mod consumer_template {
    use starknet::ContractAddress;
    use starknet::get_caller_address;

    use vrf_contracts::vrf_consumer::vrf_consumer_component::VrfConsumerComponent;
    use vrf_contracts::vrf_provider::vrf_provider_component::Source;

    component!(path: VrfConsumerComponent, storage: vrf_consumer, event: VrfConsumerEvent);

    #[abi(embed_v0)]
    impl VrfConsumerImpl = VrfConsumerComponent::VrfConsumerImpl<ContractState>;

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

    #[abi(embed_v0)]
    fn dojo_init(ref self: ContractState, vrf_provider: ContractAddress) {
        self.vrf_consumer.initializer(vrf_provider);
    }

    #[abi(embed_v0)]
    impl VrfConsumerTemplateImpl of super::IVrfConsumerTemplate<ContractState> {
        fn dice(ref self: ContractState) {
            let player_id = get_caller_address();
            let random: u256 = self.vrf_consumer.consume_random(Source::Nonce(player_id)).into();
            let value: u8 = (random % 6).try_into().unwrap() + 1;
            // do the right things
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {}
}

