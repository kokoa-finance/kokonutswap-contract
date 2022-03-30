// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./Oracle.sol";
import "../interface/claimswap/IClaimswapPair.sol";
import "../library/kip/IKIP7Detailed.sol";

contract CSLPEYEKSDOracle is Oracle {
    bytes32 public constant tokenType = "CSLPEYEKSD";
    uint256 public lastUpdatedAt;
    uint256 public constant WINDOW_SIZE = 3 hours;
    uint256 public currentPrice;

    function __CSLPEYEKSDOracle_init(address addressBook) public initializer {
        __Oracle_init(addressBook);
    }

    function getPrice() public view override returns (uint256, bool) {
        if (currentPrice <= 0) {
            return (price, valid);
        }
        return block.timestamp > lastUpdatedAt ? (currentPrice, valid) : (price, valid && price > 0);
    }

    function update() external override whenNotPaused onlyOperator {
        price = currentPrice;

        address token = addressBook.getAddress(tokenType);
        address stableToken = addressBook.getAddress(bytes32("KSD"));
        address tokenA = IClaimswapPair(token).token0();
        address tokenB = IClaimswapPair(token).token1();
        (uint112 poolA, uint112 poolB, ) = IClaimswapPair(token).getReserves();
        uint256 totalSupply = IClaimswapPair(token).totalSupply();
        uint256 price_ = 0;
        if (stableToken == tokenA) {
            uint256 decimals = IKIP7Detailed(tokenA).decimals();
            uint256 targetDecimals = 36 - decimals;
            price_ = (2 * poolA * (10**targetDecimals)) / totalSupply;
        } else {
            uint256 decimals = IKIP7Detailed(tokenB).decimals();
            uint256 targetDecimals = 36 - decimals;
            price_ = (2 * poolB * (10**targetDecimals)) / totalSupply;
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
