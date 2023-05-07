// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/access/Ownable2Step.sol";
import "../../interfaces/IronBankInterface.sol";

contract CreditLimitManager is Ownable2Step {
    /// @notice The Iron Bank contract
    IronBankInterface public immutable ironBank;

    /// @notice The address of the guardian
    address public guardian;

    event GuardianSet(address guardian);

    constructor(address ironBank_) {
        ironBank = IronBankInterface(ironBank_);
    }

    /**
     * @notice Check if the caller is the owner or the guardian.
     */
    modifier onlyOwnerOrGuardian() {
        require(msg.sender == owner() || msg.sender == guardian, "!authorized");
        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    struct CreditLimit {
        address market;
        uint256 creditLimit;
    }

    /**
     * @notice Get the credit limits of a user.
     * @param user The address of the user
     * @return The credit limits of the user
     */
    function getUserCreditLimits(address user) public view returns (CreditLimit[] memory) {
        address[] memory markets = IronBankInterface(ironBank).getUserCreditMarkets(user);
        CreditLimit[] memory creditLimits = new CreditLimit[](markets.length);
        for (uint256 i = 0; i < markets.length; i++) {
            creditLimits[i] = CreditLimit({
                market: markets[i],
                creditLimit: IronBankInterface(ironBank).getCreditLimit(user, markets[i])
            });
        }
        return creditLimits;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    /**
     * @notice Set the guardian of market configurator.
     * @param _guardian The address of the guardian
     */
    function setGuardian(address _guardian) external onlyOwner {
        guardian = _guardian;

        emit GuardianSet(guardian);
    }

    /**
     * @notice Set the credit limit of a user.
     * @param user The address of the user
     * @param market The address of the market
     * @param creditLimit The credit limit
     */
    function setCreditLimit(address user, address market, uint256 creditLimit) external onlyOwner {
        IronBankInterface(ironBank).setCreditLimit(user, market, creditLimit);
    }

    /**
     * @notice Pause the credit limit of a user.
     * @param user The address of the user
     * @param market The address of the market
     */
    function pauseCreditLimit(address user, address market) external onlyOwnerOrGuardian {
        require(IronBankInterface(ironBank).isCreditAccount(user), "cannot pause non-credit account");

        // Set the credit limit to a very small amount (1 Wei) to avoid the user becoming liquidatable.
        IronBankInterface(ironBank).setCreditLimit(user, market, 1);
    }
}
