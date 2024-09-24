

# VRF for Cartridge Controller with paymaster


caller send multicall :
```
[
    vrf_provider.request_random(),
    game_contract.you_function_consuming_randomness(...params)
]
```
Cartridge backend receive the tx,
retrieve seed using vrf_provider.get_next_seed( caller ),
compute proof for seed
and inject calls to sandwitch caller in a multicall :
```
[
    vrf_provider.submit_random( seed, proof),
    controller.outside_execution([
        vrf_provider.request_random(),
        game_contract.you_function_consuming_randomness(...params)
    ])
    vrf_provider.assert_consumed( seed ),
]
```

# Notes

- caller must be a Cartridge Controller
- Randomness must be consume
- Randomness can only be consumed once
- Tx (submit_random / user calls / assert_consumed) is executed atomically by Cartridge backend
- Sumbitted randomness only last for the tx duration 
- It's not possible to request_random in a tx and consume_random in another tx
- User cannot probe randomness