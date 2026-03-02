

## Summary

The `swap_exact_token_to` function does not bound `integrator_fee_amount_bps`, allowing arbitrarily large fee values to inflate the internal buy target. Under `FeeOnBuy` policy, this results in an exaggerated `internal_buy_token_amount`, which propagates into `_swap_exact_token_to` and can cause the iterative swap loop to exceed `sell_token_max_amount`, leading to a revert with:

```
"Insufficient token from amount"
```

This creates a denial-of-service (DoS) vector affecting swap liveness.

---

## Vulnerable Component

Function:

```
compute_swap_exact_token_to_integrator_fee_amount()
```

Used inside:

```
swap_exact_token_to()
```

---

## Root Cause

`integrator_fee_amount_bps` is not bounded.

For `FeeOnBuy`, the integrator fee is calculated as:

```
integrator_fee = buy_token_amount * bps / 10000
internal_buy_token_amount = buy_token_amount + integrator_fee
```

If `bps` is extremely large, `internal_buy_token_amount` becomes unrealistically high.

This inflated target is passed into `_swap_exact_token_to`, which attempts to iteratively acquire enough buy tokens by pulling additional sell tokens from the user.

Eventually:

```
sell_token_buy_amount_transfer > remaining_sell_token_amount
```

Triggering:

```
assert(sell_token_buy_amount_transfer <= remaining_sell_token_amount)
```

Resulting in full transaction revert.

---


## Impact

### Direct Fund Loss

None.

The transaction reverts atomically.

### Economic Impact

* Swap liveness can be disrupted.
* If `integrator_fee_amount_bps` is externally controlled (e.g., via integrator backend or relayer), a malicious actor can grief users by forcing all swaps to revert.
* Router robustness depends on external parameter sanity.

### Severity Assessment

| Scenario                        | Severity                                    |
| ------------------------------- | ------------------------------------------- |
| User controls BPS directly      | Informational                               |
| Integrator/backend controls BPS | Low–Medium (griefing / liveness disruption) |

---

## Why This Matters

The router ties fee calculation directly into swap target computation.
Unbounded external economic inputs influence core execution feasibility.

Robust DeFi routers must enforce economic sanity constraints.

---

## Recommended Mitigation

Add upper bound validation before fee computation:

```rust
assert(integrator_fee_amount_bps <= 10000, 'Integrator fee too high');
```

Or define a protocol constant:

```rust
const MAX_INTEGRATOR_FEE_BPS: u128 = 1000; // example: 10%
```

And enforce:

```rust
assert(integrator_fee_amount_bps <= MAX_INTEGRATOR_FEE_BPS);
```

This prevents target inflation from destabilizing swap execution.

---

## Conclusion

The absence of bounds on `integrator_fee_amount_bps` allows economically nonsensical inputs to propagate into swap logic, causing predictable reverts and degrading protocol liveness.

While no direct capital loss occurs, enforcing bounded economic parameters is necessary to ensure router stability and resilience.

---
