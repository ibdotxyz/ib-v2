// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../../interfaces/IronBankInterface.sol";
import "../../interfaces/UserHelperRegistryInterface.sol";
import "../../libraries/Arrays.sol";

contract UserHelperRegistry is Ownable2Step, UserHelperRegistryInterface {
    using Arrays for address[];

    address private immutable _pool;

    address private _guardian;

    mapping(address => bool) private _globalHelpers;

    address[] private _allGlobalHelpers;

    mapping(address => mapping(address => bool)) private _userHelpers;

    mapping(address => address[]) private _allUserHelpers;

    event GuardianSet(address guardian);

    event UserHelperSet(address indexed user, address indexed helper, bool indexed activated);

    event GlobalHelperAdded(address helper);

    event GlobalHelperRemoved(address helper);

    constructor(address pool_) {
        _pool = pool_;
    }

    modifier onlyOwnerOrGuardian() {
        require(msg.sender == owner() || msg.sender == _guardian, "unauthorized");
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function getPool() external view returns (address) {
        return _pool;
    }

    function getGuardian() external view returns (address) {
        return _guardian;
    }

    function getUserHelpers(address user) public view returns (address[] memory) {
        return _allUserHelpers[user];
    }

    function isUserHelper(address user, address helper) public view returns (bool) {
        return _userHelpers[user][helper];
    }

    function getGlobalHelpers() public view returns (address[] memory) {
        return _allGlobalHelpers;
    }

    function isGlobalHelper(address helper) public view returns (bool) {
        return _globalHelpers[helper];
    }

    function isHelperAuthorized(address user, address helper) external view returns (bool) {
        return isGlobalHelper(helper) || isUserHelper(user, helper);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct UserHelper {
        address helper;
        bool activated;
    }

    function setUserHelpers(UserHelper[] memory userHelpers) external {
        uint256 length = userHelpers.length;
        for (uint256 i = 0; i < length;) {
            address helper = userHelpers[i].helper;
            bool activated = userHelpers[i].activated;
            if (activated && !_userHelpers[msg.sender][helper]) {
                _userHelpers[msg.sender][helper] = true;
                _allUserHelpers[msg.sender].push(helper);

                emit UserHelperSet(msg.sender, helper, activated);
            } else if (!activated && _userHelpers[msg.sender][helper]) {
                _userHelpers[msg.sender][helper] = false;
                _allUserHelpers[msg.sender].deleteElement(helper);

                emit UserHelperSet(msg.sender, helper, activated);
            }

            unchecked {
                i++;
            }
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setGuardian(address guardian) external onlyOwner {
        _guardian = guardian;

        emit GuardianSet(guardian);
    }

    function addGlobalHelpers(address[] memory helpers) external onlyOwner {
        for (uint256 i = 0; i < helpers.length;) {
            if (!_globalHelpers[helpers[i]]) {
                _globalHelpers[helpers[i]] = true;
                _allGlobalHelpers.push(helpers[i]);

                emit GlobalHelperAdded(helpers[i]);
            }

            unchecked {
                i++;
            }
        }
    }

    function removeGlobalHelpers(address[] memory helpers) external onlyOwnerOrGuardian {
        for (uint256 i = 0; i < helpers.length;) {
            if (_globalHelpers[helpers[i]]) {
                _globalHelpers[helpers[i]] = false;
                _allGlobalHelpers.deleteElement(helpers[i]);

                emit GlobalHelperRemoved(helpers[i]);
            }

            unchecked {
                i++;
            }
        }
    }
}
