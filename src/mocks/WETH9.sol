// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2015, 2016, 2017 Dapphub

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;

    event Deposit(address indexed dst, uint wad);
    event Withdrawal(address indexed src, uint wad);

    // ERC20
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint);
    function balanceOf(address guy) external view returns (uint);
    function allowance(address src, address dst) external view returns (uint);

    function approve(address spender, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);

    event Approval(address indexed src, address indexed dst, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);
}

contract WETH is IWETH {
    string public constant override name = "Wrapped Ether";
    string public constant override symbol = "WETH";
    uint8 public override decimals = 18;

    mapping (address => uint) public override balanceOf;
    mapping (address => mapping (address => uint)) public override allowance;

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(uint value) external override {
        balanceOf[msg.sender] -= value;
        (bool success, ) = msg.sender.call{value: value}("");
        if (!success) {
            revert ("WETH: withdraw failed");
        }
        emit Withdrawal(msg.sender, value);
    }

    function totalSupply() external view override returns (uint) {
        return address(this).balance;
    }

    function approve(address spender, uint value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint value) external override returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;

        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint value) external override returns (bool) {
        if (from != msg.sender) {
            uint _allowance = allowance[from][msg.sender];
            if (_allowance != type(uint).max) {
                allowance[from][msg.sender] -= value;
            }
        }

        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit Transfer(from, to, value);
        return true;
    }
}
