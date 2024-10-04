pub mod vrf_provider {
    pub mod vrf_provider;
    pub mod vrf_provider_component;
}

pub mod vrf_consumer {
    pub mod vrf_consumer_component;
    pub mod vrf_consumer_example;
}

pub mod utils;

#[cfg(test)]
pub mod tests {
    pub mod common;
    pub mod test_dice_no_commit;
    pub mod test_dice_with_commit;
    pub mod test_shared_dice_no_commit;
    pub mod test_shared_dice_with_commit;
    pub mod test_predict;
    pub mod test_action;
}

