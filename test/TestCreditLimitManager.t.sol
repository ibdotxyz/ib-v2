// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract CreditLimitManagerTest is Test, Common {
    uint16 internal constant reserveFactor = 1000; // 10%

    address admin = address(64);
    address user = address(128);

    IronBank ib;
    MarketConfigurator configurator;
    CreditLimitManager creditLimitManager;

    ERC20Market market1;
    ERC20Market market2;

    function setUp() public {
        ib = createIronBank(admin);

        configurator = createMarketConfigurator(admin, ib);

        vm.prank(admin);
        ib.setMarketConfigurator(address(configurator));

        creditLimitManager = createCreditLimitManager(admin, ib);

        vm.prank(admin);
        ib.setCreditLimitManager(address(creditLimitManager));

        TripleSlopeRateModel irm = createDefaultIRM();

        (market1,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
        (market2,,) = createAndListERC20Market(18, admin, ib, configurator, irm, reserveFactor);
    }

    function testSetGuardian() public {
        address guardian = address(256);

        vm.prank(admin);
        creditLimitManager.setGuardian(guardian);

        assertEq(creditLimitManager.guardian(), guardian);
    }

    function testCannotSetGuardianForNotOwner() public {
        address guardian = address(256);

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        creditLimitManager.setGuardian(guardian);
    }

    function testSetCreditLimit() public {
        // Set market1 credit.
        uint256 market1CreditLimit = 1000;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market1), market1CreditLimit);

        CreditLimitManager.CreditLimit[] memory creditLimits = creditLimitManager.getUserCreditLimits(user);
        assertEq(creditLimits.length, 1);
        assertEq(creditLimits[0].market, address(market1));
        assertEq(creditLimits[0].creditLimit, market1CreditLimit);

        assertEq(ib.getCreditLimit(user, address(market1)), market1CreditLimit);
        assertTrue(ib.isCreditAccount(user));

        address[] memory userCreditMarkets = ib.getUserCreditMarkets(user);
        assertEq(userCreditMarkets.length, 1);
        assertEq(userCreditMarkets[0], address(market1));

        // Set market2 credit.
        uint256 market2CreditLimit = 500;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market2), market2CreditLimit);

        creditLimits = creditLimitManager.getUserCreditLimits(user);
        assertEq(creditLimits.length, 2);
        assertEq(creditLimits[0].market, address(market1));
        assertEq(creditLimits[0].creditLimit, market1CreditLimit);
        assertEq(creditLimits[1].market, address(market2));
        assertEq(creditLimits[1].creditLimit, market2CreditLimit);

        assertEq(ib.getCreditLimit(user, address(market2)), market2CreditLimit);
        assertTrue(ib.isCreditAccount(user));

        userCreditMarkets = ib.getUserCreditMarkets(user);
        assertEq(userCreditMarkets.length, 2);
        assertEq(userCreditMarkets[0], address(market1));
        assertEq(userCreditMarkets[1], address(market2));

        // Clear market1 credit.
        market1CreditLimit = 0;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market1), market1CreditLimit);

        creditLimits = creditLimitManager.getUserCreditLimits(user);
        assertEq(creditLimits.length, 1);
        assertEq(creditLimits[0].market, address(market2));
        assertEq(creditLimits[0].creditLimit, market2CreditLimit);

        assertEq(ib.getCreditLimit(user, address(market1)), market1CreditLimit);
        assertTrue(ib.isCreditAccount(user));

        userCreditMarkets = ib.getUserCreditMarkets(user);
        assertEq(userCreditMarkets.length, 1);
        assertEq(userCreditMarkets[0], address(market2));

        // Clear market2 credit.
        market2CreditLimit = 0;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market2), market2CreditLimit);

        creditLimits = creditLimitManager.getUserCreditLimits(user);
        assertEq(creditLimits.length, 0);

        assertEq(ib.getCreditLimit(user, address(market2)), market2CreditLimit);
        assertFalse(ib.isCreditAccount(user));

        userCreditMarkets = ib.getUserCreditMarkets(user);
        assertEq(userCreditMarkets.length, 0);
    }

    function testCannotSetCreditLimitForNotOwner() public {
        uint256 market1CreditLimit = 1000;

        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        creditLimitManager.setCreditLimit(user, address(market1), market1CreditLimit);
    }

    function testPauseCreditLimit() public {
        uint256 market1CreditLimit = 1000;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market1), market1CreditLimit);

        uint256 market2CreditLimit = 500;

        vm.prank(admin);
        creditLimitManager.setCreditLimit(user, address(market2), market2CreditLimit);

        address guardian = address(256);

        vm.prank(admin);
        creditLimitManager.setGuardian(guardian);

        vm.prank(admin);
        creditLimitManager.pauseCreditLimit(user, address(market1));

        assertEq(ib.getCreditLimit(user, address(market1)), 1); // 1 wei

        vm.prank(guardian);
        creditLimitManager.pauseCreditLimit(user, address(market2));

        assertEq(ib.getCreditLimit(user, address(market2)), 1); // 1 wei
    }

    function testCannotPauseCreditLimitForNotOwner() public {
        vm.prank(user);
        vm.expectRevert("!authorized");
        creditLimitManager.pauseCreditLimit(user, address(market1));
    }

    function testCannotPauseCreditLimitForNonCreditAccount() public {
        vm.prank(admin);
        vm.expectRevert("cannot pause non-credit account");
        creditLimitManager.pauseCreditLimit(user, address(market1));
    }
}
