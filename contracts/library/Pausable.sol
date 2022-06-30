// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControl.sol";

abstract contract Pausable is AccessControl {
    event Paused(address account);
    event Unpaused(address account);

    bytes32 internal constant PAUSER_ROLE = bytes32("pauser");

    bool private _paused;

    function __Pausable_init() internal initializer {
        __Pausable_init_unchained(msg.sender);
    }

    function __Pausable_init(address _owner) internal initializer {
        __Pausable_init_unchained(_owner);
    }

    function __Pausable_init_unchained(address _owner) private {
        __AccessControl_init(_owner);
        _setRoleAdmin(PAUSER_ROLE, OWNER_ROLE);
        _setupRole(PAUSER_ROLE, _owner);
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    function _whenNotPaused() private view {
        require(!paused(), "paused");
    }

    modifier whenNotPaused() virtual {
        _whenNotPaused();
        _;
    }

    function _whenPaused() private view {
        require(paused(), "not paused");
    }

    modifier whenPaused() {
        _whenPaused();
        _;
    }

    function pause() public whenNotPaused onlyRole(PAUSER_ROLE) {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public whenPaused onlyRole(PAUSER_ROLE) {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
