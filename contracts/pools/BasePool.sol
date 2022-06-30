// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../library/Pausable.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IPoolToken.sol";
import "../interface/IBasePool.sol";
import "./StableSwap.sol";

/**
 * @dev BasePool is the solidity implementation of Curve Finance
 *      Original code https://github.com/curvefi/curve-contract/blob/master/contracts/pools/3pool/StableSwap3Pool.vy
 */

abstract contract BasePool is IBasePool, StableSwap {
    // @dev WARN: be careful to add new variable here
    uint256[50] private __storageBuffer;

    constructor(uint256 _N) StableSwap(_N) {}

    /// @notice Contract initializer
    /// @param _coins Addresses of KIP7 contracts of coins
    /// @param _poolToken Address of the token representing LP share
    /// @param _initialA Amplification coefficient multiplied by n * (n - 1)
    /// @param _fee Fee to charge for exchanges
    /// @param _adminFee Admin fee
    function __BasePool_init(
        address[] memory _coins,
        uint256[] memory _PRECISION_MUL,
        uint256[] memory _RATES,
        address _poolToken,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) internal initializer {
        __StableSwap_init(_coins, _PRECISION_MUL, _RATES, _poolToken, _initialA, _fee, _adminFee);
    }

    function balances(uint256 i) external view override returns (uint256) {
        return _storedBalances[i];
    }

    function adminBalances(uint256 i) external view override returns (uint256) {
        return _getThisTokenBalance(coins[i]) - _storedBalances[i];
    }

    function adminBalanceList() external view override returns (uint256[] memory balances_) {
        balances_ = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            balances_[i] = _getThisTokenBalance(coins[i]) - _storedBalances[i];
        }
    }

    function balanceList() external view override returns (uint256[] memory) {
        return _storedBalances;
    }

    // 10**18 precision
    function _xp() internal view returns (uint256[] memory) {
        return _xpMem(_storedBalances);
    }

    // 10**18 precision
    function _xpMem(uint256[] memory _balances) internal view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            result[i] = (RATES[i] * _balances[i]) / PRECISION;
        }
        return result;
    }

    function getDMem(uint256[] memory _balances, uint256 amp) internal view returns (uint256) {
        return getD(_xpMem(_balances), amp);
    }

    function getPrice(uint256 i, uint256 j) external view override returns (uint256) {
        return StableSwapMath.calculatePrice(i, j, _xp(), _A());
    }

    function getLpPrice(uint256 i) external view override returns (uint256) {
        return StableSwapMath.calculateLpPrice(i, _xp(), _A(), _lpTotalSupply());
    }

    function getVirtualPrice() external view override returns (uint256) {
        /*
        Returns portfolio virtual price (for calculating profit)
        scaled up by 1e18
        */
        uint256 D = getD(_xp(), _A());
        // D is in the units similar to DAI (e.g. converted to precision 1e18)
        // When balanced, D = n * x_u - total virtual value of the portfolio
        uint256 tokenSupply = _lpTotalSupply();
        return (D * PRECISION) / tokenSupply;
    }

    /// @notice Simplified method to calculate addition or reduction in token supply at
    ///         deposit or withdrawal without taking fees into account (but looking at
    ///         slippage).
    ///         Needed to prevent front-running, not for precise calculations!
    /// @param amounts amount list of each assets
    /// @param deposit the flag whether deposit or withdrawal
    /// @return the amount of lp tokens
    function calcTokenAmount(uint256[] memory amounts, bool deposit) external view override returns (uint256) {
        /*
        Simplified method to calculate addition or reduction in token supply at
        deposit or withdrawal without taking fees into account (but looking at
        slippage) .
        Needed to prevent front-running, not for precise calculations!
        */

        uint256[] memory _balances = _storedBalances;
        uint256 amp = _A();
        uint256 D0 = getDMem(_balances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (deposit) {
                _balances[i] += amounts[i];
            } else {
                _balances[i] -= amounts[i];
            }
        }
        uint256 D1 = getDMem(_balances, amp);
        uint256 tokenAmount = _lpTotalSupply();
        uint256 diff = 0;
        if (deposit) {
            diff = D1 - D0;
        } else {
            diff = D0 - D1;
        }
        return (diff * tokenAmount) / D0;
    }

    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount) external payable override nonReentrant whenNotPaused returns (uint256) {
        require(msg.value == 0);
        uint256 amp = _A();

        uint256 tokenSupply = _lpTotalSupply();
        // Initial invariant
        uint256 D0 = 0;
        uint256[] memory oldBalances = _storedBalances;
        if (tokenSupply > 0) {
            D0 = getDMem(oldBalances, amp);
        }
        uint256[] memory newBalances = arrCopy(oldBalances);

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 inAmount = amounts[i];
            if (tokenSupply == 0) {
                require(inAmount > 0); // dev: initial deposit requires all coins
            }
            address inCoin = coins[i];

            // Take coins from the sender
            if (inAmount > 0) {
                // "safeTransferFrom" which works for KIP7s which return bool or not
                _pullToken(inCoin, msg.sender, amounts[i]);
            }

            newBalances[i] = oldBalances[i] + inAmount;
        }

        // Invariant after change
        uint256 D1 = getDMem(newBalances, amp);
        require(D1 > D0);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256 D2 = D1;
        uint256[] memory fees = new uint256[](N_COINS);
        if (tokenSupply > 0) {
            // Only account for fees if we are not the first to deposit
            uint256 _fee = (fee * N_COINS) / (4 * (N_COINS - 1));
            uint256 _adminFee = adminFee;
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 idealBalance = (D1 * oldBalances[i]) / D0;
                uint256 difference = 0;
                if (idealBalance > newBalances[i]) {
                    difference = idealBalance - newBalances[i];
                } else {
                    difference = newBalances[i] - idealBalance;
                }
                fees[i] = (_fee * difference) / FEE_DENOMINATOR;
                _storedBalances[i] = newBalances[i] - ((fees[i] * _adminFee) / FEE_DENOMINATOR);
                newBalances[i] -= fees[i];
            }
            D2 = getDMem(newBalances, amp);
        } else {
            _storedBalances = newBalances;
        }

        // Calculate, how much pool tokens to mint
        uint256 mintAmount = 0;
        if (tokenSupply == 0) {
            mintAmount = D1; // Take the dust if there was any
        } else {
            mintAmount = (tokenSupply * (D2 - D0)) / D0;
        }

        _checkSlippage(mintAmount, minMintAmount);

        // Mint pool tokens
        rawCall(token, abi.encodeWithSignature("mint(address,uint256)", msg.sender, mintAmount));

        emit AddLiquidity(msg.sender, amounts, fees, D1, tokenSupply + mintAmount);

        return mintAmount;
    }

    function _getDy(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        return StableSwapMath.calculateDy(RATES, _xp(), i, j, dx, _A(), (withoutFee ? 0 : fee));
    }

    // reference: https://github.com/curvefi/curve-contract/blob/c6df0cf14b557b11661a474d8d278affd849d3fe/contracts/pools/y/StableSwapY.vy#L351
    function _getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) internal view override returns (uint256) {
        return StableSwapMath.calculateDx(RATES, _xp(), i, j, dy, _A(), fee);
    }

    function _getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        // dx and dy in underlying units
        uint256[] memory xp = _xp();

        uint256 x = xp[i] + dx * PRECISION_MUL[i];
        uint256 y = getY(i, j, x, xp);
        uint256 dy = (xp[j] - y - 1) / PRECISION_MUL[j];
        uint256 _fee = ((withoutFee ? 0 : fee) * dy) / FEE_DENOMINATOR;
        return dy - _fee;
    }

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external payable override nonReentrant whenNotPaused returns (uint256) {
        require(msg.value == 0);
        uint256[] memory oldBalances = _storedBalances;
        uint256[] memory xp = _xpMem(oldBalances);

        address inputCoin = coins[i];

        // "safeTransferFrom" which works for KIP7s which return bool or not
        _pullToken(inputCoin, msg.sender, dx);

        uint256 x = xp[i] + (dx * RATES[i]) / PRECISION;
        uint256 y = getY(i, j, x, xp);

        uint256 dy = xp[j] - y - 1; // -1 just in case there were some rounding errors
        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;

        // Convert all to real units
        dy = ((dy - dyFee) * PRECISION) / RATES[j];
        _checkSlippage(dy, minDy);

        uint256 dyAdminFee = (dyFee * adminFee) / FEE_DENOMINATOR;
        dyAdminFee = (dyAdminFee * PRECISION) / RATES[j];

        // Change balances exactly in same way as we change actual KIP7 coin amounts
        _storedBalances[i] = oldBalances[i] + dx;
        // When rounding errors happen, we undercharge admin fee in favor of LP
        _storedBalances[j] = oldBalances[j] - dy - dyAdminFee;

        // "safeTransfer" which works for KIP7s which return bool or not
        _pushToken(coins[j], msg.sender, dy);

        emit TokenExchange(msg.sender, i, dx, j, dy, dyFee);

        return dy;
    }

    /// @notice Calculate estimated coins from the pool when remove by lp tokens
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @return List of amounts of coins that were withdrawn
    function calcWithdraw(uint256 _amount) external view override returns (uint256[] memory) {
        uint256 totalSupply = _lpTotalSupply();
        uint256[] memory amounts = new uint256[](N_COINS);

        for (uint256 i = 0; i < N_COINS; i++) {
            amounts[i] = (_storedBalances[i] * _amount) / totalSupply;
        }

        return amounts;
    }

    /// @notice Withdraw coins from the pool
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @param minAmounts Minimum amounts of underlying coins to receive
    /// @return List of amounts of coins that were withdrawn
    function removeLiquidity(uint256 _amount, uint256[] memory minAmounts) external override nonReentrant returns (uint256[] memory) {
        uint256 totalSupply = _lpTotalSupply();
        uint256[] memory amounts = new uint256[](N_COINS);
        uint256[] memory fees = new uint256[](N_COINS); // Fees are unused but we've got them historically in event

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 value = (_storedBalances[i] * _amount) / totalSupply;
            _checkSlippage(value, minAmounts[i]);
            _storedBalances[i] -= value;
            amounts[i] = value;

            // "safeTransfer" which works for KIP7s which return bool or not
            _pushToken(coins[i], msg.sender, value);
        }

        _burnLp(msg.sender, _amount);

        emit RemoveLiquidity(msg.sender, amounts, fees, totalSupply - _amount);

        return amounts;
    }

    function removeLiquidityImbalance(uint256[] memory amounts, uint256 maxBurnAmount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 tokenSupply = _lpTotalSupply();
        require(tokenSupply != 0); // dev: zero total supply
        uint256 amp = _A();

        uint256[] memory oldBalances = _storedBalances;
        uint256[] memory newBalances = arrCopy(oldBalances);
        uint256 D0 = getDMem(oldBalances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            newBalances[i] -= amounts[i];
        }
        uint256 D1 = getDMem(newBalances, amp);
        uint256[] memory fees = new uint256[](N_COINS);
        {
            uint256 _fee = (fee * N_COINS) / (4 * (N_COINS - 1));
            uint256 _adminFee = adminFee;
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 idealBalance = (D1 * oldBalances[i]) / D0;
                uint256 difference = 0;
                if (idealBalance > newBalances[i]) {
                    difference = idealBalance - newBalances[i];
                } else {
                    difference = newBalances[i] - idealBalance;
                }
                fees[i] = (_fee * difference) / FEE_DENOMINATOR;
                _storedBalances[i] = newBalances[i] - ((fees[i] * _adminFee) / FEE_DENOMINATOR);
                newBalances[i] -= fees[i];
            }
        }
        uint256 D2 = getDMem(newBalances, amp);

        uint256 tokenAmount = ((D0 - D2) * tokenSupply) / D0;
        require(tokenAmount != 0); // dev: zero tokens burned
        tokenAmount += 1; // In case of rounding errors - make it unfavorable for the "attacker"
        _checkSlippage(maxBurnAmount, tokenAmount);

        _burnLp(msg.sender, tokenAmount);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (amounts[i] != 0) {
                // "safeTransfer" which works for KIP7s which return bool or not
                _pushToken(coins[i], msg.sender, amounts[i]);
            }
        }
        emit RemoveLiquidityImbalance(msg.sender, amounts, fees, D1, tokenSupply - tokenAmount);

        return tokenAmount;
    }

    function _calcWithdrawOneCoin(
        uint256 _tokenAmount,
        uint256 i,
        bool withoutFee
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // First, need to calculate
        // * Get current D
        // * Solve Eqn against y_i for D - _tokenAmount
        uint256 amp = _A();
        uint256 totalSupply = _lpTotalSupply();

        uint256[] memory xp = _xp();

        uint256 D0 = getD(xp, amp);
        uint256 D1 = D0 - (_tokenAmount * D0) / totalSupply;
        uint256[] memory xpReduced = arrCopy(xp);

        uint256 newY = getYD(amp, i, xp, D1);
        uint256 dy0 = (xp[i] - newY) / PRECISION_MUL[i]; // w/o fees, precision depends on coin
        {
            uint256 _fee = ((withoutFee ? 0 : fee) * N_COINS) / (4 * (N_COINS - 1));
            for (uint256 j = 0; j < N_COINS; j++) {
                uint256 dxExpected = 0;
                if (j == i) {
                    dxExpected = (xp[j] * D1) / D0 - newY;
                } else {
                    dxExpected = xp[j] - (xp[j] * D1) / D0;
                    // 10**18
                }
                xpReduced[j] -= (_fee * dxExpected) / FEE_DENOMINATOR;
            }
        }
        uint256 dy = xpReduced[i] - getYD(amp, i, xpReduced, D1);
        dy = (dy - 1) / PRECISION_MUL[i]; // Withdraw less to account for rounding errors

        return (dy, dy0 - dy, totalSupply);
    }

    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, false);
        return result;
    }

    function calcWithdrawOneCoinWithoutFee(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, true);
        return result;
    }

    function removeLiquidityOneCoin(
        uint256 _tokenAmount,
        uint256 i,
        uint256 minAmount
    ) external override nonReentrant whenNotPaused returns (uint256) {
        /*
        Remove _amount of liquidity all in a form of coin i
        */

        (uint256 dy, uint256 dyFee, uint256 totalSupply) = _calcWithdrawOneCoin(_tokenAmount, i, false);
        _checkSlippage(dy, minAmount);

        _storedBalances[i] -= (dy + (dyFee * adminFee) / FEE_DENOMINATOR);
        _burnLp(msg.sender, _tokenAmount);

        // "safeTransfer" which works for KIP7s which return bool or not
        _pushToken(coins[i], msg.sender, dy);
        uint256[] memory amounts = new uint256[](N_COINS);
        uint256[] memory fees = new uint256[](N_COINS);
        amounts[i] = dy;
        fees[i] = dyFee;

        emit RemoveLiquidityOne(msg.sender, _tokenAmount, amounts, fees, totalSupply - _tokenAmount);

        return dy;
    }

    function transferOwnership(address newOwner) public override(IStableSwap, StableSwap) onlyOwner {
        super.transferOwnership(newOwner);
    }

    function withdrawAdminFees(address recipient) external override onlyOperator {
        require(recipient != address(0), "StableSwap: 0 address");
        for (uint256 i = 0; i < N_COINS; i++) {
            address c = coins[i];
            uint256 value = _getThisTokenBalance(c) - _storedBalances[i];
            if (value > 0) {
                // "safeTransfer" which works for KIP7s which return bool or not
                _pushToken(c, recipient, value);
            }
        }
    }

    function donateAdminFees() external override onlyOwner {
        for (uint256 i = 0; i < N_COINS; i++) {
            _storedBalances[i] = _getThisTokenBalance(coins[i]);
        }
    }
}
