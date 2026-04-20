// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDOManager} from "../../src/IDOManager.sol";
import {KYCVerifier} from "../../src/kyc/KYCVerifier.sol";
import {AdminManager} from "../../src/admin_manager/AdminManager.sol";
import {IIDOManager} from "../../src/interfaces/IIDOManager.sol";
import {ReservesManager} from "../../src/ReservesManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20R is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RefundReasonTest is Test {
    IDOManager internal idoManager;
    KYCVerifier internal kycVerifier;
    AdminManager internal adminManager;

    MockERC20R internal usdt;
    MockERC20R internal usdc;
    MockERC20R internal flx;
    MockERC20R internal idoToken;

    address internal owner = address(this);
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");

    uint256 internal constant KYC_EXPIRES = 0;
    bytes internal constant KYC_SIG = hex"";
    uint256 internal constant HUNDRED_PERCENT = 10_000_000;

    function setUp() public {
        usdt = new MockERC20R("USDT", "USDT", 6);
        usdc = new MockERC20R("USDC", "USDC", 6);
        flx = new MockERC20R("FLX", "FLX", 18);
        idoToken = new MockERC20R("IDO Token", "IDO", 18);

        kycVerifier = new KYCVerifier(makeAddr("signer"));
        adminManager = new AdminManager(owner, admin, owner);

        ReservesManager.TokenConfig[] memory tokens = new ReservesManager.TokenConfig[](3);
        tokens[0] = ReservesManager.TokenConfig({token: address(usdt), price: 1e8});
        tokens[1] = ReservesManager.TokenConfig({token: address(usdc), price: 1e8});
        tokens[2] = ReservesManager.TokenConfig({token: address(flx), price: 1e8});

        idoManager = new IDOManager(tokens, address(kycVerifier), address(adminManager));

        vm.prank(admin);
        idoManager.setKYCThresholdUSD(type(uint256).max);
    }

    function _createIDOWithPolicy(
        IIDOManager.RefundPolicy memory refundPolicy
    ) internal returns (uint256) {
        uint64 startTime = uint64(block.timestamp + 1 days);
        IIDOManager.IDOInput memory idoInput = IIDOManager.IDOInput({
            info: IIDOManager.IDOInfo({
                tokenAddress: address(0),
                projectId: 1,
                totalAllocated: 0,
                minAllocationUSD: 100e18,
                totalAllocationByUser: 10000e18,
                totalAllocation: 1000000e18
            }),
            bonuses: IIDOManager.IDOBonuses({
                phase1BonusPercent: 0,
                phase2BonusPercent: 0,
                phase3BonusPercent: 0
            }),
            schedules: IIDOManager.IDOSchedules({
                idoStartTime: startTime,
                idoEndTime: startTime + 10 days,
                claimStartTime: 0,
                tgeTime: 0,
                cliffDuration: 7 days,
                vestingDuration: 30 days,
                unlockInterval: 1 days,
                twapCalculationWindowHours: 24,
                timeoutForRefundAfterVesting: 90 days,
                tgeUnlockPercent: 1_000_000 // 10%
            }),
            refundPenalties: IIDOManager.RefundPenalties({
                fullRefundPenalty: 500_000,
                fullRefundPenaltyBeforeTge: 200_000,
                refundPenalty: 1_000_000
            }),
            refundPolicy: refundPolicy,
            initialPriceUsdt: 1e8,
            fullRefundPriceUsdt: 7e7
        });

        vm.prank(admin);
        return idoManager.createIDO(idoInput);
    }

    function _defaultPolicy() internal pure returns (IIDOManager.RefundPolicy memory) {
        return IIDOManager.RefundPolicy({
            fullRefundDuration: 7 days,
            isRefundIfClaimedAllowed: true,
            isRefundUnlockedPartOnly: false,
            isRefundInCliffAllowed: true,
            isFullRefundBeforeTGEAllowed: true,
            isPartialRefundInCliffAllowed: true,
            isFullRefundInCliffAllowed: true,
            isPartialRefundInVestingAllowed: true,
            isFullRefundInVestingAllowed: true
        });
    }

    function _investUser(uint256 idoId) internal {
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        if (block.timestamp < idoStart) {
            vm.warp(idoStart);
        }
        usdt.mint(user, 1000e6);
        vm.prank(user);
        IERC20(address(usdt)).approve(address(idoManager), 1000e6);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
    }

    function _setTgeAndClaim(uint256 idoId, uint64 tgeTime) internal {
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);
    }

    // ── Code 11: No investment ──

    function test_reason_11_noInvestment() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 11, "Should return 11 for user with no investment");
    }

    // ── Code 1: Claimed and policy forbids refund after claim ──

    function test_reason_1_claimedAndPolicyForbids() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isRefundIfClaimedAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp to TGE so claim is possible
        vm.warp(tgeTime);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 1, "Should return 1 when user claimed and policy forbids refund after claim");
    }

    // ── Code 2: Before TGE, partial refund not allowed ──

    function test_reason_2_beforeTGE_partialRefund() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        _investUser(idoId);

        // TGE not set yet → before TGE
        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reason, 2, "Should return 2 for partial refund before TGE");
    }

    // ── Code 3: Before TGE, full refund not allowed by policy ──

    function test_reason_3_beforeTGE_fullRefundNotAllowed() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isFullRefundBeforeTGEAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        _investUser(idoId);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 3, "Should return 3 when full refund before TGE not allowed by policy");
    }

    // ── Code 0: Before TGE, full refund allowed ──

    function test_reason_0_beforeTGE_fullRefundAllowed() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        _investUser(idoId);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 0, "Should return 0 when full refund before TGE is allowed");
    }

    // ── Code 7: In cliff, full refund not allowed ──

    function test_reason_7_inCliff_fullRefundNotAllowed() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isFullRefundInCliffAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp to during cliff (TGE started but cliff not finished)
        // cliffDuration = 7 days, so warp to TGE + 1 day (within cliff)
        vm.warp(uint256(tgeTime) + 1 days);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 7, "Should return 7 when full refund in cliff not allowed");
    }

    // ── Code 8: In cliff, partial refund not allowed ──

    function test_reason_8_inCliff_partialRefundNotAllowed() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isPartialRefundInCliffAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp to during cliff
        vm.warp(uint256(tgeTime) + 1 days);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reason, 8, "Should return 8 when partial refund in cliff not allowed");
    }

    // ── Code 9: In vesting, full refund not allowed ──

    function test_reason_9_inVesting_fullRefundNotAllowed() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isFullRefundInVestingAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp past cliff (7 days) into vesting
        vm.warp(uint256(tgeTime) + 8 days);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 9, "Should return 9 when full refund in vesting not allowed");
    }

    // ── Code 10: In vesting, partial refund not allowed ──

    function test_reason_10_inVesting_partialRefundNotAllowed() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isPartialRefundInVestingAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp past cliff (7 days) into vesting
        vm.warp(uint256(tgeTime) + 8 days);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reason, 10, "Should return 10 when partial refund in vesting not allowed");
    }

    // ── Code 0: In vesting, refund allowed ──

    function test_reason_0_inVesting_refundAllowed() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Warp past cliff into vesting
        vm.warp(uint256(tgeTime) + 8 days);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 0, "Should return 0 when vesting refund is allowed");

        uint8 reasonPartial = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reasonPartial, 0, "Should return 0 when partial vesting refund is allowed");
    }

    // ── Code 12: Refund window after vesting expired ──

    function test_reason_12_afterVestingTimeoutExpired() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // cliff(7d) + vesting(30d) + timeout(90d) + 1s
        vm.warp(uint256(tgeTime) + 127 days + 1);

        uint8 reasonFull = idoManager.getRefundNotAllowedReason(idoId, user, true);
        uint8 reasonPartial = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reasonFull, 12, "Should return 12 after refund window expires (full)");
        assertEq(reasonPartial, 12, "Should return 12 after refund window expires (partial)");
    }

    function test_reason_0_atExactVestingTimeoutDeadline() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // At exact deadline, refund is still allowed (> deadline is blocked)
        vm.warp(uint256(tgeTime) + 127 days);

        uint8 reasonFull = idoManager.getRefundNotAllowedReason(idoId, user, true);
        uint8 reasonPartial = idoManager.getRefundNotAllowedReason(idoId, user, false);
        assertEq(reasonFull, 0, "Should allow full refund exactly at deadline");
        assertEq(reasonPartial, 0, "Should allow partial refund exactly at deadline");
    }

    // ── Code 0: TWAP no-penalty full refund path (eligible) ──

    function test_reason_0_twapNoPenaltyFullRefund() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        // Disable cliff/vesting full refund so only TWAP path allows it
        policy.isFullRefundInCliffAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // below fullRefundPriceUsdt of 7e7
        _investUser(idoId);

        // Warp past TWAP window (24h after TGE) but within full refund duration
        vm.warp(uint256(tgeTime) + 24 hours);

        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 0, "Should return 0 when TWAP no-penalty full refund is eligible");
    }

    // ── TWAP disqualified user falls through to cliff/vesting check ──

    function test_reason_twapDisqualified_fallsThrough() public {
        IIDOManager.RefundPolicy memory policy = _defaultPolicy();
        policy.isFullRefundInCliffAllowed = false;
        uint256 idoId = _createIDOWithPolicy(policy);
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7);
        _investUser(idoId);

        // Claim during TWAP window to get disqualified
        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        // Warp past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

        // Still in cliff (7 days), full refund in cliff not allowed → code 7
        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        assertEq(reason, 7, "Disqualified user should fall through to cliff check and get code 7");
    }

    // ── Consistency: reason code 0 iff isRefundAvailable is true ──

    function test_reason_consistentWithIsRefundAvailable() public {
        uint256 idoId = _createIDOWithPolicy(_defaultPolicy());
        (uint64 idoStart,,,,,,,,,) = idoManager.idoSchedules(idoId);
        uint64 tgeTime = idoStart + 11 days;
        _setTgeAndClaim(idoId, tgeTime);
        _investUser(idoId);

        // Before TGE - full refund
        uint8 reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        vm.prank(user);
        bool available = idoManager.isRefundAvailable(idoId, true);
        assertEq(reason == 0, available, "Reason 0 should match isRefundAvailable true");

        // Before TGE - partial refund
        uint8 reasonPartial = idoManager.getRefundNotAllowedReason(idoId, user, false);
        vm.prank(user);
        bool availablePartial = idoManager.isRefundAvailable(idoId, false);
        assertEq(reasonPartial == 0, availablePartial, "Reason 0 should match isRefundAvailable true (partial)");

        // After TGE, in cliff
        vm.warp(uint256(tgeTime) + 1 days);

        reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        vm.prank(user);
        available = idoManager.isRefundAvailable(idoId, true);
        assertEq(reason == 0, available, "Reason 0 should match isRefundAvailable in cliff");

        // After cliff, in vesting
        vm.warp(uint256(tgeTime) + 8 days);

        reason = idoManager.getRefundNotAllowedReason(idoId, user, true);
        vm.prank(user);
        available = idoManager.isRefundAvailable(idoId, true);
        assertEq(reason == 0, available, "Reason 0 should match isRefundAvailable in vesting");
    }
}
