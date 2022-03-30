// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Oracle.sol";
import "../interface/claimswap/IClaimswapPair.sol";
import "../interface/claimswap/IClaimswapFactory.sol";
import "../library/WadRayMath.sol";

contract EYEOracle is Oracle {
    bytes32 public constant tokenType = "EYE";
    uint256 public lastUpdatedAt;
    uint256 public constant WINDOW_SIZE = 3 hours;
    uint256 public currentPrice;

    function __EYEOracle_init(address addressBook) public initializer {
        __Oracle_init(addressBook);
    }

    function getPrice() public view override returns (uint256, bool) {
        if (currentPrice <= 0) {
            return (price, valid);
        }
        return block.timestamp > lastUpdatedAt ? (currentPrice, valid) : (price, valid && price > 0);
    }

    function update() external override onlyOperator {
        price = currentPrice;

        address token = addressBook.getAddress(tokenType);
        address stableToken = addressBook.getAddress(bytes32("KSD"));
        IClaimswapFactory claimswap = IClaimswapFactory(addressBook.getAddress(bytes32("claimswapFactory")));
        address lp = claimswap.getPair(token, stableToken);

        address tokenA = IClaimswapPair(lp).token0();
        (uint112 poolA, uint112 poolB, ) = IClaimswapPair(lp).getReserves();

        uint256 price_ = 0;
        if (stableToken == tokenA) {
            price_ = (poolA * WadRayMath.WAD) / poolB;
        } else {
            price_ = (poolB * WadRayMath.WAD) / poolA;
        }

        uint256 diff = block.timestamp - lastUpdatedAt;
        lastUpdatedAt = block.timestamp;
        if (diff >= WINDOW_SIZE) {
            currentPrice = price_;
            valid = true;
        } else {
            currentPrice = (currentPrice * (WINDOW_SIZE - diff)) / WINDOW_SIZE + (price_ * diff) / WINDOW_SIZE;
            valid = true;
        }

        emit Update(price, block.timestamp);
    }
}
