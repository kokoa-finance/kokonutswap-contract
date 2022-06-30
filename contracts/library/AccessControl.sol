// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./openzeppelin/proxy/Initializable.sol";

contract AccessControl is Initializable {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 internal constant OWNER_ROLE = bytes32("owner");
    bytes32 internal constant ADMIN_ROLE = bytes32("admin");
    bytes32 internal constant OPERATOR_ROLE = bytes32("operator");

    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    modifier onlyRole(bytes32 role) {
        _checkRole(role, msg.sender);
        _;
    }

    modifier onlyOwner() {
        _checkRole(OWNER_ROLE, msg.sender);
        _;
    }

    modifier onlyAdmin() {
        _checkRole(ADMIN_ROLE, msg.sender);
        _;
    }

    modifier onlyOperator() {
        _checkRole(OPERATOR_ROLE, msg.sender);
        _;
    }

    function __AccessControl_init() internal initializer {
        __AccessControl_init_unchained(msg.sender);
    }

    function __AccessControl_init(address _owner) internal initializer {
        __AccessControl_init_unchained(_owner);
    }

    function __AccessControl_init_unchained(address _owner) private {
        _setupRole(OWNER_ROLE, _owner);
        _setRoleAdmin(ADMIN_ROLE, OWNER_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, OWNER_ROLE);
        _setupRole(ADMIN_ROLE, _owner);
        _setupRole(OPERATOR_ROLE, _owner);
    }

    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members[account];
    }

    function _checkRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) {
            revert("AccessControl: invalid role");
        }
    }

    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) public onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address account) public {
        require(account == msg.sender, "AccessControl: not self");

        _revokeRole(role, account);
    }

    function _setupRole(bytes32 role, address account) internal {
        _grantRole(role, account);
    }

    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal {
        bytes32 previousAdminRole = getRoleAdmin(role);
        _roles[role].adminRole = adminRole;
        emit RoleAdminChanged(role, previousAdminRole, adminRole);
    }

    function _grantRole(bytes32 role, address account) private {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, msg.sender);
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, msg.sender);
        }
    }

    // --- ownable --
    function transferOwnership(address newOwner) public virtual onlyOwner {
        _grantRole(OWNER_ROLE, newOwner);
        _revokeRole(OWNER_ROLE, msg.sender);
    }
}
