// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract PTokenTest is Test, Common {
    uint8 internal constant decimals1 = 18;
    uint8 internal constant decimals2 = 6;

    address admin = address(64);
    address user = address(128);

    ERC20Market market1;
    ERC20Market market2;

    PToken pToken1;
    PToken pToken2;

    function setUp() public {
        market1 = new ERC20Market("Token", "TOKEN", decimals1, admin);
        market2 = new ERC20Market("Token", "TOKEN", decimals2, admin);

        pToken1 = createPToken(admin, address(market1));
        pToken2 = createPToken(admin, address(market2));

        deal(address(market1), user, 10_000 * (10 ** decimals1));
        deal(address(market2), user, 10_000 * (10 ** decimals2));
    }

    function testDecimals() public {
        assertEq(pToken1.decimals(), decimals1);
        assertEq(pToken2.decimals(), decimals2);
    }

    function testUnderlying() public {
        assertEq(pToken1.getUnderlying(), address(market1));
        assertEq(pToken2.getUnderlying(), address(market2));
    }

    function testWrap() public {
        assertEq(pToken1.balanceOf(user), 0);
        assertEq(market1.balanceOf(user), 10_000 * (10 ** decimals1));

        vm.startPrank(user);
        market1.approve(address(pToken1), 10_000 * (10 ** decimals1));
        pToken1.wrap(10_000 * (10 ** decimals1));
        vm.stopPrank();

        assertEq(pToken1.balanceOf(user), 10_000 * (10 ** decimals1));
        assertEq(market1.balanceOf(user), 0);
    }

    function testUnwrap() public {
        vm.startPrank(user);
        market1.approve(address(pToken1), 10_000 * (10 ** decimals1));
        pToken1.wrap(10_000 * (10 ** decimals1));

        assertEq(pToken1.balanceOf(user), 10_000 * (10 ** decimals1));
        assertEq(market1.balanceOf(user), 0);

        pToken1.unwrap(10_000 * (10 ** decimals1));
        vm.stopPrank();

        assertEq(pToken1.balanceOf(user), 0);
        assertEq(market1.balanceOf(user), 10_000 * (10 ** decimals1));
    }

    function testAbsorb() public {
        assertEq(pToken1.balanceOf(user), 0);
        assertEq(market1.balanceOf(user), 10_000 * (10 ** decimals1));

        vm.startPrank(user);
        market1.transfer(address(pToken1), 10_000 * (10 ** decimals1));
        pToken1.absorb(user);
        vm.stopPrank();

        assertEq(pToken1.balanceOf(user), 10_000 * (10 ** decimals1));
        assertEq(market1.balanceOf(user), 0);
    }

    function testSeize() public {
        vm.startPrank(admin);
        market2.transfer(address(pToken1), 10_000 * (10 ** decimals2));

        assertEq(market2.balanceOf(address(pToken1)), 10_000 * (10 ** decimals2));

        pToken1.seize(address(market2));

        assertEq(market2.balanceOf(address(pToken1)), 0);
        vm.stopPrank();
    }

    function testCannotSeizeForNotOwner() public {
        vm.prank(admin);
        market2.transfer(address(pToken1), 10_000 * (10 ** decimals2));

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        pToken1.seize(address(market2));

        assertEq(market2.balanceOf(address(pToken1)), 10_000 * (10 ** decimals2));
    }

    function testCannotSeizeUnderlying() public {
        vm.prank(admin);
        vm.expectRevert("cannot seize underlying");
        pToken1.seize(address(market1));
    }
}
