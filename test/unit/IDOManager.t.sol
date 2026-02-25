// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDOManager} from "../../src/IDOManager.sol";
import {KYCVerifier} from "../../src/kyc/KYCVerifier.sol";
import {IKYCVerifier} from "../../src/interfaces/IKYCVerifier.sol";
import {AdminManager} from "../../src/admin_manager/AdminManager.sol";
import {IIDOManager} from "../../src/interfaces/IIDOManager.sol";
import {ReservesManager} from "../../src/ReservesManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract MockERC20 is ERC20 {
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

contract IDOManagerTest is Test {
    IDOManager internal idoManager;
    KYCVerifier internal kycVerifier;
    AdminManager internal adminManager;

    MockERC20 internal usdt;
    MockERC20 internal usdc;
    MockERC20 internal flx;
    MockERC20 internal randomToken;
    MockERC20 internal idoToken;

    address internal owner = address(this);
    address internal admin = makeAddr("admin");
    address internal user = makeAddr("user");

    uint256 internal constant SIGNER_PRIVATE_KEY = 0xA11CE;
    address internal signer;

    uint256 internal constant KYC_EXPIRES = 0;
    bytes internal constant KYC_SIG = hex"";
    uint256 internal constant HUNDRED_PERCENT = 10_000_000;

    function setUp() public {
        signer = vm.addr(SIGNER_PRIVATE_KEY);

        usdt = new MockERC20("USDT", "USDT", 6);
        usdc = new MockERC20("USDC", "USDC", 6);
        flx = new MockERC20("FLX", "FLX", 18);
        randomToken = new MockERC20("RANDOM", "RND", 18);
        idoToken = new MockERC20("IDO Token", "IDO", 18);

        kycVerifier = new KYCVerifier(signer);
        adminManager = new AdminManager(owner, admin, owner);

        ReservesManager.TokenConfig[] memory tokens = new ReservesManager.TokenConfig[](3);
        tokens[0] = ReservesManager.TokenConfig({token: address(usdt), price: 1e8});
        tokens[1] = ReservesManager.TokenConfig({token: address(usdc), price: 1e8});
        tokens[2] = ReservesManager.TokenConfig({token: address(flx), price: 1e8});

        idoManager = new IDOManager(tokens, address(kycVerifier), address(adminManager));

        vm.startPrank(admin);
        // Disable KYC by default for unit tests unless explicitly enabled in a specific test
        idoManager.setKYCThresholdUSD(type(uint256).max);
        vm.stopPrank();
    }

    function _createBasicIDO(uint64 startTime, uint64 endTime) internal returns (uint256) {
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
                idoEndTime: endTime,
                claimStartTime: 0,
                tgeTime: 0,
                cliffDuration: 0,
                vestingDuration: 1 days,
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
            refundPolicy: IIDOManager.RefundPolicy({
                fullRefundDuration: 7 days,
                isRefundIfClaimedAllowed: true,
                isRefundUnlockedPartOnly: false,
                isRefundInCliffAllowed: true,
                isFullRefundBeforeTGEAllowed: true,
                isPartialRefundInCliffAllowed: true,
                isFullRefundInCliffAllowed: true,
                isPartialRefundInVestingAllowed: true,
                isFullRefundInVestingAllowed: false
            }),
            initialPriceUsdt: 1e8,
            fullRefundPriceUsdt: 5e7
        });

        vm.prank(admin);
        return idoManager.createIDO(idoInput);
    }

    function _mintAndApprove(address userAddr, address token, uint256 amount) internal {
        MockERC20(token).mint(userAddr, amount);
        vm.prank(userAddr);
        IERC20(token).approve(address(idoManager), amount);
    }

    function _createTWAPRefundIDO(uint64 startTime, uint64 endTime) internal returns (uint256) {
        IIDOManager.IDOInput memory idoInput = IIDOManager.IDOInput({
            info: IIDOManager.IDOInfo({
                tokenAddress: address(0),
                projectId: 2,
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
                idoEndTime: endTime,
                claimStartTime: 0,
                tgeTime: 0,
                cliffDuration: 0,
                vestingDuration: 30 days,
                unlockInterval: 1 days,
                twapCalculationWindowHours: 24,
                timeoutForRefundAfterVesting: 90 days,
                tgeUnlockPercent: 3_000_000 // 30%
            }),
            refundPenalties: IIDOManager.RefundPenalties({
                fullRefundPenalty: 500_000, // 5%
                fullRefundPenaltyBeforeTge: 200_000,
                refundPenalty: 1_000_000
            }),
            refundPolicy: IIDOManager.RefundPolicy({
                fullRefundDuration: 7 days,
                isRefundIfClaimedAllowed: true,
                isRefundUnlockedPartOnly: false,
                isRefundInCliffAllowed: true,
                isFullRefundBeforeTGEAllowed: true,
                isPartialRefundInCliffAllowed: true,
                isFullRefundInCliffAllowed: true,
                isPartialRefundInVestingAllowed: true,
                isFullRefundInVestingAllowed: true
            }),
            initialPriceUsdt: 1e8,
            fullRefundPriceUsdt: 7e7 // $0.70
        });

        vm.prank(admin);
        return idoManager.createIDO(idoInput);
    }

    function _setupTWAPScenario() internal returns (uint256 idoId, uint64 tgeTime) {
        uint64 startTime = uint64(block.timestamp + 1 days);
        idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);
    }

    function _signKYC(address userAddr, uint256 expires) internal view returns (bytes memory) {
        uint256 nonce = kycVerifier.nonces(userAddr, address(idoManager));
        bytes32 typehash = keccak256("KYC(address user,address caller,uint256 expires,uint256 nonce)");
        bytes32 structHash = keccak256(abi.encode(typehash, userAddr, address(idoManager), expires, nonce));
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("KYCVerifier")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(kycVerifier)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_createIDO_Success() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));
        assertEq(idoId, 1);
        assertEq(idoManager.idoCount(), 1);
    }

    function test_invest_Success_KYCDisabled() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        _mintAndApprove(user, address(usdt), 100e6);
        vm.prank(user);
        idoManager.invest(idoId, 100e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        (uint256 investedUsdt, uint256 allocatedTokens, , , ) = idoManager.getUserInfo(idoId, user);
        assertEq(investedUsdt, 100e18);
        assertEq(allocatedTokens, 100e18);
    }

    function test_invest_Reverts_InvalidToken() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        _mintAndApprove(user, address(randomToken), 100e18);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        idoManager.invest(idoId, 100e18, address(randomToken), KYC_EXPIRES, KYC_SIG);
    }

    function test_invest_Success_KYCRequired_WithValidProof() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        vm.prank(admin);
        idoManager.setKYCThresholdUSD(0);

        _mintAndApprove(user, address(usdt), 100e6);
        uint256 expires = block.timestamp + 1 hours;
        bytes memory sig = _signKYC(user, expires);

        vm.prank(user);
        idoManager.invest(idoId, 100e6, address(usdt), expires, sig);
    }

    function test_invest_Reverts_KYCRequired_InvalidProof() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        vm.prank(admin);
        idoManager.setKYCThresholdUSD(0);

        _mintAndApprove(user, address(usdt), 100e6);
        uint256 expires = block.timestamp + 1 hours;
        bytes memory sig = _signKYC(user, expires);

        // Corrupt signature (flip a bit) -> should revert InvalidKYCSignature
        sig[0] = bytes1(uint8(sig[0]) ^ 0x01);

        vm.prank(user);
        // When the signature is malformed, OpenZeppelin ECDSA reverts before KYCVerifier's custom error.
        vm.expectRevert(ECDSA.ECDSAInvalidSignature.selector);
        idoManager.invest(idoId, 100e6, address(usdt), expires, sig);
    }

    function test_claimTokens_Success_TGEUnlock() public {
        uint256 idoId = _createBasicIDO(uint64(block.timestamp), uint64(block.timestamp + 30 days));

        _mintAndApprove(user, address(usdt), 100e6);
        vm.prank(user);
        idoManager.invest(idoId, 100e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        uint64 tgeTime = uint64(block.timestamp + 2 days);
        uint64 claimStart = tgeTime;

        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, claimStart);
        vm.stopPrank();

        idoToken.mint(address(idoManager), 1000000e18);

        vm.warp(claimStart);
        uint256 balBefore = idoToken.balanceOf(user);
        vm.prank(user);
        idoManager.claimTokens(idoId);
        uint256 balAfter = idoToken.balanceOf(user);

        // 10% unlocked at TGE of 100 tokens
        assertEq(balAfter - balBefore, 10e18);
    }

    function test_refund_C2_FailedListing_NoActions_GetsNoPenaltyFullRefund() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing: <= $0.70

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_C1_FailedListing_ClaimInTWAPWindow_DisablesNoPenaltyOnly() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_C3_SuccessListing_NoNoPenaltyRefund() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 8e7); // Successful listing: > $0.70

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_FullRefundWindowBoundary_ExactEndDoesNotDisqualify() public {
        address user2 = makeAddr("user2");
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        _mintAndApprove(user, address(usdt), 1000e6);
        _mintAndApprove(user2, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.prank(user2);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        // Set failed TWAP price after TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing

        // user1 claims 1s before full refund window ends → disqualified
        vm.warp(uint256(tgeTime) + 24 hours + 7 days - 1);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        // user2 claims exactly at full refund window end → NOT disqualified
        vm.warp(uint256(tgeTime) + 24 hours + 7 days);
        vm.prank(user2);
        idoManager.claimTokens(idoId);

        // Verify disqualification flags
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));
        assertFalse(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user2));

        // Both get penalty: user1 because disqualified, user2 because full refund window ended
        (, uint256 percentUser1) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        (, uint256 percentUser2) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user2, true);

        assertEq(percentUser1, HUNDRED_PERCENT - 500_000);
        assertEq(percentUser2, HUNDRED_PERCENT - 500_000);
    }

    /// @notice C1: Partial refund during TWAP window also disqualifies from no-penalty full refund
    function test_refund_C1_RefundDuringTWAPWindow_DisablesNoPenaltyFullRefund() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Do partial refund during TWAP window (1 hour after TGE)
        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.processRefund(idoId, false);

        // Verify disqualified from no-penalty full refund
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));

        // Move past TWAP window, set failed TWAP price
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // $0.60 < $0.70 threshold

        // Full refund should be available but WITH penalty (5%)
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
    }

    /// @notice C2: Execute no-penalty full refund after failed listing and verify 100% USDT returned
    function test_refund_C2_ExecuteNoPenaltyFullRefund_VerifyBalances() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Move past TWAP window, set failed TWAP price
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // $0.60 failed listing

        // Verify 100% refund percentage
        (uint256 tokensToRefund, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertEq(tokensToRefund, 1000e18); // all 1000 tokens
        assertEq(percent, HUNDRED_PERCENT); // no penalty

        // Execute full refund and check balances
        uint256 balBefore = usdt.balanceOf(user);
        vm.prank(user);
        idoManager.processRefund(idoId, true);
        uint256 balAfter = usdt.balanceOf(user);

        // 100% of invested 1000 USDT returned (no penalty)
        assertEq(balAfter - balBefore, 1000e6);
    }

    /// @notice C2: Partial refund during TWAP Full Refund Duration still carries penalty
    function test_refund_C2_PartialRefundDuringFullRefundDuration_HasPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Move past TWAP window, set failed TWAP price
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7);

        // Partial refund always has penalty (10%) even during TWAP Full Refund Duration
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, false);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 1_000_000); // 10% partial refund penalty

        // Execute partial refund and verify penalty applied
        uint256 balBefore = usdt.balanceOf(user);
        vm.prank(user);
        idoManager.processRefund(idoId, false);
        uint256 balAfter = usdt.balanceOf(user);

        // Partial refund: only unlocked portion (30% TGE + some vesting) with 10% penalty
        assertGt(balAfter - balBefore, 0);
        // The refund amount should be less than the full unlocked value (due to 10% penalty)
        uint256 fullUnlockedValue = amount * 1e6 / 1e18; // convert from 18 to 6 decimals
        assertLt(balAfter - balBefore, fullUnlockedValue);
    }

    /// @notice C2: After TWAP Full Refund Duration expires, full refund reverts to penalty
    function test_refund_C2_AfterFullRefundDuration_FullRefundHasPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Set failed TWAP
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7);

        // Move past Full Refund Duration (TWAP window 24h + full refund duration 7d)
        vm.warp(uint256(tgeTime) + 24 hours + 7 days);

        // Full refund now has penalty since Full Refund Duration expired
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000); // 5% full refund penalty
    }

    /// @notice C2: Claiming during full refund window (after TWAP) DOES disqualify from no-penalty full refund
    function test_refund_C2_ClaimDuringFullRefundWindow_DisqualifiesFromNoPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Move past TWAP window, set failed TWAP price
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7);

        // Claim tokens during full refund window (after TWAP window) → disqualified
        vm.prank(user);
        idoManager.claimTokens(idoId);
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));

        // Full refund should have penalty since user is disqualified (5% full refund penalty)
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000); // 5% penalty

        // Execute full refund and verify funds returned (with penalty)
        uint256 balBefore = usdt.balanceOf(user);
        vm.prank(user);
        idoManager.processRefund(idoId, true);
        uint256 balAfter = usdt.balanceOf(user);
        assertGt(balAfter - balBefore, 0);
    }

    function test_refund_AtExactVestingTimeoutDeadline_StillAllowed() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // For _setupTWAPScenario IDO: cliff=0, vesting=30d, timeout=90d.
        uint256 deadline = uint256(tgeTime) + 30 days + 90 days;
        vm.warp(deadline);

        assertEq(idoManager.getRefundNotAllowedReason(idoId, user, true), 0);
        assertTrue(idoManager.isRefundAvailable(idoId, true));

        uint256 usdtBefore = usdt.balanceOf(user);
        vm.prank(user);
        idoManager.processRefund(idoId, true);
        uint256 usdtAfter = usdt.balanceOf(user);
        assertGt(usdtAfter - usdtBefore, 0);
    }

    function test_refund_AfterVestingTimeoutDeadline_Reverts() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        uint256 deadline = uint256(tgeTime) + 30 days + 90 days;
        vm.warp(deadline + 1);

        assertEq(idoManager.getRefundNotAllowedReason(idoId, user, true), 12);
        assertFalse(idoManager.isRefundAvailable(idoId, true));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("RefundNotAvailable()"));
        idoManager.processRefund(idoId, true);
    }

    /// @notice C1: Disqualified user retains claim, partial refund (w/penalty), and full refund (w/penalty)
    function test_refund_C1_DisqualifiedUser_CanStillClaimAndRefundWithPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario();

        // Claim during TWAP window → gets disqualified
        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.claimTokens(idoId);
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));

        // Move past TWAP window, set failed TWAP
        vm.warp(uint256(tgeTime) + 24 hours);
        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 6e7);

        // Can still claim more tokens (vesting has progressed)
        uint256 claimable = idoManager.getTokensAvailableToClaim(idoId, user);
        assertGt(claimable, 0);
        uint256 tokenBalBefore = idoToken.balanceOf(user);
        vm.prank(user);
        idoManager.claimTokens(idoId);
        assertGt(idoToken.balanceOf(user) - tokenBalBefore, 0);

        // Can do partial refund with penalty (10%)
        vm.prank(user);
        assertTrue(idoManager.isRefundAvailable(idoId, false));
        (, uint256 partialPercent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, false);
        assertEq(partialPercent, HUNDRED_PERCENT - 1_000_000);

        // Can do full refund with penalty (5%) — NOT no-penalty
        vm.prank(user);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
        (, uint256 fullPercent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertEq(fullPercent, HUNDRED_PERCENT - 500_000);

        // Execute full refund with penalty and verify
        uint256 usdtBalBefore = usdt.balanceOf(user);
        vm.prank(user);
        idoManager.processRefund(idoId, true);
        uint256 usdtBalAfter = usdt.balanceOf(user);
        assertGt(usdtBalAfter - usdtBalBefore, 0);
    }
}

