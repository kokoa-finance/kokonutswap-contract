// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../library/Pausable.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IStableSwap.sol";
import "./StableSwapMath.sol";

abstract contract StableSwap is ReentrancyGuard, Pausable, IStableSwap {
    error SlippageOccurred();

    uint256 public immutable override N_COINS;

    address internal constant KLAY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    uint256 internal constant FEE_DENOMINATOR = 10**10;
    uint256 internal constant PRECISION = 10**18; // The precision to convert to

    uint256 internal constant MAX_ADMIN_FEE = 10 * 10**9; // 100%
    uint256 internal constant MAX_FEE = 5 * 10**9; // 50%
    uint256 internal constant MAX_A = 10**6;
    uint256 internal constant MAX_A_CHANGE = 10;

    uint256 internal constant ADMIN_ACTIONS_DELAY = 3;
    uint256 internal constant MIN_RAMP_TIME = 86400;

    uint256 internal constant A_PRECISION = 100;

    uint256[] internal PRECISION_MUL;
    uint256[] internal RATES;

    address[] public override coins;
    uint256[] internal _storedBalances; // precision depends on coin
    uint256 public override fee; // fee * 1e10
    uint256 public override adminFee; // adminFee * 1e10

    address public override token;

    uint256 public initialA;
    uint256 public futureA;
    uint256 public initialATime;
    uint256 public futureATime;

    uint256 public adminActionsDeadline;
    uint256 public transferOwnershipDeadline;
    uint256 public futureFee;
    uint256 public futureAdminFee;
    address public futureOwner;

    // @dev WARN: be careful to add new variable here
    uint256[50] private __storageBuffer;

    constructor(uint256 _N) {
        N_COINS = _N;
    }

    /// @notice Contract initializer
    /// @param _coins Addresses of KIP7 contracts of coins
    /// @param _poolToken Address of the token representing LP share
    /// @param _initialA Amplification coefficient multiplied by n * (n - 1)
    /// @param _fee Fee to charge for exchanges
    /// @param _adminFee Admin fee
    function __StableSwap_init(
        address[] memory _coins,
        uint256[] memory _PRECISION_MUL,
        uint256[] memory _RATES,
        address _poolToken,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) internal initializer {
        __Pausable_init();
        require(_coins.length == N_COINS);
        require(_PRECISION_MUL.length == N_COINS);
        require(_RATES.length == N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            require(_coins[i] != address(0));
        }
        coins = _coins;
        PRECISION_MUL = _PRECISION_MUL;
        RATES = _RATES;
        token = _poolToken;
        initialA = _initialA * A_PRECISION;
        futureA = _initialA * A_PRECISION;
        fee = _fee;
        adminFee = _adminFee;
        _storedBalances = new uint256[](N_COINS);
    }

    function coinIndex(address coin) external view override returns (uint256) {
        address[] memory _coins = coins;
        for (uint256 i = 0; i < N_COINS; i++) {
            if (_coins[i] == coin) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function coinList() external view override returns (address[] memory) {
        return coins;
    }

    function _A() internal view returns (uint256) {
        /*
        Handle ramping A up or down
        */
        uint256 t1 = futureATime;
        uint256 A1 = futureA;

        if (block.timestamp < t1) {
            uint256 A0 = initialA;
            uint256 t0 = initialATime;
            // Expressions in uint256 cannot have negative numbers, thus "if"
            if (A1 > A0) {
                return A0 + ((A1 - A0) * (block.timestamp - t0)) / (t1 - t0);
            } else {
                return A0 - ((A0 - A1) * (block.timestamp - t0)) / (t1 - t0);
            }
        } else {
            // when t1 == 0 or block.timestamp >= t1
            return A1;
        }
    }

    function A() external view override returns (uint256) {
        return _A() / A_PRECISION;
    }

    function APrecise() external view override returns (uint256) {
        return _A();
    }

    function getD(uint256[] memory xp, uint256 amp) internal pure returns (uint256) {
        return StableSwapMath.getD(xp, amp);
    }

    function getY(
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[] memory xp_
    ) internal view returns (uint256) {
        return StableSwapMath.getY(i, j, x, xp_, _A());
    }

    function _getDy(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view virtual returns (uint256);

    function getDy(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view override returns (uint256) {
        return _getDy(i, j, dx, false);
    }

    function _getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) internal view virtual returns (uint256);

    function getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) external view override returns (uint256) {
        return _getDx(i, j, dy);
    }

    function getDyWithoutFee(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view override returns (uint256) {
        return _getDy(i, j, dx, true);
    }

    function _getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view virtual returns (uint256);

    function getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view override returns (uint256) {
        return _getDyUnderlying(i, j, dx, false);
    }

    function getDyUnderlyingWithoutFee(
        uint256 i,
        uint256 j,
        uint256 dx
    ) external view override returns (uint256) {
        return _getDyUnderlying(i, j, dx, true);
    }

    function getYD(
        uint256 A_,
        uint256 i,
        uint256[] memory xp,
        uint256 D
    ) internal pure returns (uint256) {
        return StableSwapMath.getYD(A_, i, xp, D);
    }

    /// Admin functions ///
    function rampA(uint256 _futureA, uint256 _futureTime) external override onlyOwner {
        require(block.timestamp >= initialATime + MIN_RAMP_TIME);
        require(_futureTime >= block.timestamp + MIN_RAMP_TIME); // dev: insufficient time

        uint256 _initialA = _A();
        uint256 _futureAWithPrecision = _futureA * A_PRECISION;

        require((_futureA > 0) && (_futureA < MAX_A));
        if (_futureAWithPrecision < _initialA) {
            require(_futureAWithPrecision * MAX_A_CHANGE >= _initialA);
        } else {
            require(_futureAWithPrecision <= _initialA * MAX_A_CHANGE);
        }

        initialA = _initialA;
        futureA = _futureAWithPrecision;
        initialATime = block.timestamp;
        futureATime = _futureTime;

        emit RampA(_initialA, _futureAWithPrecision, block.timestamp, _futureTime);
    }

    function stopRampA() external override onlyOwner {
        uint256 currentA = _A();
        initialA = currentA;
        futureA = currentA;
        initialATime = block.timestamp;
        futureATime = block.timestamp;
        // now (block.timestamp < t1) is always False, so we return saved A

        emit StopRampA(currentA, block.timestamp);
    }

    function commitNewFee(uint256 newFee, uint256 newAdminFee) external override onlyOwner {
        require(adminActionsDeadline == 0); // dev: active action
        require(newFee <= MAX_FEE); // dev: fee exceeds maximum
        require(newAdminFee <= MAX_ADMIN_FEE); // dev: admin fee exceeds maximum

        uint256 _deadline = block.timestamp + ADMIN_ACTIONS_DELAY;
        adminActionsDeadline = _deadline;
        futureFee = newFee;
        futureAdminFee = newAdminFee;

        emit CommitNewFee(_deadline, newFee, newAdminFee);
    }

    function applyNewFee() external override onlyOwner {
        require(block.timestamp >= adminActionsDeadline); // dev: insufficient time
        require(adminActionsDeadline != 0); // dev: no active action

        adminActionsDeadline = 0;
        uint256 _fee = futureFee;
        uint256 _adminFee = futureAdminFee;
        fee = _fee;
        adminFee = _adminFee;

        emit NewFee(_fee, _adminFee);
    }

    function revertNewParameters() external onlyOwner {
        adminActionsDeadline = 0;
    }

    function transferOwnership(address newOwner) public virtual override(IStableSwap, AccessControl) onlyOwner {
        require(transferOwnershipDeadline == 0); // dev: active transfer

        uint256 _deadline = block.timestamp + ADMIN_ACTIONS_DELAY;
        transferOwnershipDeadline = _deadline;
        futureOwner = newOwner;

        emit CommitNewOwner(_deadline, newOwner);
    }

    function applyTransferOwnership() external override onlyOwner {
        require(block.timestamp >= transferOwnershipDeadline); // dev: insufficient time
        require(transferOwnershipDeadline != 0); // dev: no active transfer

        transferOwnershipDeadline = 0;
        super.transferOwnership(futureOwner);
    }

    function revertTransferOwnership() external override onlyOwner {
        transferOwnershipDeadline = 0;
    }

    function withdrawLostToken(
        address _token,
        uint256 _amount,
        address _to
    ) external override onlyOwner {
        address[] memory _coins = coins;
        for (uint256 i = 0; i < _coins.length; i++) {
            require(_coins[i] != _token);
        }
        uint256 balance = _token == KLAY_ADDRESS ? address(this).balance : _getThisTokenBalance(_token);
        if (balance < _amount) {
            _amount = balance;
        }
        if (_token == KLAY_ADDRESS) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success);
        } else {
            _pushToken(_token, _to, _amount);
        }
    }

    function rawCall(address to, bytes memory data) internal {
        (bool success, bytes memory ret) = to.call(data);
        require(success, string(ret)); // dev: failed transfer
    }

    function arrCopy(uint256[] memory _input) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](_input.length);
        for (uint256 i = 0; i < _input.length; i++) {
            result[i] = _input[i];
        }
        return result;
    }

    function _lpTotalSupply() internal view returns (uint256) {
        return IKIP7(token).totalSupply();
    }

    function _burnLp(address _account, uint256 _amount) internal {
        rawCall(token, abi.encodeWithSignature("burn(address,uint256)", _account, _amount));
    }

    function _pullToken(
        address _token,
        address _from,
        uint256 _amount
    ) internal {
        rawCall(_token, abi.encodeWithSignature("transferFrom(address,address,uint256)", _from, address(this), _amount));
    }

    function _pushToken(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        rawCall(_token, abi.encodeWithSignature("transfer(address,uint256)", _to, _amount));
    }

    function _getThisTokenBalance(address _token) internal view returns (uint256) {
        return IKIP7(_token).balanceOf(address(this));
    }

    function _checkSlippage(uint256 big, uint256 small) internal pure {
        if (big < small) revert SlippageOccurred();
    }
}
