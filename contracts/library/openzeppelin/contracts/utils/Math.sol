// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    function add(uint256 x, int256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x + uint256(y);
            require(y >= 0 || z <= x, "Math: addition overflow");
            require(y <= 0 || z >= x, "Math: addition overflow");
        }
    }

    function sub(uint256 x, int256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x - uint256(y);
            require(y <= 0 || z <= x, "Math: subtraction overflow");
            require(y >= 0 || z >= x, "Math: subtraction overflow");
        }
    }

    function mul(uint256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = int256(x) * y;
            require(int256(x) >= 0, "Math: multiplication overflow");
            require(y == 0 || z / y == int256(x), "Math: multiplication overflow");
        }
    }

    function mul(int256 x, uint256 y) internal pure returns (int256 z) {
        z = x * int256(y);
        require(int256(y) >= 0, "Math: multiplication overflow");
        require(x == 0 || z / x == int256(y), "Math: multiplication overflow");
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }

    // from uniswap
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        z = y;
        uint256 x = y / 2 + 1;
        while (x < z) {
            z = x;
            x = (y / x + x) / 2;
        }
    }
}
