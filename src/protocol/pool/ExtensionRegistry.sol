// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../../interfaces/ExtensionRegistryInterface.sol";
import "../../interfaces/IronBankInterface.sol";
import "../../libraries/Arrays.sol";

contract ExtensionRegistry is Ownable2Step, ExtensionRegistryInterface {
    using Arrays for address[];

    address private immutable _pool;

    address private _guardian;

    mapping(address => bool) private _globalExtensions;

    address[] private _allGlobalExtensions;

    mapping(address => mapping(address => bool)) private _userExtensions;

    mapping(address => address[]) private _allUserExtensions;

    event GuardianSet(address guardian);

    event UserExtensionSet(address indexed user, address indexed extension, bool indexed activated);

    event GlobalExtensionAdded(address extension);

    event GlobalExtensionRemoved(address extension);

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

    function getUserExtensions(address user) public view returns (address[] memory) {
        return _allUserExtensions[user];
    }

    function isUserExtension(address user, address extension) public view returns (bool) {
        return _userExtensions[user][extension];
    }

    function getGlobalExtensions() public view returns (address[] memory) {
        return _allGlobalExtensions;
    }

    function isGlobalExtension(address extension) public view returns (bool) {
        return _globalExtensions[extension];
    }

    function isAuthorized(address user, address extension) external view returns (bool) {
        return isGlobalExtension(extension) || isUserExtension(user, extension);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    struct UserExtension {
        address extension;
        bool activated;
    }

    function setUserExtensions(UserExtension[] memory userExtensions) external {
        uint256 length = userExtensions.length;
        for (uint256 i = 0; i < length;) {
            address extension = userExtensions[i].extension;
            bool activated = userExtensions[i].activated;
            if (activated && !_userExtensions[msg.sender][extension]) {
                _userExtensions[msg.sender][extension] = true;
                _allUserExtensions[msg.sender].push(extension);

                emit UserExtensionSet(msg.sender, extension, activated);
            } else if (!activated && _userExtensions[msg.sender][extension]) {
                _userExtensions[msg.sender][extension] = false;
                _allUserExtensions[msg.sender].deleteElement(extension);

                emit UserExtensionSet(msg.sender, extension, activated);
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

    function addGlobalExtensions(address[] memory extensions) external onlyOwner {
        for (uint256 i = 0; i < extensions.length;) {
            if (!_globalExtensions[extensions[i]]) {
                _globalExtensions[extensions[i]] = true;
                _allGlobalExtensions.push(extensions[i]);

                emit GlobalExtensionAdded(extensions[i]);
            }

            unchecked {
                i++;
            }
        }
    }

    function removeGlobalExtensions(address[] memory extensions) external onlyOwnerOrGuardian {
        for (uint256 i = 0; i < extensions.length;) {
            if (_globalExtensions[extensions[i]]) {
                _globalExtensions[extensions[i]] = false;
                _allGlobalExtensions.deleteElement(extensions[i]);

                emit GlobalExtensionRemoved(extensions[i]);
            }

            unchecked {
                i++;
            }
        }
    }
}
