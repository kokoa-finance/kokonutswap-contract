// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControl.sol";

abstract contract Pausable is AccessControl {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    function __Pausable_init() internal initializer {
        __Pausable_init_unchained(msg.sender);
    }

    function __Pausable_init(address _owner) internal initializer {
        __Pausable_init_unchained(_owner);
    }

    function __Pausable_init_unchained(address _owner) private initializer {
        __AccessControl_init(_owner);
        _setRoleAdmin(bytes32("pauser"), bytes32("owner"));
        _setupRole(bytes32("pauser"), _owner);
    }

    function paused() public view virtual returns (bool) {
        return _paused;
    }

    modifier whenNotPaused() virtual {
        require(!paused(), "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    function pause() public whenNotPaused onlyRole("pauser") {
        _paused = true;
        emit Paused(msg.sender);
    }

    function unpause() public whenPaused onlyRole("pauser") {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}
