# General
1. Added dependency management. Fix Openzeppelin imports 

# IDOManager
1. Fix Ownable initialization
2. Remove "isPartialRefundAllowedBeforeTGE" because only full refunds can be allowed before TGE

# Admin Manager
1. Constructor: Admin set from argument, not msg.sender

# 2026-01-27
## Contracts
1. Add super admin role in AdminManager with `onlySuperAdmin`, `isSuperAdminAddress`, `setSuperAdmin`, and `SuperAdminChanged` event
2. Add `CallerNotSuperAdmin` error and wire super admin checks into dependency setters (`setKYCRegistry`, `setAdminManager`)
3. Add `EmergencyWithdrawAdmin` contract and integrate emergency withdrawal flow into `ReservesManager`
4. Restrict accepted investment tokens to USDT/USDC only; FLX investments now revert
5. Expand `Investment` event to include normalized token amount; expand `Refund` event with refunded USDT, penalty USDT, and refund flags
6. Remove Ownable import/inheritance from `IDOManager` and drop `_initialOwner` constructor arg
7. Remove legacy/old withdraw logic and other redundant code paths in `IDOManager` and `ReservesManager`
8. Update reserves admin interface `IReservesManager` to match the new contract changes
9. Initializing USDT and USDC static prices as "1"
10. Remove reserves admin withdrawal entrypoints from `IDOManager` (`getWithdrawableAmount`, `withdrawStablecoins`, `withdrawUnsoldTokens`, `withdrawRefundedTokens`, `withdrawPenaltyFees`) and the related logic in `ReservesManager`
11. Emit refund flags bitmask (before TGE, full refund, TWAP below full-refund price) and refund amounts in normalized token units
12. Allow super admin emergency withdrawals of ERC20 and native ETH via `EmergencyWithdrawAdmin`

## Scripts
1. Add `script/Deploy.s.sol` deployment script
2. Update deployment script to match the new `IDOManager` constructor signature (no `_initialOwner`)

## Tests
1. Update unit/integration tests for super admin constructor parameter and permissions
2. Update Investment/Refund event assertions to match new fields and ordering
3. Convert FLX investment tests to assert reverts (USDT/USDC only)
4. Adjust penalty fee tests to cover USDT/USDC only paths

## Tooling
1. Update submodules in `foundry.lock` and `lib/forge-std`