// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../../interfaces/IronBankInterface.sol";

contract CreditLimitManager is Ownable2Step {
    address private immutable _pool;

    address private _guardian;

    event GuardianSet(address guardian);

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

    struct CreditLimit {
        address market;
        uint256 creditLimit;
    }

    function getUserCreditLimits(address user) public view returns (CreditLimit[] memory) {
        address[] memory markets = IronBankInterface(_pool).getUserCreditMarkets(user);
        CreditLimit[] memory creditLimits = new CreditLimit[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            creditLimits[i] = CreditLimit({
                market: markets[i],
                creditLimit: IronBankInterface(_pool).getCreditLimit(user, markets[i])
            });
        }
        return creditLimits;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setGuardian(address guardian) external onlyOwner {
        _guardian = guardian;

        emit GuardianSet(guardian);
    }

    function setCreditLimit(address user, address market, uint256 creditLimit) external onlyOwner {
        IronBankInterface(_pool).setCreditLimit(user, market, creditLimit);
    }

    function pauseCreditLimit(address user, address market) external onlyOwnerOrGuardian {
        require(IronBankInterface(_pool).isCreditAccount(user), "cannot pause non-credit account");

        // Set the credit limit to a very small amount (1 Wei) to avoid the user becoming liquidatable.
        IronBankInterface(_pool).setCreditLimit(user, market, 1);
    }
}
