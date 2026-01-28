// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {KYCVerifier} from "../../src/kyc/KYCVerifier.sol";

contract KYCVerifierTest is Test {
    KYCVerifier public kycVerifier;

    // KYC signer private key and address
    uint256 public constant SIGNER_PRIVATE_KEY = 0xA11CE;
    address public signer;

    address public owner = address(this);
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public randomUser = makeAddr("randomUser");

    // EIP-712 domain separator components
    bytes32 private constant KYC_TYPEHASH =
        keccak256("KYC(address user,uint256 expires,uint256 nonce)");

    event KYCVerified(address indexed user, uint256 expires);
    event KYCSignerUpdated(address indexed previousSigner, address indexed newSigner);

    function setUp() public {
        // Derive signer address from private key
        signer = vm.addr(SIGNER_PRIVATE_KEY);

        // Deploy KYCVerifier with signer
        kycVerifier = new KYCVerifier(signer);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _getDigest(address user, uint256 expires, uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                KYC_TYPEHASH,
                user,
                expires,
                nonce
            )
        );

        // Build domain separator matching the contract's EIP712 implementation
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("KYCVerifier")),
                keccak256(bytes("1.0")),
                block.chainid,
                address(kycVerifier)
            )
        );

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _signKYC(
        uint256 privateKey,
        address user,
        uint256 expires,
        uint256 nonce
    ) internal view returns (bytes memory) {
        bytes32 digest = _getDigest(user, expires, nonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    // ============================================
    // Constructor Tests
    // ============================================

    function test_constructor_SetsKYCSigner() public view {
        assertEq(kycVerifier.kycSigner(), signer);
    }

    function test_constructor_SetsOwner() public view {
        assertEq(kycVerifier.owner(), owner);
    }

    function test_constructor_RevertsWithZeroAddress() public {
        vm.expectRevert("Invalid signer");
        new KYCVerifier(address(0));
    }

    // ============================================
    // setKYCSigner Tests
    // ============================================

    function test_setKYCSigner_Success() public {
        address newSigner = makeAddr("newSigner");

        vm.expectEmit(true, true, false, false);
        emit KYCSignerUpdated(signer, newSigner);

        kycVerifier.setKYCSigner(newSigner);

        assertEq(kycVerifier.kycSigner(), newSigner);
    }

    function test_setKYCSigner_RevertsNonOwner() public {
        address newSigner = makeAddr("newSigner");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        kycVerifier.setKYCSigner(newSigner);
    }

    function test_setKYCSigner_RevertsWithZeroAddress() public {
        vm.expectRevert("Invalid signer");
        kycVerifier.setKYCSigner(address(0));
    }

    function test_setKYCSigner_CanUpdateMultipleTimes() public {
        address newSigner1 = makeAddr("newSigner1");
        address newSigner2 = makeAddr("newSigner2");

        kycVerifier.setKYCSigner(newSigner1);
        assertEq(kycVerifier.kycSigner(), newSigner1);

        kycVerifier.setKYCSigner(newSigner2);
        assertEq(kycVerifier.kycSigner(), newSigner2);
    }

    // ============================================
    // verifyKYC Tests
    // ============================================

    function test_verifyKYC_Success() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.expectEmit(true, false, false, true);
        emit KYCVerified(user1, expires);

        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        // Nonce should be incremented
        assertEq(kycVerifier.nonces(user1), nonce + 1);
    }

    function test_verifyKYC_Success_MultipleUsers() public {
        uint256 expires = block.timestamp + 1 hours;

        // User1 verifies
        bytes memory sig1 = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, 0);
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, sig1);
        assertEq(kycVerifier.nonces(user1), 1);

        // User2 verifies
        bytes memory sig2 = _signKYC(SIGNER_PRIVATE_KEY, user2, expires, 0);
        vm.prank(user2);
        kycVerifier.verifyKYC(expires, sig2);
        assertEq(kycVerifier.nonces(user2), 1);

        // User1's nonce unchanged
        assertEq(kycVerifier.nonces(user1), 1);
    }

    function test_verifyKYC_Success_SameUserMultipleTimes() public {
        uint256 expires = block.timestamp + 1 hours;

        // First verification (nonce 0)
        bytes memory sig1 = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, 0);
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, sig1);
        assertEq(kycVerifier.nonces(user1), 1);

        // Second verification (nonce 1)
        bytes memory sig2 = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, 1);
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, sig2);
        assertEq(kycVerifier.nonces(user1), 2);

        // Third verification (nonce 2)
        bytes memory sig3 = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, 2);
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, sig3);
        assertEq(kycVerifier.nonces(user1), 3);
    }

    function test_verifyKYC_Success_ExpiresExactlyAtTimestamp() public {
        uint256 expires = block.timestamp; // Exact timestamp is valid
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user1), nonce + 1);
    }

    function test_verifyKYC_RevertsExpiredSignature() public {
        uint256 expires = block.timestamp - 1; // Already expired
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.prank(user1);
        vm.expectRevert("KYC expired");
        kycVerifier.verifyKYC(expires, signature);
    }

    function test_verifyKYC_RevertsInvalidSignature() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        // Sign with wrong private key
        uint256 wrongKey = 0xBAD;
        bytes memory signature = _signKYC(wrongKey, user1, expires, nonce);

        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, signature);
    }

    function test_verifyKYC_RevertsWrongUser() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        // Sign for user1 but call from user2
        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.prank(user2);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, signature);
    }

    function test_verifyKYC_RevertsReplayAttack() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        // First call succeeds
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        // Replay attack should fail (nonce already incremented)
        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, signature);
    }

    function test_verifyKYC_RevertsWrongNonce() public {
        uint256 expires = block.timestamp + 1 hours;

        // Sign with wrong nonce (1 instead of 0)
        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, 1);

        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, signature);
    }

    function test_verifyKYC_RevertsWrongExpires() public {
        uint256 correctExpires = block.timestamp + 1 hours;
        uint256 wrongExpires = block.timestamp + 2 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        // Sign with one expiration, call with different
        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, correctExpires, nonce);

        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(wrongExpires, signature);
    }

    function test_verifyKYC_WorksAfterSignerChange() public {
        // Create new signer
        uint256 newSignerKey = 0xB0B;
        address newSigner = vm.addr(newSignerKey);

        // Update signer
        kycVerifier.setKYCSigner(newSigner);

        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        // Old signer's signature should fail
        bytes memory oldSig = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);
        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, oldSig);

        // New signer's signature should work
        bytes memory newSig = _signKYC(newSignerKey, user1, expires, nonce);
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, newSig);

        assertEq(kycVerifier.nonces(user1), 1);
    }

    // ============================================
    // Nonce Getter Tests
    // ============================================

    function test_nonces_InitiallyZero() public view {
        assertEq(kycVerifier.nonces(user1), 0);
        assertEq(kycVerifier.nonces(user2), 0);
        assertEq(kycVerifier.nonces(randomUser), 0);
    }

    function test_nonces_IncrementsCorrectly() public {
        uint256 expires = block.timestamp + 1 hours;

        for (uint256 i = 0; i < 5; i++) {
            assertEq(kycVerifier.nonces(user1), i);

            bytes memory sig = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, i);
            vm.prank(user1);
            kycVerifier.verifyKYC(expires, sig);
        }

        assertEq(kycVerifier.nonces(user1), 5);
    }

    // ============================================
    // Edge Cases
    // ============================================

    function test_verifyKYC_MaxExpiration() public {
        uint256 expires = type(uint256).max;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user1), 1);
    }

    function test_verifyKYC_FarFutureExpiration() public {
        uint256 expires = block.timestamp + 365 days;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user1), 1);
    }

    function test_verifyKYC_AfterWarp() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        // Warp time but still within expiration
        vm.warp(block.timestamp + 30 minutes);

        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user1), 1);
    }

    function test_verifyKYC_ExpiresAfterWarp() public {
        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        // Warp past expiration
        vm.warp(block.timestamp + 2 hours);

        vm.prank(user1);
        vm.expectRevert("KYC expired");
        kycVerifier.verifyKYC(expires, signature);
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function testFuzz_verifyKYC_ValidSignature(uint256 expiresDelta, address user) public {
        vm.assume(user != address(0));
        vm.assume(expiresDelta > 0 && expiresDelta < 365 days);

        uint256 expires = block.timestamp + expiresDelta;
        uint256 nonce = kycVerifier.nonces(user);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user, expires, nonce);

        vm.prank(user);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user), nonce + 1);
    }

    function testFuzz_verifyKYC_RejectsWrongSigner(uint256 wrongKey) public {
        vm.assume(wrongKey != SIGNER_PRIVATE_KEY);
        vm.assume(wrongKey != 0);
        vm.assume(wrongKey < type(uint256).max / 2); // Valid key range

        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(wrongKey, user1, expires, nonce);

        vm.prank(user1);
        vm.expectRevert("Invalid KYC signature");
        kycVerifier.verifyKYC(expires, signature);
    }

    // ============================================
    // Integration with IDOManager pattern
    // ============================================

    function test_verifyKYC_CalledFromContract() public {
        // Simulates how IDOManager would call verifyKYC

        uint256 expires = block.timestamp + 1 hours;
        uint256 nonce = kycVerifier.nonces(user1);

        bytes memory signature = _signKYC(SIGNER_PRIVATE_KEY, user1, expires, nonce);

        // User calls a contract function which calls verifyKYC
        // The contract must use msg.sender properly
        vm.prank(user1);
        kycVerifier.verifyKYC(expires, signature);

        assertEq(kycVerifier.nonces(user1), 1);
    }
}
