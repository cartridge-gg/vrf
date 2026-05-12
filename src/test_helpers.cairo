use snforge_std::{ContractClass, ContractClassTrait, DeclareResultTrait, declare, get_class_hash};
use starknet::ContractAddress;

#[generate_trait]
pub impl AsAddressImpl of AsAddressTrait {
    const fn as_address(self: felt252) -> ContractAddress {
        self.try_into().unwrap()
    }
}

pub const OWNER: ContractAddress = 'OWNER'.as_address();
pub const AUTHORIZED: ContractAddress = 'AUTHORIZED'.as_address();

pub fn declare_and_deploy_at(
    name: ByteArray, contract_address: ContractAddress, calldata: Array<felt252>,
) {
    let contract = declare(name).unwrap().contract_class();
    contract.deploy_at(@calldata, contract_address).unwrap();
}

pub fn deploy_another_at(
    existing: ContractAddress, new_address: ContractAddress, calldata: Array<felt252>,
) {
    let class_hash = get_class_hash(existing);
    let contract = ContractClass { class_hash };
    contract.deploy_at(@calldata, new_address).unwrap();
}
