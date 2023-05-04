// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../Common.t.sol";
import "../../src/libraries/Arrays.sol";

contract ArraysTest is Test, Common {
    using Arrays for address[];

    address[] myArray;

    function setUp() public {
        myArray = new address[](0);

        myArray.push(address(1));
        myArray.push(address(2));
        myArray.push(address(3));
    }

    function testDeleteElement() public {
        myArray.deleteElement(address(2));

        assertEq(myArray.length, 2);
        assertEq(myArray[0], address(1));
        assertEq(myArray[1], address(3));

        myArray.deleteElement(address(3));

        assertEq(myArray.length, 1);
        assertEq(myArray[0], address(1));

        myArray.deleteElement(address(1));

        assertEq(myArray.length, 0);

        myArray.deleteElement(address(100)); // nothing happens

        assertEq(myArray.length, 0);
    }

    function testDeleteElement2() public {
        myArray.deleteElement(address(1));

        assertEq(myArray.length, 2);
        assertEq(myArray[0], address(3));
        assertEq(myArray[1], address(2));

        myArray.deleteElement(address(1)); // nothing happens

        assertEq(myArray.length, 2);
        assertEq(myArray[0], address(3));
        assertEq(myArray[1], address(2));
    }
}
