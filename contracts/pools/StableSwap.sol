// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../library/Pausable.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IPoolToken.sol";
import "../interface/IStableSwap.sol";

abstract contract StableSwap is ReentrancyGuard, Pausable, IStableSwap {
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
        require(_coins.length == N_COINS, "StableSwap::init: wrong _coins length");
        require(_PRECISION_MUL.length == N_COINS, "StableSwap::init: wrong _PRECISION_MUL length");
        require(_RATES.length == N_COINS, "StableSwap::init: wrong _RATES length");
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

    function coinList() external view override returns (address[] memory coins_) {
        coins_ = new address[](N_COINS);
        address[] memory _coins = coins;
        for (uint256 i = 0; i < N_COINS; i++) {
            coins_[i] = _coins[i];
        }
    }

    function balances(uint256 i) public view virtual override returns (uint256);

    function adminBalances(uint256 i) public view virtual override returns (uint256);

    function balanceList() external view override returns (uint256[] memory balances_) {
        balances_ = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            balances_[i] = balances(i);
        }
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

    function getD(uint256[] memory xp, uint256 amp) internal view returns (uint256) {
        uint256 S = 0;
        for (uint256 i = 0; i < N_COINS; i++) {
            S += xp[i];
        }
        if (S == 0) {
            return 0;
        }

        uint256 Dprev = 0;
        uint256 D = S;
        uint256 Ann = amp * N_COINS;
        for (uint256 _i = 0; _i < 255; _i++) {
            uint256 DP = D;
            for (uint256 _j = 0; _j < N_COINS; _j++) {
                DP = (DP * D) / (xp[_j] * N_COINS); // If division by 0, this will be borked: only withdrawal will work. And that is good
            }
            Dprev = D;
            D = (((Ann * S) / A_PRECISION + DP * N_COINS) * D) / (((Ann - A_PRECISION) * D) / A_PRECISION + (N_COINS + 1) * DP);
            // Equality with the precision of 1
            if (D > Dprev) {
                if (D - Dprev <= 1) return D;
            } else {
                if (Dprev - D <= 1) return D;
            }
        }
        // convergence typically occurs in 4 rounds or less, this should be unreachable!
        // if it does happen the pool is borked and LPs can withdraw via `removeLiquidity`
        revert();
    }

    function getY(
        uint256 i,
        uint256 j,
        uint256 x,
        uint256[] memory xp_
    ) internal view returns (uint256) {
        // x in the input is converted to the same price/precision

        require(i != j); // dev: same coin
        require(j >= 0); // dev: j below zero
        require(j < N_COINS); // dev: j above N_COINS

        // should be unreachable, but good for safety
        require(i >= 0);
        require(i < N_COINS);

        uint256 amp = _A();
        uint256 D = getD(xp_, amp);

        uint256 S_ = 0;
        uint256 _x = 0;
        uint256 c = D;
        uint256 Ann = amp * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i == i) {
                _x = x;
            } else if (_i != j) {
                _x = xp_[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann; // - D
        uint256 yPrev = 0;
        uint256 y = D;
        for (uint256 _i = 0; _i < 255; _i++) {
            yPrev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
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

    /// @notice Calculate estimated coins from the pool when remove by lp tokens
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @return List of amounts of coins that were withdrawn
    function calcWithdraw(uint256 _amount) external view override returns (uint256[] memory) {
        uint256 totalSupply = IPoolToken(token).totalSupply();
        uint256[] memory amounts = new uint256[](N_COINS);

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 value = (balances(i) * _amount) / totalSupply;
            amounts[i] = value;
        }

        return amounts;
    }

    function getYD(
        uint256 A_,
        uint256 i,
        uint256[] memory xp,
        uint256 D
    ) internal view returns (uint256) {
        /*
        Calculate x[i] if one reduces D from being calculated for xp to D

        Done by solving quadratic equation iteratively.
        x_1**2 + x1 * (sum' - (A*n**n - 1) * D / (A * n**n)) = D ** (n + 1) / (n ** (2 * n) * prod' * A)
        x_1**2 + b*x_1 = c

        x_1 = (x_1**2 + c) / (2*x_1 + b)
        */
        // x in the input is converted to the same price/precision

        require(i >= 0); // dev: i below zero
        require(i < N_COINS); // dev: i above N_COINS

        uint256 S_ = 0;
        uint256 _x = 0;

        uint256 c = D;
        uint256 Ann = A_ * N_COINS;

        for (uint256 _i = 0; _i < N_COINS; _i++) {
            if (_i != i) {
                _x = xp[_i];
            } else {
                continue;
            }
            S_ += _x;
            c = (c * D) / (_x * N_COINS);
        }
        c = (c * D * A_PRECISION) / (Ann * N_COINS);
        uint256 b = S_ + (D * A_PRECISION) / Ann;
        uint256 yPrev = 0;
        uint256 y = D;
        for (uint256 _i = 0; _i < 255; _i++) {
            yPrev = y;
            y = (y * y + c) / (2 * y + b - D);
            // Equality with the precision of 1
            if (y > yPrev) {
                if (y - yPrev <= 1) {
                    return y;
                }
            } else {
                if (yPrev - y <= 1) {
                    return y;
                }
            }
        }
        revert();
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

    function adminBalanceList() external view override returns (uint256[] memory balances_) {
        balances_ = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            balances_[i] = adminBalances(i);
        }
    }

    function withdrawLostToken(
        address _token,
        uint256 _amount,
        address _to
    ) external override onlyOwner {
        address[] memory _coins = coins;
        for (uint256 i = 0; i < _coins.length; i++) {
            require(_coins[i] != _token, "StableSwap::withdrawLostToken: cannot withdraw registered token");
        }
        uint256 balance = _token == KLAY_ADDRESS ? address(this).balance : IKIP7(_token).balanceOf(address(this));
        if (balance < _amount) {
            _amount = balance;
        }
        if (_token == KLAY_ADDRESS) {
            (bool success, ) = _to.call{value: _amount}("");
            require(success);
        } else {
            require(IKIP7(_token).transfer(_to, _amount));
        }
    }

    function rawCall(address to, bytes memory data) internal {
        (bool success, ) = to.call(data);
        require(success); // dev: failed transfer
    }

    function rawCall(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success); // dev: failed transfer
    }

    function arrCopy(uint256[] memory _input) internal pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](_input.length);
        for (uint256 i = 0; i < _input.length; i++) {
            result[i] = _input[i];
        }
        return result;
    }
}
