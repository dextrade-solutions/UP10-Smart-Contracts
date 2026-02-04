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
}

