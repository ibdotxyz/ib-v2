// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract IRMTest is Test, Common {
    uint256 internal constant baseRatePerSecond = 0.0001e18;
    uint256 internal constant borrowPerSecond1 = 0.002e18;
    uint256 internal constant kink1 = 0.8e18;
    uint256 internal constant borrowPerSecond2 = 0.004e18;
    uint256 internal constant kink2 = 0.9e18;
    uint256 internal constant borrowPerSecond3 = 0.006e18;

    TripleSlopeRateModel irm;

    function setUp() public {
        irm = createIRM(baseRatePerSecond, borrowPerSecond1, kink1, borrowPerSecond2, kink2, borrowPerSecond3);
    }

    function testZeroUtilization() public {
        uint256 cash = 100e18;
        uint256 borrow = 0;
        uint256 util = 0;
        uint256 borrowRate = 0.0001e18; // baseRatePerSecond
        uint256 supplyRate = 0;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testUtilizationBelowKink1() public {
        uint256 cash = 90e18;
        uint256 borrow = 10e18;
        uint256 util = 0.1e18;
        uint256 borrowRate = 0.0003e18; // 0.0001 + 0.002*0.1
        uint256 supplyRate = 0.00003e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testUtilizationEqualKink1() public {
        uint256 cash = 20e18;
        uint256 borrow = 80e18;
        uint256 util = 0.8e18;
        uint256 borrowRate = 0.0017e18; // 0.0001 + 0.002*0.8
        uint256 supplyRate = 0.00136e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testUtilizationBetweenKink1AndKink2() public {
        uint256 cash = 15e18;
        uint256 borrow = 85e18;
        uint256 util = 0.85e18;
        uint256 borrowRate = 0.0019e18; // 0.0001 + 0.002*0.8 + 0.004*0.05
        uint256 supplyRate = 0.001615e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testUtilizationEqualKink2() public {
        uint256 cash = 10e18;
        uint256 borrow = 90e18;
        uint256 util = 0.9e18;
        uint256 borrowRate = 0.0021e18; // 0.0001 + 0.002*0.8 + 0.004*0.1
        uint256 supplyRate = 0.00189e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testUtilizationAboveKink2() public {
        uint256 cash = 5e18;
        uint256 borrow = 95e18;
        uint256 util = 0.95e18;
        uint256 borrowRate = 0.0024e18; // 0.0001 + 0.002*0.8 + 0.004*0.1 + 0.006*0.05
        uint256 supplyRate = 0.00228e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }

    function testMaxUtilization() public {
        uint256 cash = 0;
        uint256 borrow = 100e18;
        uint256 util = 1e18;
        uint256 borrowRate = 0.0027e18; // 0.0001 + 0.002*0.8 + 0.004*0.1 + 0.006*0.1
        uint256 supplyRate = 0.0027e18;

        assertEq(irm.getUtilization(cash, borrow), util);
        assertEq(irm.getBorrowRate(cash, borrow), borrowRate);
        assertEq(irm.getSupplyRate(cash, borrow), supplyRate);
    }
}
