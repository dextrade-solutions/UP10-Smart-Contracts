// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {AdminManager} from "../../src/admin_manager/AdminManager.sol";
import {WithAdminManager} from "../../src/admin_manager/WithAdminManager.sol";
import {ReservesManager} from "../../src/ReservesManager.sol";
import "../../src/Errors.sol";

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

contract ReservesManagerHarness is ReservesManager {
    constructor(ReservesManager.TokenConfig[] memory tokens, address adminManager)
        WithAdminManager(adminManager)
        ReservesManager(tokens)
    {}
}

contract ReservesManagerTest is Test {
    AdminManager internal adminManager;
    ReservesManagerHarness internal reserves;

    MockERC20 internal usdt;
    MockERC20 internal usdc;
    MockERC20 internal flx;
    MockERC20 internal other;

    address internal owner = address(this);
    address internal admin = makeAddr("admin");
    address internal nonAdmin = makeAddr("nonAdmin");
    address payable internal superAdmin = payable(makeAddr("superAdmin"));

    function setUp() public {
        adminManager = new AdminManager(owner, admin, superAdmin);

        usdt = new MockERC20("USDT", "USDT", 6);
        usdc = new MockERC20("USDC", "USDC", 6);
        flx = new MockERC20("FLX", "FLX", 18);
        other = new MockERC20("OTHER", "OTH", 18);

        ReservesManager.TokenConfig[] memory tokens = new ReservesManager.TokenConfig[](3);
        tokens[0] = ReservesManager.TokenConfig({token: address(usdt), price: 1e8});
        tokens[1] = ReservesManager.TokenConfig({token: address(usdc), price: 2e8});
        tokens[2] = ReservesManager.TokenConfig({token: address(flx), price: 3e8});

        reserves = new ReservesManagerHarness(tokens, address(adminManager));
    }

    function test_constructor_SetsSupportedTokensAndPrices() public view {
        assertTrue(reserves.isTokenSupported(address(usdt)));
        assertTrue(reserves.isTokenSupported(address(usdc)));
        assertTrue(reserves.isTokenSupported(address(flx)));
        assertFalse(reserves.isTokenSupported(address(other)));

        assertEq(reserves.getStaticPrice(address(usdt)), 1e8);
        assertEq(reserves.getStaticPrice(address(usdc)), 2e8);
        assertEq(reserves.getStaticPrice(address(flx)), 3e8);
        assertEq(reserves.getStaticPrice(address(other)), 0);
    }

    function test_constructor_RevertsZeroTokenAddress() public {
        ReservesManager.TokenConfig[] memory tokens = new ReservesManager.TokenConfig[](1);
        tokens[0] = ReservesManager.TokenConfig({token: address(0), price: 1e8});

        vm.expectRevert(ZeroAddress.selector);
        new ReservesManagerHarness(tokens, address(adminManager));
    }

    function test_constructor_RevertsDuplicateToken() public {
        ReservesManager.TokenConfig[] memory tokens = new ReservesManager.TokenConfig[](2);
        tokens[0] = ReservesManager.TokenConfig({token: address(usdt), price: 1e8});
        tokens[1] = ReservesManager.TokenConfig({token: address(usdt), price: 1e8});

        vm.expectRevert(DuplicateToken.selector);
        new ReservesManagerHarness(tokens, address(adminManager));
    }

    function test_getSupportedTokensWithPrices_ReturnsConfiguredList() public view {
        ReservesManager.TokenConfig[] memory list = reserves.getSupportedTokensWithPrices();
        assertEq(list.length, 3);

        assertEq(list[0].token, address(usdt));
        assertEq(list[0].price, 1e8);

        assertEq(list[1].token, address(usdc));
        assertEq(list[1].price, 2e8);

        assertEq(list[2].token, address(flx));
        assertEq(list[2].price, 3e8);
    }

    function test_setStaticPrice_RevertsForNonAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(CallerNotAdmin.selector);
        reserves.setStaticPrice(address(usdt), 9e8);
    }

    function test_setStaticPrice_RevertsForUnsupportedToken() public {
        vm.prank(admin);
        vm.expectRevert(InvalidToken.selector);
        reserves.setStaticPrice(address(other), 9e8);
    }

    function test_setStaticPrice_SetsPrice() public {
        vm.prank(admin);
        reserves.setStaticPrice(address(usdt), 9e8);
        assertEq(reserves.getStaticPrice(address(usdt)), 9e8);
    }

    function test_emergencyWithdraw_RevertsNonSuperAdmin() public {
        vm.prank(nonAdmin);
        vm.expectRevert(CallerNotSuperAdmin.selector);
        reserves.emergencyWithdraw(address(usdt), 1);
    }

    function test_emergencyWithdraw_RevertsZeroAmount() public {
        vm.prank(superAdmin);
        vm.expectRevert(InvalidAmount.selector);
        reserves.emergencyWithdraw(address(usdt), 0);
    }

    function test_emergencyWithdraw_ERC20_Success() public {
        uint256 amount = 123e6;
        usdt.mint(address(reserves), amount);

        uint256 ownerBefore = usdt.balanceOf(superAdmin);
        uint256 reservesBefore = usdt.balanceOf(address(reserves));

        vm.prank(superAdmin);
        reserves.emergencyWithdraw(address(usdt), amount);

        assertEq(usdt.balanceOf(superAdmin), ownerBefore + amount);
        assertEq(usdt.balanceOf(address(reserves)), reservesBefore - amount);
    }

    function test_emergencyWithdraw_ETH_Success() public {
        vm.deal(address(reserves), 1 ether);

        uint256 ownerBefore = superAdmin.balance;
        uint256 reservesBefore = address(reserves).balance;

        uint256 amount = 0.4 ether;
        vm.prank(superAdmin);
        reserves.emergencyWithdraw(address(0), amount);

        assertEq(superAdmin.balance, ownerBefore + amount);
        assertEq(address(reserves).balance, reservesBefore - amount);
    }
}

