// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "../library/WadRayMath.sol";
import "../library/openzeppelin/contracts/utils/Math.sol";
import "../interface/ITokenGateway.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IAddressBook.sol";
import "../interface/IOracle.sol";
import "../interface/ITreasury.sol";

abstract contract TokenGateway is Pausable, ITokenGateway {
    using WadRayMath for uint256;

    IAddressBook public addressBook;
    uint256 public override discountRatio; // 1WAD == 100%
    uint256 public vestingPeriod;

    uint256 public totalDepositedAmount;
    uint256 public totalCreatedAmount;
    uint256 public totalPurchasedValue;

    function __TokenGateway_init(address addressBook_) public initializer {
        __Pausable_init();
        addressBook = IAddressBook(addressBook_);
    }

    function config(bytes32 what, uint256 data) external onlyAdmin {
        if (what == "discountRatio") discountRatio = data;
        else if (what == "vestingPeriod") vestingPeriod = data;
        else revert("TokenGateway::config: unrecognized-param");
    }

    function tokenType() public pure virtual returns (bytes32);

    function deposit(uint256 tokenAmount) external override whenNotPaused returns (uint256 refundAmount) {
        if (tokenAmount <= 0) {
            return 0;
        }

        ITreasury treasury = ITreasury(addressBook.getAddress(tokenType(), bytes32("treasury")));
        uint256 bondAmount;
        uint256 amountToCreate;
        uint256 valueToCreate;
        {
            IOracle tokenOracle = IOracle(addressBook.getAddress(tokenType(), bytes32("oracle")));
            (uint256 tokenPrice, bool tokenPriceValid) = tokenOracle.getPrice();
            require(tokenPriceValid, "TokenGateway::deposit: invalid token price");
            require(tokenPrice > 0, "TokenGateway::deposit: token price should be gt 0");

            IOracle EYEOracle = IOracle(addressBook.getAddress(bytes32("EYE"), bytes32("oracle")));
            (uint256 EYEPrice, bool EYEPriceValid) = EYEOracle.getPrice();
            require(EYEPriceValid, "TokenGateway::deposit: invalid eye price");

            bondAmount = (tokenAmount * tokenPrice * WadRayMath.WAD) / (EYEPrice * (WadRayMath.WAD - discountRatio));
            amountToCreate = Math.min(bondAmount, treasury.creatableBondAmount());
            valueToCreate = amountToCreate.wadMul(EYEPrice);
        }
        treasury.createBond(msg.sender, amountToCreate, vestingPeriod);

        refundAmount = (tokenAmount * (bondAmount - amountToCreate)) / bondAmount;
        IKIP7 token = IKIP7(addressBook.getAddress(tokenType()));
        token.transferFrom(msg.sender, address(treasury), tokenAmount - refundAmount);

        totalDepositedAmount += tokenAmount - refundAmount;
        totalCreatedAmount += amountToCreate;
        totalPurchasedValue += valueToCreate;
        emit Deposit(msg.sender, tokenAmount, refundAmount, amountToCreate, valueToCreate, vestingPeriod);
    }
}
