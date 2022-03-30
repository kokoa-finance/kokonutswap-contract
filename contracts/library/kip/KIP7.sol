// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../openzeppelin/contracts/utils/Address.sol";
import "../openzeppelin/proxy/Initializable.sol";
import "./IKIP7.sol";
import "./IKIP7Receiver.sol";
import "./KIP13.sol";

contract KIP7 is KIP13, IKIP7 {
    using Address for address;

    bytes4 private constant _KIP7_RECEIVED = 0x9d188c22;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;

    uint256 internal _totalSupply;

    bytes4 private constant _INTERFACE_ID_KIP7 = 0x65787371;

    function __KIP7_init() internal initializer {
        __KIP13_init();
        __KIP7_init_unchained();
    }

    function __KIP7_init_unchained() private initializer {
        _registerInterface(_INTERFACE_ID_KIP7);
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 value) public virtual override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "IKIP7: decreased allowance below zero");
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function safeTransfer(address recipient, uint256 amount) public virtual override {
        safeTransfer(recipient, amount, "");
    }

    function safeTransfer(
        address recipient,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        transfer(recipient, amount);
        require(_checkOnKIP7Received(msg.sender, recipient, amount, data), "KIP7::safeTransfer: transfer to non KIP7Receiver implementer");
    }

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override {
        safeTransferFrom(sender, recipient, amount, "");
    }

    function safeTransferFrom(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        transferFrom(sender, recipient, amount);
        require(_checkOnKIP7Received(sender, recipient, amount, data), "KIP7::safeTransferFrom: transfer to non KIP7Receiver implementer");
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "KIP7::_transfer: transfer from the zero address");
        require(recipient != address(0), "KIP7::_transfer: transfer to the zero address");
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 value
    ) internal {
        require(owner != address(0), "KIP7::_approve: approve from the zero address");
        require(spender != address(0), "KIP7::_approve: approve to the zero address");
        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function _checkOnKIP7Received(
        address sender,
        address recipient,
        uint256 amount,
        bytes memory _data
    ) internal returns (bool) {
        if (!recipient.isContract()) {
            return true;
        }

        bytes4 retval = IKIP7Receiver(recipient).onKIP7Received(msg.sender, sender, amount, _data);
        return (retval == _KIP7_RECEIVED);
    }
}
