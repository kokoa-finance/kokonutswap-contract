// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;
import "../openzeppelin/proxy/Initializable.sol";
import "./IKIP7Detailed.sol";
import "./KIP7.sol";

contract KIP7Detailed is KIP7, IKIP7Detailed {
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;

    bytes4 private constant INTERFACE_ID_KIP7_METADATA = 0xa219a025;

    function __KIP7Detailed_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal initializer {
        __KIP7_init();
        __KIP7Detailed_init_unchained(name_, symbol_, decimals_);
    }

    function __KIP7Detailed_init_unchained(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) private initializer {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _registerInterface(INTERFACE_ID_KIP7_METADATA);
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
