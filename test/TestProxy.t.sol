// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/protocol/pool/IronBank.sol";
import "../src/protocol/pool/IronBankProxy.sol";

contract MockIronBank is IronBank {
    function mockTest() public pure returns (uint256) {
        return 123;
    }
}

contract ProxyTest is Test {
    IronBankProxy ib;

    address alice = address(64);
    address bob = address(128);

    function setUp() public {
        IronBank impl = new IronBank();
        ib = new IronBankProxy(address(impl), abi.encodeWithSignature("initialize(address)", alice));
    }

    function testCannotInitializeAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        IronBank(address(ib)).initialize(bob);
    }

    function testCannotChangeImplementationForNotAdmin() public {
        IronBank newImpl = new IronBank();
        vm.prank(bob);
        vm.expectRevert("Ownable: caller is not the owner");
        IronBank(address(ib)).upgradeTo(address(newImpl));
    }

    function testChangeImplementation() public {
        IronBank newImpl = new MockIronBank();
        IronBank(address(ib)).upgradeTo(address(newImpl));
        assertEq(MockIronBank(address(ib)).mockTest(), 123);
    }
}
