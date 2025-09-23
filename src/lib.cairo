pub mod vrf_provider {
    pub mod vrf_provider;
    pub mod vrf_provider_component;
}

pub mod vrf_consumer {
    pub mod vrf_consumer_component;
}

pub mod mocks {
    pub mod vrf_consumer_mock;
}
pub use vrf_consumer::vrf_consumer_component::VrfConsumerComponent;

pub use vrf_provider::vrf_provider_component::{
    IVrfProvider, IVrfProviderDispatcher, IVrfProviderDispatcherTrait, PublicKey, Source,
};

#[cfg(test)]
pub mod tests {
    pub mod common;
    pub mod test_dice;
}
