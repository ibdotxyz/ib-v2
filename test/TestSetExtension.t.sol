// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./Common.t.sol";

contract SetExtensionTest is Test, Common {
    IronBank ib;

    address admin = address(64);
    address user1 = address(128);
    address extension1 = address(256);
    address extension2 = address(512);

    function setUp() public {
        ib = createIronBank(admin);
    }

    function testSetUserExtension() public {
        vm.startPrank(user1);

        vm.expectEmit(true, true, false, true, address(ib));
        emit ExtensionAdded(user1, extension1);

        ib.setUserExtension(extension1, true);
        assertTrue(ib.isAllowedExtension(user1, extension1));
        address[] memory extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 1);
        assertEq(extensions[0], extension1);

        vm.expectEmit(true, true, false, true, address(ib));
        emit ExtensionAdded(user1, extension2);

        ib.setUserExtension(extension2, true);
        assertTrue(ib.isAllowedExtension(user1, extension2));
        extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 2);
        assertEq(extensions[0], extension1);
        assertEq(extensions[1], extension2);

        ib.setUserExtension(extension1, true); // duplicate
        assertTrue(ib.isAllowedExtension(user1, extension1));
        extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 2);
        assertEq(extensions[0], extension1);
        assertEq(extensions[1], extension2);

        vm.expectEmit(true, true, false, true, address(ib));
        emit ExtensionRemoved(user1, extension1);

        ib.setUserExtension(extension1, false);
        assertFalse(ib.isAllowedExtension(user1, extension1));
        extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 1);
        assertEq(extensions[0], extension2);

        vm.expectEmit(true, true, false, true, address(ib));
        emit ExtensionRemoved(user1, extension2);

        ib.setUserExtension(extension2, false);
        assertFalse(ib.isAllowedExtension(user1, extension2));
        extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 0);

        ib.setUserExtension(extension2, false); // duplicate
        assertFalse(ib.isAllowedExtension(user1, extension2));
        extensions = ib.getUserAllowedExtensions(user1);
        assertEq(extensions.length, 0);

        vm.stopPrank();
    }
}
