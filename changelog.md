# General
1. Added dependency management. Fix Openzeppelin imports 

# 2026-02-25

## IDOManager
1. Enforce `timeoutForRefundAfterVesting` in refund eligibility logic after vesting ends (`tge + cliff + vesting + timeout`)
2. Add new refund denial reason code `12` for expired post-vesting refund window

## IIDOManager
1. Update NatSpec reason code documentation to include code `12` (`Refund window after vesting has expired`)

## Tests
1. Add unit coverage for refund-timeout reason code (`12`) and deadline boundary behavior in `RefundReason.t.sol`
2. Add execution-path tests for exact-deadline success and post-deadline `RefundNotAvailable()` revert in `IDOManager.t.sol`

# 2026-02-23

## IDOManager
1. Extend no-penalty full refund disqualification window from TWAP calculation window only to the entire period from TWAP calculation window start until full refund window end
2. Remove unused `_isWithinTWAPCalculationWindow` helper

# 2026-02-22

## IDOManager
1. Add `getRefundNotAllowedReason(uint256 idoId, address user, bool fullRefund)` public view function that returns a `uint8` reason code explaining why a refund is not allowed (0 = allowed, 1–11 = specific denial reasons)
2. Add `getRefundNotAllowedReason` to `IIDOManager` interface with full NatSpec documentation of all reason codes
3. Refactor `_isRefundAllowed()` to delegate to new internal `_getRefundNotAllowedReason()`, preserving existing behavior while enabling reason code reporting

# 2026-02-04

## KYCVerifier
1. Now KYC Verification requires caller verification

## ReservesManager / EmergencyWithdraw
1. Add unit tests for `ReservesManager` constructor validation, supported tokens/prices, and `setStaticPrice` access control
2. Add unit tests for `EmergencyWithdrawAdmin.emergencyWithdraw` (ERC20 + native ETH), including permissions and zero-amount revert

## AdminManager / EmergencyWithdrawAdmin
1. Replace string-based `require()` messages with custom errors from `Errors.sol` (`InvalidZeroAddress`, `CallerNotSuperAdmin`, `InvalidAmount`)

## Tests
1. Remove legacy `KYCRegistry` usage and migrate tests to signature-based `KYCVerifier` flow
2. Remove outdated integration tests depending on removed reserves-withdrawal APIs


# 2026-02-03

## KYCVerifier
1. Update `verifyKYC()` to accept explicit `user` parameter instead of using `msg.sender`
2. Update `IDOManager.invest()` to pass `msg.sender` as user to `kycVerifier.verifyKYC()`
3. Update all KYCVerifier unit tests to include the new `user` parameter


## IDOManager
1. Update `_calcRefundFlags()` to remove unused variable
2. Removed `WithAdminManager` duplicated inheritance from IDOManager

Acceptable tokens can now be set from the constructor

# 2026-01-28

## Configurable KYC Threshold
1. Add `kycThresholdUSD` state variable (default 100 USD) - investments >= threshold require KYC, below threshold KYC is optional
2. Add `setKYCThresholdUSD()` admin setter to change the threshold
3. Add `KYCThresholdUSDSet` event
4. Update `invest()` to conditionally verify KYC based on investment amount vs threshold

## KYC Verification - KYCRegistry → KYCVerifier

### New Contracts
1. Add `KYCVerifier.sol` - EIP-712 signature-based KYC verification with nonce replay protection
2. Add `IKYCVerifier.sol` - Interface for KYCVerifier
3. Add `WithKYCVerifier.sol` - Abstract contract for KYCVerifier integration

### IDOManager Changes
1. Replace `WithKYCRegistry` with `WithKYCVerifier`
2. Update `invest()` signature: add `kycExpires` and `kycSignature` parameters
3. Remove `onlyKYC` modifier, now calls `kycVerifier.verifyKYC()` directly
4. Rename `setKYCRegistry()` → `setKYCVerifier()`
5. Rename event `KYCRegistrySet` → `KYCVerifierSet`

### Breaking Changes
- `invest(uint256 idoId, uint256 amount, address tokenIn)` → `invest(uint256 idoId, uint256 amount, address tokenIn, uint256 kycExpires, bytes calldata kycSignature)`
- Constructor `_kyc` parameter now expects KYCVerifier address instead of KYCRegistry

### Tests
1. Add comprehensive unit tests for KYCVerifier (27 tests covering constructor, setKYCSigner, verifyKYC, nonces, replay attacks, fuzz tests)

---

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