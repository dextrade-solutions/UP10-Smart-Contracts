# Up10 IDO Contracts Technical Documentation

This document provides a detailed technical overview of the Up10 IDO (Initial DEX Offering) system, covering architecture, contract roles, lifecycle, investment logic, and refund mechanisms.

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Contract Roles & Permissions](#contract-roles--permissions)
3. [IDO Lifecycle](#ido-lifecycle)
4. [Investment Mechanism](#investment-mechanism)
5. [Phases and Bonuses](#phases-and-bonuses)
6. [KYC Verification](#kyc-verification)
7. [Vesting & Claiming](#vesting--claiming)
8. [Refund System](#refund-system)
9. [Emergency Procedures](#emergency-procedures)
10. [Data Models (Structs)](#data-models-structs)

---

## System Architecture

The Up10 IDO system is built around a central `IDOManager` contract that coordinates the creation and execution of IDOs. It leverages several modular components for administration, KYC verification, and asset management.

### Key Contracts:
- **`IDOManager`**: The core logic engine for IDOs. It handles investments, claims, refunds, and phase management.
- **`AdminManager`**: Manages administrative roles (Admins and Super Admin).
- **`KYCVerifier`**: Handles EIP-712 based off-chain KYC signature verification.
- **`ReservesManager`**: Tracks funds raised and refunded per IDO.
- **`EmergencyWithdrawAdmin`**: Provides emergency fund recovery capabilities.

*Note: `KYCRegistry.sol` is deprecated and not used in the current implementation.*

---

## Contract Roles & Permissions

The system uses a tiered administrative model managed by `AdminManager`:

- **Owner**: Can add/remove Admins and change the Super Admin.
- **Super Admin**: Has high-level permissions, including setting the KYC Verifier and performing emergency withdrawals.
- **Admin**: Can create IDOs, set schedules (TGE, Claim Start), update pricing (Static, TWAP), and set KYC thresholds.

---

## IDO Lifecycle

1. **Creation**: An Admin calls `createIDO` with comprehensive configuration (schedules, bonuses, refund policies).
2. **Investment**: Users invest stablecoins (USDT/USDC) during the IDO window. If the investment exceeds the `kycThresholdUSD`, a valid KYC signature is required.
3. **Phases**: IDOs automatically transition through Phase 1, 2, and 3 based on the percentage of total allocation sold, applying corresponding bonuses.
4. **TGE (Token Generation Event)**: Marking the start of the vesting period.
5. **Vesting & Claims**: Users claim tokens according to the schedule (TGE Unlock -> Cliff -> Linear Vesting).
6. **Refunds**: Users can request refunds if eligible, subject to timing and TWAP conditions.

---

## Investment Mechanism

Users invest using `invest(idoId, amount, tokenIn, kycExpires, kycSignature)`.

- **Accepted Tokens**: USDT, USDC, and FLX (via `staticPrices` mapping).
- **Normalization**: All amounts are normalized to 18 decimals for internal calculations.
- **KYC Requirement**: Mandatory for investments above `kycThresholdUSD` (default 100 USD).
- **Allocation Limits**: Checks both per-user and total IDO allocation limits.

---

## Phases and Bonuses

IDOs are divided into three phases based on the amount of tokens sold:
- **Phase 1**: First 1/3 of total allocation.
- **Phase 2**: Second 1/3 of total allocation.
- **Phase 3**: Final 1/3 of total allocation.

Each phase can have a unique bonus percentage (e.g., Phase 1 may offer higher bonuses than Phase 3). Bonuses are calculated at the time of investment.

---

## KYC Verification

Uses EIP-712 typed data signatures to verify off-chain KYC status.
- **Domain**: `KYCVerifier`, Version `1.0`.
- **Signer**: A trusted `kycSigner` address set by the Super Admin.
- **Anti-Replay**: Each user has a nonce that increments upon successful verification.

---

## Vesting & Claiming

The system implements a flexible vesting schedule:
- **TGE Unlock**: A percentage of tokens available immediately at TGE.
- **Cliff**: A period after TGE where no further tokens are unlocked.
- **Linear Vesting**: Periodic unlocks over a specified duration after the cliff.
- **Unlock Interval**: The frequency of linear unlocks (e.g., every 1 second or every 30 days).

Users claim unlocked tokens via `claimTokens(idoId)`.

---

## Refund System

The system features a complex, policy-driven refund mechanism controlled by `RefundPolicy` and `RefundPenalties`.

### Refund Types:
- **Full Refund**: Returns the full invested value (minus penalties).
- **Partial Refund**: Returns only the value corresponding to unlocked/unclaimed tokens.

### Eligibility Factors:
- **Timing**: Refunds can be allowed/disallowed during Cliff, Vesting, or before TGE.
- **TWAP Condition**: If the project token's TWAP price falls below `fullRefundPriceUsdt`, users may become eligible for a penalty-free full refund.
- **Claim Status**: Some policies may prevent refunds if the user has already claimed tokens.

### Penalties:
Penalties are deducted from the refunded amount and tracked as `penaltyFeesCollected`.

---

## Emergency Procedures

In case of critical issues or if funds need to be recovered, the Super Admin can use `emergencyWithdraw(token, amount)` provided by `EmergencyWithdrawAdmin`. This allows for the withdrawal of any ERC20 token or native currency held by the contract.

---

## Data Models (Structs)

### `IDOInfo`
Stores core metadata:
- `tokenAddress`: Address of the project token.
- `totalAllocated`: Total tokens currently allocated to investors.
- `minAllocationUSD`: Minimum investment allowed per user.
- `totalAllocationByUser`: Maximum tokens allowed per user.
- `totalAllocation`: Total tokens available in the IDO.

### `IDOSchedules`
Defines timing:
- `idoStartTime`/`idoEndTime`: The investment window.
- `tgeTime`: Start of vesting.
- `claimStartTime`: When users can begin claiming.
- `vestingDuration`/`cliffDuration`/`unlockInterval`: Vesting parameters.

### `RefundPolicy`
Boolean flags for flexibility:
- `isRefundIfClaimedAllowed`: Can refund after claiming?
- `isRefundInCliffAllowed`: Can refund during cliff?
- `isFullRefundBeforeTGEAllowed`: Can refund before TGE?
- etc.

### `UserInfo`
Tracks user state:
- `investedUsdt`: Total value invested.
- `allocatedTokens`: Total tokens (including bonuses).
- `claimedTokens`: Amount already claimed.
- `refundedTokens`: Amount already refunded.
- `investedToken`: Address of the stablecoin used.
