// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../library/Pausable.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IPoolToken.sol";
import "../interface/IKlayPool.sol";
import "./StableSwap.sol";

abstract contract KlayPool is IKlayPool, StableSwap {
    // @dev WARN: be careful to add new variable here
    uint256[50] private __storageBuffer;

    constructor(uint256 _N) StableSwap(_N) {}

    /// @notice Contract initializer
    /// @param _coins Addresses of KIP7 contracts of coins
    /// @param _poolToken Address of the token representing LP share
    /// @param _initialA Amplification coefficient multiplied by n * (n - 1)
    /// @param _fee Fee to charge for exchanges
    /// @param _adminFee Admin fee
    function __KlayPool_init(
        address[] memory _coins,
        address _poolToken,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) internal initializer {
        require(_coins[0] == KLAY_ADDRESS);
        uint256[] memory _PRECISION_MUL = new uint256[](N_COINS);
        uint256[] memory _RATES = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            _PRECISION_MUL[i] = 1;
            _RATES[i] = 1000000000000000000;
        }
        __StableSwap_init(_coins, _PRECISION_MUL, _RATES, _poolToken, _initialA, _fee, _adminFee);
    }

    function _balances(uint256 _value) internal view returns (uint256[] memory result) {
        result = new uint256[](N_COINS);
        result[0] = address(this).balance - _storedBalances[0] - _value;
        for (uint256 i = 1; i < N_COINS; i++) {
            result[i] = _getThisTokenBalance(coins[i]) - _storedBalances[i];
        }
    }

    /// @notice Get the current balance of a coin within the
    ///         pool, less the accrued admin fees
    /// @param i Index value for the coin to query balance of
    /// @return Token balance
    function balances(uint256 i) external view override returns (uint256) {
        return _balances(0)[i];
    }

    function adminBalances(uint256 i) external view override returns (uint256) {
        return _storedBalances[i];
    }

    function adminBalanceList() external view override returns (uint256[] memory) {
        return _storedBalances;
    }

    function balanceList() external view override returns (uint256[] memory) {
        return _balances(0);
    }

    function getPrice(uint256 i, uint256 j) external view override returns (uint256) {
        return StableSwapMath.calculatePrice(i, j, _balances(0), _A());
    }

    function getLpPrice(uint256 i) external view override returns (uint256) {
        return StableSwapMath.calculateLpPrice(i, _balances(0), _A(), _lpTotalSupply());
    }

    /// @notice The current virtual price of the pool LP token
    /// @dev Useful for calculating profits
    /// @return LP token virtual price normalized to 1e18
    function getVirtualPrice() external view override returns (uint256) {
        uint256 D = getD(_balances(0), _A());
        // D is in the units similar to DAI (e.g. converted to precision 1e18)
        // When balanced, D = n * x_u - total virtual value of the portfolio
        return (D * PRECISION) / _lpTotalSupply();
    }

    /// @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    /// @dev This calculation accounts for slippage, but not fees.
    ///      Needed to prevent front-running, not for precise calculations!
    /// @param amounts Amount of each coin being deposited
    /// @param isDeposit set True for deposits, False for withdrawals
    /// @return Expected amount of LP tokens received
    function calcTokenAmount(uint256[] memory amounts, bool isDeposit) external view override returns (uint256) {
        uint256 amp = _A();
        uint256[] memory balances_ = _balances(0);
        uint256 D0 = getD(balances_, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (isDeposit) {
                balances_[i] += amounts[i];
            } else {
                balances_[i] -= amounts[i];
            }
        }
        uint256 D1 = getD(balances_, amp);
        uint256 tokenAmount = _lpTotalSupply();
        uint256 diff = 0;
        if (isDeposit) {
            diff = D1 - D0;
        } else {
            diff = D0 - D1;
        }
        return (diff * tokenAmount) / D0;
    }

    /// @notice Deposit coins into the pool
    /// @param amounts List of amounts of coins to deposit
    /// @param minMintAmount Minimum amount of LP tokens to mint from the deposit
    /// @return Amount of LP tokens received by depositing
    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount) external payable override nonReentrant whenNotPaused returns (uint256) {
        // Initial invariant
        uint256 amp = _A();
        uint256[] memory oldBalances = _balances(msg.value);
        uint256[] memory D = new uint256[](3);
        D[0] = getD(oldBalances, amp);

        uint256 tokenSupply = _lpTotalSupply();
        uint256[] memory newBalances = arrCopy(oldBalances);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (tokenSupply == 0) {
                require(amounts[i] > 0); // dev: initial deposit requires all coins
            }
            newBalances[i] += amounts[i];
        }

        // Invariant after change
        D[1] = getD(newBalances, amp);
        require(D[1] > D[0]);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256[] memory fees = new uint256[](N_COINS);
        uint256 mintAmount = 0;
        D[2] = 0;
        if (tokenSupply > 0) {
            // Only account for fees if we are not the first to deposit
            uint256 _fee = (fee * N_COINS) / (4 * (N_COINS - 1));
            uint256 _adminFee = adminFee;
            for (uint256 i = 0; i < N_COINS; i++) {
                uint256 idealBalance = (D[1] * oldBalances[i]) / D[0];
                uint256 difference = 0;
                if (idealBalance > newBalances[i]) {
                    difference = idealBalance - newBalances[i];
                } else {
                    difference = newBalances[i] - idealBalance;
                }
                fees[i] = (_fee * difference) / FEE_DENOMINATOR;
                if (_adminFee != 0) {
                    _storedBalances[i] += (fees[i] * _adminFee) / FEE_DENOMINATOR;
                }
                newBalances[i] -= fees[i];
            }
            D[2] = getD(newBalances, amp);
            mintAmount = (tokenSupply * (D[2] - D[0])) / D[0];
        } else {
            mintAmount = D[1]; // Take the dust if there was any
        }

        _checkSlippage(mintAmount, minMintAmount);

        // Take coins from the sender
        require(msg.value == amounts[0]);
        for (uint256 i = 1; i < N_COINS; i++) {
            if (amounts[i] > 0) {
                _pullToken(coins[i], msg.sender, amounts[i]);
            }
        }

        // Mint pool tokens
        rawCall(token, abi.encodeWithSignature("mint(address,uint256)", msg.sender, mintAmount));

        emit AddLiquidity(msg.sender, amounts, fees, D[1], tokenSupply + mintAmount);

        return mintAmount;
    }

    function _getDy(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        uint256[] memory rates = new uint256[](N_COINS);
        for (uint256 k = 0; k < rates.length; k++) {
            rates[k] = PRECISION;
        }
        return StableSwapMath.calculateDy(rates, _balances(0), i, j, dx, _A(), (withoutFee ? 0 : fee));
    }

    // reference: https://github.com/curvefi/curve-contract/blob/c6df0cf14b557b11661a474d8d278affd849d3fe/contracts/pools/y/StableSwapY.vy#L351
    function _getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) internal view override returns (uint256) {
        uint256[] memory rates = new uint256[](N_COINS);
        for (uint256 k = 0; k < rates.length; k++) {
            rates[k] = PRECISION;
        }
        return StableSwapMath.calculateDx(rates, _balances(0), i, j, dy, _A(), fee);
    }

    function _getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        return _getDy(i, j, dx, withoutFee);
    }

    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external payable override nonReentrant whenNotPaused returns (uint256) {
        uint256[] memory xp = _balances(msg.value);
        // dx and dy are in aTokens

        uint256 x = xp[i] + dx;
        uint256 y = getY(i, j, x, xp);
        uint256 dy = xp[j] - y - 1;
        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;

        dy = dy - dyFee;
        _checkSlippage(dy, minDy);

        uint256 _adminFee = adminFee;
        if (_adminFee != 0) {
            uint256 dyAdminFee = (dyFee * _adminFee) / FEE_DENOMINATOR;
            if (dyAdminFee != 0) {
                _storedBalances[j] += dyAdminFee;
            }
        }

        if (i == 0) {
            require(msg.value == dx);
            _pushToken(coins[j], msg.sender, dy);
        } else if (j == 0) {
            require(msg.value == 0);
            _pullToken(coins[i], msg.sender, dx);
            rawCall(msg.sender, dy);
        } else {
            require(msg.value == 0);
            _pullToken(coins[i], msg.sender, dx);
            _pushToken(coins[j], msg.sender, dy);
        }

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
        uint256[] memory balances_ = _balances(0);

        for (uint256 i = 0; i < N_COINS; i++) {
            amounts[i] = (balances_[i] * _amount) / totalSupply;
        }

        return amounts;
    }

    /// @notice Withdraw coins from the pool
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @param minAmounts Minimum amounts of underlying coins to receive
    /// @return List of amounts of coins that were withdrawn
    function removeLiquidity(uint256 _amount, uint256[] memory minAmounts) external nonReentrant returns (uint256[] memory) {
        uint256[] memory amounts = _balances(0);
        uint256 totalSupply = _lpTotalSupply();
        _burnLp(msg.sender, _amount);

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 value = (amounts[i] * _amount) / totalSupply;
            _checkSlippage(value, minAmounts[i]);

            amounts[i] = value;
            if (i == 0) {
                rawCall(msg.sender, value);
            } else {
                _pushToken(coins[1], msg.sender, value);
            }
        }

        uint256[] memory fees;
        emit RemoveLiquidity(msg.sender, amounts, fees, totalSupply - _amount);

        return amounts;
    }

    /// @notice Withdraw coins from the pool in an imbalanced amount
    /// @param amounts List of amounts of underlying coins to withdraw
    /// @param maxBurnAmount Maximum amount of LP token to burn in the withdrawal
    /// @return Actual amount of the LP token burned in the withdrawal
    function removeLiquidityImbalance(uint256[] memory amounts, uint256 maxBurnAmount)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        uint256 amp = _A();
        uint256[] memory oldBalances = _balances(0);
        uint256 D0 = getD(oldBalances, amp);
        uint256[] memory newBalances = arrCopy(oldBalances);
        for (uint256 i = 0; i < N_COINS; i++) {
            newBalances[i] -= amounts[i];
        }
        uint256 D1 = getD(newBalances, amp);

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
                if (_adminFee != 0) {
                    _storedBalances[i] = (fees[i] * _adminFee) / FEE_DENOMINATOR;
                }
                newBalances[i] -= fees[i];
            }
        }
        uint256 D2 = getD(newBalances, amp);

        uint256 tokenSupply = _lpTotalSupply();
        uint256 tokenAmount = ((D0 - D2) * tokenSupply) / D0;

        require(tokenAmount != 0); // dev: zero tokens burned
        _checkSlippage(maxBurnAmount, tokenAmount);

        _burnLp(msg.sender, tokenAmount);

        if (amounts[0] != 0) {
            rawCall(msg.sender, amounts[0]);
        }
        for (uint256 i = 1; i < N_COINS; i++) {
            if (amounts[i] != 0) {
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
        uint256[] memory xp = _balances(0);
        uint256 D0 = getD(xp, amp);
        uint256 totalSupply = _lpTotalSupply();
        uint256 D1 = D0 - (_tokenAmount * D0) / totalSupply;
        uint256 newY = getYD(amp, i, xp, D1);

        uint256 dy;
        {
            uint256 _fee = ((withoutFee ? 0 : fee) * N_COINS) / (4 * (N_COINS - 1));
            uint256[] memory xpReduced = arrCopy(xp);
            for (uint256 j = 0; j < N_COINS; j++) {
                uint256 dxExpected = 0;
                if (j == i) {
                    dxExpected = (xp[j] * D1) / D0 - newY;
                } else {
                    dxExpected = xp[j] - (xp[j] * D1) / D0;
                }
                xpReduced[j] -= (_fee * dxExpected) / FEE_DENOMINATOR;
            }
            dy = xpReduced[i] - getYD(amp, i, xpReduced, D1);
            dy -= 1; // Withdraw less to account for rounding errors
        }

        return (dy, (xp[i] - newY) - dy, totalSupply);
    }

    /// @notice Calculate the amount received when withdrawing a single coin
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @return Amount of coin received
    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, false);
        return result;
    }

    function calcWithdrawOneCoinWithoutFee(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, true);
        return result;
    }

    /// @notice Withdraw a single coin from the pool
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @param minAmount Minimum amount of coin to receive
    /// @return Amount of coin received
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

        _storedBalances[i] += (dyFee * adminFee) / FEE_DENOMINATOR;

        _burnLp(msg.sender, _tokenAmount);

        if (i == 0) {
            rawCall(msg.sender, dy);
        } else {
            _pushToken(coins[i], msg.sender, dy);
        }
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

    function withdrawAdminFees(address recipient) external override onlyOperator nonReentrant {
        require(recipient != address(0), "StableSwap: 0 address");

        uint256[] memory _adminBalances = _storedBalances;
        if (_adminBalances[0] > 0) {
            rawCall(recipient, _adminBalances[0]);
        }
        for (uint256 i = 1; i < N_COINS; i++) {
            if (_adminBalances[i] > 0) {
                _pushToken(coins[i], recipient, _adminBalances[i]);
            }
        }
        _clearAdminBalances();
    }

    function donateAdminFees() external override onlyOwner nonReentrant {
        _clearAdminBalances();
    }

    function _clearAdminBalances() internal {
        for (uint256 i = 0; i < N_COINS; i++) {
            _storedBalances[i] = 0;
        }
    }

    function rawCall(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        require(success); // dev: failed transfer
    }
}
