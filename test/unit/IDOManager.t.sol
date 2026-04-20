// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDOManager} from "../../src/IDOManager.sol";
import {KYCVerifier} from "../../src/kyc/KYCVerifier.sol";
import {IKYCVerifier} from "../../src/interfaces/IKYCVerifier.sol";
import {AdminManager} from "../../src/admin_manager/AdminManager.sol";
import {IIDOManager} from "../../src/interfaces/IIDOManager.sol";
import {ReservesManager} from "../../src/ReservesManager.sol";
import "../../src/Errors.sol";
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

    function _createTWAPRefundIDOWithBonus(
        uint64 startTime,
        uint64 endTime,
        uint64 phase1BonusPercent
    ) internal returns (uint256) {
        IIDOManager.IDOInput memory idoInput = IIDOManager.IDOInput({
            info: IIDOManager.IDOInfo({
                tokenAddress: address(0),
                projectId: 3,
                totalAllocated: 0,
                minAllocationUSD: 100e18,
                totalAllocationByUser: 10000e18,
                totalAllocation: 1000000e18
            }),
            bonuses: IIDOManager.IDOBonuses({
                phase1BonusPercent: phase1BonusPercent,
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

    function _setupTWAPScenario(uint256 twapPriceUsdt) internal returns (uint256 idoId, uint64 tgeTime) {
        uint64 startTime = uint64(block.timestamp + 1 days);
        idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        if (twapPriceUsdt > 0) {
            idoManager.setTwapPriceUsdt(idoId, twapPriceUsdt);
        }
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
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
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createBasicIDO(startTime, uint64(startTime + 30 days));

        uint64 tgeTime = uint64(block.timestamp + 2 days);
        uint64 claimStart = tgeTime;

        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, claimStart);
        vm.stopPrank();

        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 100e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 100e6, address(usdt), KYC_EXPIRES, KYC_SIG);

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

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing: <= $0.70
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.warp(uint256(tgeTime) + 24 hours);

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_C1_FailedListing_ClaimInTWAPWindow_DisablesNoPenaltyOnly() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        vm.warp(uint256(tgeTime) + 24 hours);

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_C3_SuccessListing_NoNoPenaltyRefund() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        idoManager.setTwapPriceUsdt(idoId, 8e7); // Successful listing: > $0.70
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.warp(uint256(tgeTime) + 24 hours);

        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
        assertTrue(idoManager.isRefundAvailable(idoId, true));
    }

    function test_refund_FullRefundWindowBoundary_ExactEndDoesNotDisqualify() public {
        address user2 = makeAddr("user2");
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDO(startTime, uint64(startTime + 10 days));

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        idoManager.setTwapPriceUsdt(idoId, 6e7); // Failed listing
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        _mintAndApprove(user2, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.prank(user2);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        vm.warp(uint256(tgeTime) + 24 hours);

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
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Do partial refund during TWAP window (1 hour after TGE)
        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.processRefund(idoId, false);

        // Verify disqualified from no-penalty full refund
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));

        // Move past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

        // Full refund should be available but WITH penalty (5%)
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000);
    }

    /// @notice C2: Execute no-penalty full refund after failed listing and verify 100% USDT returned
    function test_refund_C2_ExecuteNoPenaltyFullRefund_VerifyBalances() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Move past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

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

    function test_ClaimedBonusReducesRefundableBase() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createTWAPRefundIDOWithBonus(startTime, uint64(startTime + 10 days), 1_000_000); // 10%

        uint64 tgeTime = uint64(startTime + 2 days);
        vm.startPrank(admin);
        idoManager.setTokenAddress(idoId, address(idoToken));
        idoManager.setTgeTime(idoId, tgeTime);
        idoManager.setClaimStartTime(idoId, tgeTime);
        vm.stopPrank();
        idoToken.mint(address(idoManager), 1000000e18);

        _mintAndApprove(user, address(usdt), 1000e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        (,,,,,,,,,,, uint256 allocatedTokens, uint256 allocatedBonus,) = idoManager.userInfo(idoId, user);
        assertGt(allocatedBonus, 0);
        uint256 baseAllocated = allocatedTokens - allocatedBonus;

        vm.warp(uint256(tgeTime) + 1 days);
        vm.prank(user);
        idoManager.claimTokens(idoId);

        (, uint256 claimedTokens, uint256 claimedBonus,,,,,,,,,,,) = idoManager.userInfo(idoId, user);
        assertGt(claimedBonus, 0);
        uint256 baseClaimed = claimedTokens - claimedBonus;
        uint256 refundableExpected = baseAllocated - baseClaimed;

        uint256 refundableActual = idoManager.getTokensAvailableToRefund(idoId, user, true);
        assertEq(refundableActual, refundableExpected);

        uint256 shortfall = refundableExpected - refundableActual;
        assertEq(shortfall, 0, "shortfall should be zero after fix");

        (uint256 refundableWithPenalty, uint256 refundPercent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertEq(refundableWithPenalty, refundableExpected);

        uint256 expectedRefundUsdt = (refundableWithPenalty * refundPercent) / HUNDRED_PERCENT;
        uint256 expectedPenaltyUsdt = refundableWithPenalty - expectedRefundUsdt;
        uint256 expectedStablecoinOut = expectedRefundUsdt / 1e12;
        uint256 expectedPenaltySubtractedBonusAmount = allocatedBonus - claimedBonus;
        uint8 expectedRefundFlags = 1 << 1; // full refund only

        uint256 usdtBefore = usdt.balanceOf(user);
        vm.expectEmit(true, true, false, true, address(idoManager));
        emit IIDOManager.Refund(
            idoId,
            user,
            refundableWithPenalty,
            expectedRefundUsdt,
            expectedRefundUsdt,
            expectedPenaltyUsdt,
            expectedPenaltySubtractedBonusAmount,
            expectedRefundFlags
        );
        vm.prank(user);
        idoManager.processRefund(idoId, true);
        uint256 usdtAfter = usdt.balanceOf(user);

        assertEq(usdtAfter - usdtBefore, expectedStablecoinOut);

        (,,,, uint256 userPenaltySubtractedBonus,,,,,,,,,) = idoManager.userInfo(idoId, user);
        assertEq(userPenaltySubtractedBonus, expectedPenaltySubtractedBonusAmount);

        (uint256 totalRefunded, uint256 idoPenaltySubtractedBonus,,,) = idoManager.idoRefundInfo(idoId);
        assertEq(totalRefunded, refundableWithPenalty);
        assertEq(idoPenaltySubtractedBonus, expectedPenaltySubtractedBonusAmount);
    }

    /// @notice C2: Partial refund during TWAP Full Refund Duration still carries penalty
    function test_refund_C2_PartialRefundDuringFullRefundDuration_HasPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Move past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

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
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Move past Full Refund Duration (TWAP window 24h + full refund duration 7d)
        vm.warp(uint256(tgeTime) + 24 hours + 7 days);

        // Full refund now has penalty since Full Refund Duration expired
        (uint256 amount, uint256 percent) = idoManager.getTokensAvailableToRefundWithPenalty(idoId, user, true);
        assertGt(amount, 0);
        assertEq(percent, HUNDRED_PERCENT - 500_000); // 5% full refund penalty
    }

    /// @notice C2: Claiming during full refund window (after TWAP) DOES disqualify from no-penalty full refund
    function test_refund_C2_ClaimDuringFullRefundWindow_DisqualifiesFromNoPenalty() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Move past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

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

    function test_setTwapPriceUsdt_AllowsAtDeadline() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(0);
        uint256 deadline = uint256(tgeTime) + 24 hours + 1 hours;
        vm.warp(deadline);

        vm.prank(admin);
        idoManager.setTwapPriceUsdt(idoId, 9e7);

        (, , uint256 twapPrice) = idoManager.idoPricing(idoId);
        assertEq(twapPrice, 9e7);
    }

    function test_setTwapPriceUsdt_RevertsWhenSetSecondTime() public {
        (uint256 idoId,) = _setupTWAPScenario(8e7);

        vm.prank(admin);
        vm.expectRevert(TwapPriceAlreadySet.selector);
        idoManager.setTwapPriceUsdt(idoId, 9e7);
    }

    function test_refund_AtExactVestingTimeoutDeadline_StillAllowed() public {
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(0);

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
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(0);

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
        (uint256 idoId, uint64 tgeTime) = _setupTWAPScenario(6e7);

        // Claim during TWAP window → gets disqualified
        vm.warp(uint256(tgeTime) + 1 hours);
        vm.prank(user);
        idoManager.claimTokens(idoId);
        assertTrue(idoManager.twapNoPenaltyFullRefundDisqualified(idoId, user));

        // Move past TWAP window
        vm.warp(uint256(tgeTime) + 24 hours);

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

    function test_RefundedCapacityReusedForInvestment() public {
        address investor1 = makeAddr("investor1");
        address investor2 = makeAddr("investor2");
        address investor3 = makeAddr("investor3");
        address newInvestor = makeAddr("newInvestor");

        uint64 startTime = uint64(block.timestamp + 1 days);
        uint64 endTime = uint64(block.timestamp + 365 days);

        IIDOManager.IDOInput memory idoInput = IIDOManager.IDOInput({
            info: IIDOManager.IDOInfo({
                tokenAddress: address(0),
                projectId: 999,
                totalAllocated: 0,
                minAllocationUSD: 100e18,
                totalAllocationByUser: 3000e18,
                totalAllocation: 3000e18
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
                tgeUnlockPercent: 1_000_000
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
                isFullRefundInVestingAllowed: true
            }),
            initialPriceUsdt: 1e8,
            fullRefundPriceUsdt: 5e7
        });

        vm.prank(admin);
        uint256 idoId = idoManager.createIDO(idoInput);

        vm.startPrank(admin);
        idoManager.setTgeTime(idoId, startTime);
        idoManager.setClaimStartTime(idoId, startTime);
        idoManager.setTokenAddress(idoId, address(idoToken));
        vm.stopPrank();

        _mintAndApprove(investor1, address(usdt), 1000e6);
        _mintAndApprove(investor2, address(usdt), 1000e6);
        _mintAndApprove(investor3, address(usdt), 1000e6);

        vm.warp(startTime);

        vm.prank(investor1);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.prank(investor2);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.prank(investor3);
        idoManager.invest(idoId, 1000e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        (,, IIDOManager.IDOInfo memory infoBefore,) = idoManager.idos(idoId);
        emit log_named_uint("totalAllocated after 3 investors", infoBefore.totalAllocated);
        emit log_named_uint("totalAllocation (IDO cap)", infoBefore.totalAllocation);
        assertEq(infoBefore.totalAllocated, infoBefore.totalAllocation, "IDO must be exactly at capacity");

        vm.warp(block.timestamp + 30 days + 30 days);
        vm.prank(investor1);
        idoManager.processRefund(idoId, true);

        (uint256 totalRefunded, uint256 refundedBonus,,,) = idoManager.idoRefundInfo(idoId);
        emit log_named_uint("totalRefunded (base)", totalRefunded);
        emit log_named_uint("refundedBonus", refundedBonus);
        assertTrue(totalRefunded > 0, "refund must have freed capacity");

        (,, IIDOManager.IDOInfo memory infoAfter,) = idoManager.idos(idoId);
        assertEq(infoAfter.totalAllocated, infoBefore.totalAllocated, "totalAllocated unchanged after refund");
        emit log_named_uint("totalAllocated after refund (unchanged)", infoAfter.totalAllocated);

        uint256 effectiveAllocation = infoAfter.totalAllocated - totalRefunded - refundedBonus;
        emit log_named_uint("effective allocation (refund-adjusted)", effectiveAllocation);
        assertLt(effectiveAllocation, infoBefore.totalAllocation, "effective allocation below cap - room exists");

        uint256 newInvestAmount = 100e6;
        usdt.mint(newInvestor, newInvestAmount);
        vm.startPrank(newInvestor);
        usdt.approve(address(idoManager), newInvestAmount);
        idoManager.invest(idoId, newInvestAmount, address(usdt), KYC_EXPIRES, KYC_SIG);
        vm.stopPrank();

        (, uint256 newInvestorAllocated, , , ) = idoManager.getUserInfo(idoId, newInvestor);
        assertEq(newInvestorAllocated, 100e18, "new investor should be able to use refunded capacity");
        emit log_named_uint("capacity reused (tokens)", totalRefunded + refundedBonus);
    }

    function test_setCriticalSetters_RevertAfterIdoStart() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createBasicIDO(startTime, uint64(startTime + 30 days));

        vm.warp(startTime);

        vm.prank(admin);
        vm.expectRevert(IDOAlreadyStarted.selector);
        idoManager.setTgeTime(idoId, startTime + 1 days);
    }

    function test_setCriticalSetters_RevertAfterFirstInvestor() public {
        uint64 startTime = uint64(block.timestamp + 1 days);
        uint256 idoId = _createBasicIDO(startTime, uint64(startTime + 30 days));

        _mintAndApprove(user, address(usdt), 100e6);
        vm.warp(startTime);
        vm.prank(user);
        idoManager.invest(idoId, 100e6, address(usdt), KYC_EXPIRES, KYC_SIG);

        vm.prank(admin);
        vm.expectRevert(IDOAlreadyHasInvestors.selector);
        idoManager.setClaimStartTime(idoId, startTime + 2 days);
    }

    function test_setAdminManager_Reverts_ZeroAddress() public {
        vm.expectRevert(InvalidZeroAddress.selector);
        idoManager.setAdminManager(address(0));
    }
    function test_setKYCVerifier_Reverts_ZeroAddress() public {
        vm.expectRevert(InvalidZeroAddress.selector);
        idoManager.setKYCVerifier(address(0));
    }
    function test_adminManagerConstructor_RevertsZeroInitialAdmin() public {
        vm.expectRevert(InvalidZeroAddress.selector);
        new AdminManager(owner, address(0), owner);
    }
    function test_adminManagerConstructor_RevertsZeroInitialSuperAdmin() public {
        vm.expectRevert(InvalidZeroAddress.selector);
        new AdminManager(owner, admin, address(0));
    }
}

