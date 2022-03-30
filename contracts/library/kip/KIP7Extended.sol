// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../openzeppelin/proxy/Initializable.sol";
import "../AccessControl.sol";
import "./IKIP7Extended.sol";
import "./KIP7Detailed.sol";
import "../Pausable.sol";

contract KIP7Extended is KIP7Detailed, IKIP7Extended, AccessControl, Pausable {
    function __KIP7Extended_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal initializer {
        __KIP7Detailed_init(name_, symbol_, decimals_);
        __Pausable_init();
    }

    function __KIP7Extended_init(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address _owner
    ) internal initializer {
        __KIP7Detailed_init(name_, symbol_, decimals_);
        __Pausable_init(_owner);
    }

    function __KIP7Extended_init_unchained() private initializer {}

    function mint(address account, uint256 amount) public override onlyAdmin whenNotPaused returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(address account, uint256 value) public override onlyAdmin whenNotPaused returns (bool) {
        _burn(account, value);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "KIP7Extended::_mint: mint to the zero address");
        _totalSupply = _totalSupply + amount;
        _balances[account] = _balances[account] + amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 value) internal {
        require(account != address(0), "KIP7Extended::_burn: burn from the zero address");
        _totalSupply = _totalSupply - value;
        _balances[account] = _balances[account] - value;
        emit Transfer(account, address(0), value);
    }

    function transfer(address recipient, uint256 amount) public virtual override(KIP7, IKIP7) whenNotPaused returns (bool) {
        return super.transfer(recipient, amount);
    }

    function approve(address spender, uint256 value) public virtual override(KIP7, IKIP7) whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override(KIP7, IKIP7) whenNotPaused returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }
}
