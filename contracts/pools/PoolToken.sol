// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/kip/KIP7Extended.sol";
import "../interface/IPoolToken.sol";

contract PoolToken is KIP7Extended, IPoolToken {
    function __PoolToken_init(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) internal initializer {
        __KIP7Extended_init(_name, _symbol, _decimals);
    }

    function __PoolToken_init(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _owner
    ) internal initializer {
        __KIP7Extended_init(_name, _symbol, _decimals, _owner);
    }

    function changeName(string memory name_) external onlyOwner {
        _name = name_;
    }

    function changeSymbol(string memory symbol_) external onlyOwner {
        _symbol = symbol_;
    }
}
