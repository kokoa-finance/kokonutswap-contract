// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "./StableSwap.sol";
import "../interface/IBasePool.sol";
import "../interface/IMetaPool.sol";

abstract contract MetaPool is StableSwap, IMetaPool {
    uint256 private immutable MAX_COIN;

    uint256 private immutable BASE_N_COINS;

    // Token corresponding to the pool is always the last one
    uint256 private constant BASE_CACHE_EXPIRES = 10 * 60; // 10 min
    address public override basePool;
    uint256 private baseVirtualPrice;
    uint256 public baseCacheUpdated;
    address[] private baseCoins;

    // @dev WARN: be careful to add new variable here
    uint256[50] private __storageBuffer;

    constructor(uint256 _N, uint256 _BASE_N_COINS) StableSwap(_N) {
        MAX_COIN = N_COINS - 1;
        BASE_N_COINS = _BASE_N_COINS;
    }

    // @notice Contract constructor
    // @param _coins Addresses of KIP7 contracts of coins
    // @param _poolToken Address of the token representing LP share
    // @param _basePool Address of the base pool (which will have a virtual price)
    // @param _initialA Amplification coefficient multiplied by n * (n - 1)
    // @param _fee Fee to charge for exchanges
    // @param _adminFee Admin fee
    function __MetaPool_init(
        address[] memory _coins,
        uint256[] memory _PRECISION_MUL,
        uint256[] memory _RATES,
        address _poolToken,
        address _basePool,
        uint256 _initialA,
        uint256 _fee,
        uint256 _adminFee
    ) internal initializer {
        __StableSwap_init(_coins, _PRECISION_MUL, _RATES, _poolToken, _initialA, _fee, _adminFee);

        basePool = _basePool;
        for (uint256 i = 0; i < BASE_N_COINS; i++) {
            address _baseCoin = IBasePool(_basePool).coins(i);
            baseCoins.push(_baseCoin);

            rawCall(_baseCoin, abi.encodeWithSignature("approve(address,uint256)", _basePool, type(uint256).max));
        }
    }

    function balances(uint256 i) external view override returns (uint256) {
        return _storedBalances[i];
    }

    function adminBalances(uint256 i) public view override returns (uint256) {
        return _getThisTokenBalance(coins[i]) - _storedBalances[i];
    }

    function adminBalanceList() external view override returns (uint256[] memory balances_) {
        balances_ = new uint256[](N_COINS);
        for (uint256 i = 0; i < N_COINS; i++) {
            balances_[i] = adminBalances(i);
        }
    }

    function balanceList() external view override returns (uint256[] memory) {
        return _storedBalances;
    }

    function _xp(uint256 vpRate) internal view returns (uint256[] memory) {
        return _xpMem(vpRate, _storedBalances);
    }

    function _xpMem(uint256 vpRate, uint256[] memory _balances) internal view returns (uint256[] memory result) {
        result = RATES;
        result[MAX_COIN] = vpRate; // virtual price for the metacurrency
        for (uint256 i = 0; i < N_COINS; i++) {
            result[i] = (result[i] * _balances[i]) / PRECISION;
        }
    }

    function _getBaseVirtualPrice() internal view returns (uint256) {
        return IBasePool(basePool).getVirtualPrice();
    }

    function _vpRate() internal returns (uint256) {
        if (block.timestamp > baseCacheUpdated + BASE_CACHE_EXPIRES) {
            uint256 vprice = _getBaseVirtualPrice();
            baseVirtualPrice = vprice;
            baseCacheUpdated = block.timestamp;
            return vprice;
        } else {
            return baseVirtualPrice;
        }
    }

    function _vpRateRo() internal view returns (uint256) {
        if (block.timestamp > baseCacheUpdated + BASE_CACHE_EXPIRES) {
            return _getBaseVirtualPrice();
        } else {
            return baseVirtualPrice;
        }
    }

    function getDMem(
        uint256 vpRate,
        uint256[] memory _balances,
        uint256 amp
    ) internal view returns (uint256) {
        return getD(_xpMem(vpRate, _balances), amp);
    }

    function getPrice(uint256 i, uint256 j) external view override returns (uint256 price) {
        uint256 vp = _vpRateRo();
        price = StableSwapMath.calculatePrice(i, j, _xp(vp), _A());
        if (i == MAX_COIN) {
            price = price * vp / PRECISION;
        }
        if (j == MAX_COIN) {
            price = price * PRECISION / vp;
        }
    }

    function getLpPrice(uint256 i) external view override returns (uint256) {
        return StableSwapMath.calculateLpPrice(i, _xp(_vpRateRo()), _A(), _lpTotalSupply());
    }

    /// @notice The current virtual price of the pool LP token
    /// @dev Useful for calculating profits
    /// @return LP token virtual price normalized to 1e18
    function getVirtualPrice() external view override returns (uint256) {
        // D is in the units similar to DAI (e.g. converted to precision 1e18)
        // When balanced, D = n * x_u - total virtual value of the portfolio
        return (getD(_xp(_vpRateRo()), _A()) * PRECISION) / _lpTotalSupply();
    }

    /// @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    /// @dev This calculation accounts for slippage, but not fees.
    ///      Needed to prevent front-running, not for precise calculations!
    /// @param amounts Amount of each coin being deposited
    /// @param isDeposit set True for deposits, False for withdrawals
    /// @return Expected amount of LP tokens received
    function calcTokenAmount(uint256[] memory amounts, bool isDeposit) external view override returns (uint256) {
        uint256 amp = _A();
        uint256 vpRate = _vpRateRo();
        uint256[] memory _balances = _storedBalances;
        uint256 D0 = getDMem(vpRate, _balances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (isDeposit) {
                _balances[i] += amounts[i];
            } else {
                _balances[i] -= amounts[i];
            }
        }
        uint256 D1 = getDMem(vpRate, _balances, amp);
        uint256 diff = 0;
        if (isDeposit) {
            diff = D1 - D0;
        } else {
            diff = D0 - D1;
        }
        return (diff * _lpTotalSupply()) / D0;
    }

    /// @notice Deposit coins into the pool
    /// @param amounts List of amounts of coins to deposit
    /// @param minMintAmount Minimum amount of LP tokens to mint from the deposit
    /// @return Amount of LP tokens received by depositing
    function addLiquidity(uint256[] memory amounts, uint256 minMintAmount) external payable override nonReentrant whenNotPaused returns (uint256) {
        require(msg.value == 0);
        uint256 amp = _A();
        uint256 vpRate = _vpRate();
        uint256 tokenSupply = _lpTotalSupply();

        // Initial invariant
        uint256[3] memory D;
        D[0] = 0;
        uint256[] memory oldBalances = _storedBalances;
        if (tokenSupply > 0) {
            D[0] = getDMem(vpRate, oldBalances, amp);
        }
        uint256[] memory newBalances = arrCopy(oldBalances);

        for (uint256 i = 0; i < N_COINS; i++) {
            if (tokenSupply == 0) {
                require(amounts[i] > 0); // dev: initial deposit requires all coins
            }
            // balances store amounts of c-tokens
            newBalances[i] += amounts[i];
        }

        // Invariant after change
        D[1] = getDMem(vpRate, newBalances, amp);
        require(D[1] > D[0]);

        // We need to recalculate the invariant accounting for fees
        // to calculate fair user's share
        uint256[] memory fees = new uint256[](N_COINS);
        D[2] = D[1];
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
                _storedBalances[i] = newBalances[i] - ((fees[i] * _adminFee) / FEE_DENOMINATOR);
                newBalances[i] -= fees[i];
            }
            D[2] = getDMem(vpRate, newBalances, amp);
        } else {
            _storedBalances = newBalances;
        }

        // Calculate, how much pool tokens to mint
        uint256 mintAmount;
        if (tokenSupply == 0) {
            mintAmount = D[1]; // Take the dust if there was any
        } else {
            mintAmount = (tokenSupply * (D[2] - D[0])) / D[0];
        }
        _checkSlippage(mintAmount, minMintAmount);

        // Take coins from the sender
        for (uint256 i = 0; i < N_COINS; i++) {
            if (amounts[i] > 0) {
                _pullToken(coins[i], msg.sender, amounts[i]);
            }
        }

        // Mint pool tokens
        rawCall(token, abi.encodeWithSignature("mint(address,uint256)", msg.sender, mintAmount));

        emit AddLiquidity(msg.sender, amounts, fees, D[1], tokenSupply + mintAmount);

        return mintAmount;
    }

    function _getVpRatesRo() internal view returns (uint256[] memory rates) {
        rates = RATES;
        rates[MAX_COIN] = _vpRateRo();
    }

    function _getDy(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        // dx and dy in c-units
        uint256[] memory rates = _getVpRatesRo();
        return StableSwapMath.calculateDy(rates, _xp(rates[MAX_COIN]), i, j, dx, _A(), (withoutFee ? 0 : fee));
    }

    // reference: https://github.com/curvefi/curve-contract/blob/c6df0cf14b557b11661a474d8d278affd849d3fe/contracts/pools/y/StableSwapY.vy#L351
    function _getDx(
        uint256 i,
        uint256 j,
        uint256 dy
    ) internal view override returns (uint256) {
        // dx and dy in c-units
        uint256[] memory rates = _getVpRatesRo();
        return StableSwapMath.calculateDx(rates, _xp(rates[MAX_COIN]), i, j, dy, _A(), fee);
    }

    function _getDyUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        bool withoutFee
    ) internal view override returns (uint256) {
        // dx and dy in c-units
        uint256 vpRate = _vpRateRo();
        uint256[] memory xp = _xp(vpRate);
        uint256[] memory precisions = PRECISION_MUL;
        IBasePool _basePool = IBasePool(basePool);

        uint256 metaI = MAX_COIN;
        uint256 metaJ = MAX_COIN;
        if (i < MAX_COIN) {
            metaI = i;
        }
        if (j < MAX_COIN) {
            metaJ = j;
        }

        uint256 x = 0;
        if (i < MAX_COIN) {
            x = xp[i] + dx * precisions[i];
        } else {
            if (j < MAX_COIN) {
                // i is from BasePool
                // At first, get the amount of pool tokens
                uint256[] memory baseInputs = new uint256[](BASE_N_COINS);
                baseInputs[i - MAX_COIN] = dx;
                // Token amount transformed to underlying "dollars"
                x = (_basePool.calcTokenAmount(baseInputs, true) * vpRate) / PRECISION;
                // Accounting for deposit/withdraw fees approximately
                if (!withoutFee) {
                    x -= (x * _basePool.fee()) / (2 * FEE_DENOMINATOR);
                }
                // Adding number of pool tokens
                x += xp[MAX_COIN];
            } else {
                // If both are from the base pool
                if (withoutFee) {
                    return _basePool.getDyWithoutFee(i - MAX_COIN, j - MAX_COIN, dx);
                }
                return _basePool.getDy(i - MAX_COIN, j - MAX_COIN, dx);
            }
        }

        // This pool is involved only when in-pool assets are used
        uint256 dy = xp[metaJ] - getY(metaI, metaJ, x, xp) - 1;
        dy = (dy - ((withoutFee ? 0 : fee) * dy) / FEE_DENOMINATOR);

        // If output is going via the metapool
        if (j < MAX_COIN) {
            dy /= precisions[metaJ];
        } else {
            // j is from BasePool
            // The fee is already accounted for
            if (withoutFee) {
                dy = _basePool.calcWithdrawOneCoinWithoutFee((dy * PRECISION) / vpRate, j - MAX_COIN);
            } else {
                dy = _basePool.calcWithdrawOneCoin((dy * PRECISION) / vpRate, j - MAX_COIN);
            }
        }
        return dy;
    }

    function _getVpRates() internal returns (uint256[] memory rates) {
        rates = RATES;
        rates[MAX_COIN] = _vpRate();
    }

    /// @notice Perform an exchange between two coins
    /// @dev Index values can be found via the `coins` public getter method
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @param dx Amount of `i` being exchanged
    /// @param minDy Minimum amount of `j` to receive
    /// @return Actual amount of `j` received
    function exchange(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external payable override nonReentrant whenNotPaused returns (uint256) {
        require(msg.value == 0);
        uint256[] memory rates = _getVpRates();

        uint256[] memory oldBalances = _storedBalances;
        uint256[] memory xp = _xpMem(rates[MAX_COIN], oldBalances);

        uint256 x = xp[i] + (dx * rates[i]) / PRECISION;
        uint256 y = getY(i, j, x, xp);

        uint256 dy = xp[j] - y - 1; // -1 just in case there were some rounding errors
        uint256 dyFee = (dy * fee) / FEE_DENOMINATOR;

        // Convert all to real units
        dy = ((dy - dyFee) * PRECISION) / rates[j];
        _checkSlippage(dy, minDy);

        uint256 dyAdminFee = (dyFee * adminFee) / FEE_DENOMINATOR;
        dyAdminFee = (dyAdminFee * PRECISION) / rates[j];

        // Change balances exactly in same way as we change actual KIP7 coin amounts
        _storedBalances[i] = oldBalances[i] + dx;
        // When rounding errors happen, we undercharge admin fee in favor of LP
        _storedBalances[j] = oldBalances[j] - dy - dyAdminFee;

        _pullToken(coins[i], msg.sender, dx);
        _pushToken(coins[j], msg.sender, dy);

        emit TokenExchange(msg.sender, i, dx, j, dy, dyFee);

        return dy;
    }

    // @notice Perform an exchange between two underlying coins
    // @dev Index values can be found via the `underlying_coins` public getter method
    // @param i Index value for the underlying coin to send
    // @param j Index valie of the underlying coin to recieve
    // @param dx Amount of `i` being exchanged
    // @param minDy Minimum amount of `j` to receive
    // @return Actual amount of `j` received
    function exchangeUnderlying(
        uint256 i,
        uint256 j,
        uint256 dx,
        uint256 minDy
    ) external override nonReentrant whenNotPaused returns (uint256 dy) {
        uint256[] memory rates = _getVpRates();

        // Addresses for input and output coins
        address[2] memory ioCoins;
        if (i < MAX_COIN) {
            ioCoins[0] = coins[i];
        } else {
            ioCoins[0] = baseCoins[i - MAX_COIN];
        }
        if (j < MAX_COIN) {
            ioCoins[1] = coins[j];
        } else {
            ioCoins[1] = baseCoins[j - MAX_COIN];
        }

        // "safeTransferFrom" which works for KIP7s which return bool or not
        _pullToken(ioCoins[0], msg.sender, dx);
        // end "safeTransferFrom"

        uint256 dyFee = 0;
        IBasePool basePool_ = IBasePool(basePool);
        if (i < MAX_COIN || j < MAX_COIN) {
            uint256[] memory oldBalances = _storedBalances;
            uint256[] memory xp = _xpMem(rates[MAX_COIN], oldBalances);

            uint256 x = 0;
            if (i < MAX_COIN) {
                x = xp[i] + (dx * rates[i]) / PRECISION;
            } else {
                // i is from BasePool
                // At first, get the amount of pool tokens
                uint256[] memory baseInputs = new uint256[](BASE_N_COINS);
                baseInputs[i - MAX_COIN] = dx;
                address coinI = coins[MAX_COIN];
                // Deposit and measure delta
                x = _getThisTokenBalance(coinI);
                rawCall(address(basePool_), abi.encodeWithSignature("addLiquidity(uint256[],uint256)", baseInputs, 0));
                // Need to convert pool token to "virtual" units using rates
                // dx is also different now
                dx = _getThisTokenBalance(coinI) - x;
                x = (dx * rates[MAX_COIN]) / PRECISION;
                // Adding number of pool tokens
                x += xp[MAX_COIN];
            }

            {
                uint256[2] memory metaIJ = [i < MAX_COIN ? i : MAX_COIN, j < MAX_COIN ? j : MAX_COIN];
                // Either a real coin or token
                dy = xp[metaIJ[1]] - getY(metaIJ[0], metaIJ[1], x, xp) - 1; // -1 just in case there were some rounding errors
                dyFee = (dy * fee) / FEE_DENOMINATOR;

                // Convert all to real units
                // Works for both pool coins and real coins
                dy = ((dy - dyFee) * PRECISION) / rates[metaIJ[1]];

                uint256 dyAdminFee = (dyFee * adminFee) / FEE_DENOMINATOR;
                dyAdminFee = (dyAdminFee * PRECISION) / rates[metaIJ[1]];

                // Change balances exactly in same way as we change actual KIP7 coin amounts
                _storedBalances[metaIJ[0]] = oldBalances[metaIJ[0]] + dx;
                // When rounding errors happen, we undercharge admin fee in favor of LP
                _storedBalances[metaIJ[1]] = oldBalances[metaIJ[1]] - dy - dyAdminFee;
            }

            // Withdraw from the base pool if needed
            if (j >= MAX_COIN) {
                uint256 outAmount = _getThisTokenBalance(ioCoins[1]);
                rawCall(address(basePool_), abi.encodeWithSignature("removeLiquidityOneCoin(uint256,uint256,uint256)", dy, j - MAX_COIN, 0));
                dy = _getThisTokenBalance(ioCoins[1]) - outAmount;
            }
            _checkSlippage(dy, minDy);
        } else {
            // If both are from the base pool
            dy = _getThisTokenBalance(ioCoins[1]);
            rawCall(address(basePool_), abi.encodeWithSignature("exchange(uint256,uint256,uint256,uint256)", i - MAX_COIN, j - MAX_COIN, dx, minDy));
            dy = _getThisTokenBalance(ioCoins[1]) - dy;
        }
        // "safeTransfer" which works for KIP7s which return bool or not
        _pushToken(ioCoins[1], msg.sender, dy);
        // end "safeTransfer"

        emit TokenExchangeUnderlying(msg.sender, i, dx, j, dy, dyFee);

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

        for (uint256 i = 0; i < N_COINS; i++) {
            uint256 value = (_storedBalances[i] * _amount) / totalSupply;
            _checkSlippage(value, minAmounts[i]);
            _storedBalances[i] -= value;
            amounts[i] = value;

            // "safeTransfer" which works for KIP7s which return bool or not
            _pushToken(coins[i], msg.sender, value);
        }

        _burnLp(msg.sender, _amount);

        emit RemoveLiquidity(msg.sender, amounts, new uint256[](N_COINS), totalSupply - _amount);

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
        uint256 vpRate = _vpRate();

        uint256 tokenSupply = _lpTotalSupply();
        require(tokenSupply != 0); // dev: zero total supply

        uint256[] memory oldBalances = _storedBalances;
        uint256[] memory newBalances = arrCopy(oldBalances);
        uint256[3] memory D;
        D[0] = getDMem(vpRate, oldBalances, amp);
        for (uint256 i = 0; i < N_COINS; i++) {
            newBalances[i] -= amounts[i];
        }
        D[1] = getDMem(vpRate, newBalances, amp);

        uint256[] memory fees = new uint256[](N_COINS);
        {
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
                _storedBalances[i] = newBalances[i] - ((fees[i] * _adminFee) / FEE_DENOMINATOR);
                newBalances[i] -= fees[i];
            }
        }
        D[2] = getDMem(vpRate, newBalances, amp);

        uint256 tokenAmount = ((D[0] - D[2]) * tokenSupply) / D[0];
        require(tokenAmount != 0); // dev: zero tokens burned
        tokenAmount += 1; // In case of rounding errors - make it unfavorable for the "attacker"
        _checkSlippage(maxBurnAmount, tokenAmount);

        _burnLp(msg.sender, tokenAmount);
        for (uint256 i = 0; i < N_COINS; i++) {
            if (amounts[i] != 0) {
                _pushToken(coins[i], msg.sender, amounts[i]);
            }
        }

        emit RemoveLiquidityImbalance(msg.sender, amounts, fees, D[1], tokenSupply - tokenAmount);

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
            uint256 dy,
            uint256 dyFee,
            uint256 totalSupply
        )
    {
        uint256 vpRate = _vpRateRo();
        // First, need to calculate
        // * Get current D
        // * Solve Eqn against y_i for D - _tokenAmount
        uint256 amp = _A();
        uint256[] memory xp = _xp(vpRate);
        uint256[2] memory D;
        D[0] = getD(xp, amp);

        totalSupply = _lpTotalSupply();
        D[1] = D[0] - (_tokenAmount * D[0]) / totalSupply;
        uint256 newY = getYD(amp, i, xp, D[1]);

        uint256 _fee = ((withoutFee ? 0 : fee) * N_COINS) / (4 * (N_COINS - 1));
        uint256[] memory rates = RATES;
        rates[MAX_COIN] = vpRate;

        (dy, dyFee) = __calcWithdrawOneCoin(i, amp, xp, D, newY, _fee, rates);
    }

    function __calcWithdrawOneCoin(
        uint256 i,
        uint256 amp,
        uint256[] memory xp,
        uint256[2] memory D,
        uint256 newY,
        uint256 _fee,
        uint256[] memory rates
    ) private view returns (uint256 dy, uint256 dyFee) {
        uint256[] memory xpReduced = arrCopy(xp);
        uint256 dy0 = ((xp[i] - newY) * PRECISION) / rates[i]; // w/o fees

        for (uint256 j = 0; j < N_COINS; j++) {
            uint256 dxExpected = 0;
            if (j == i) {
                dxExpected = (xp[j] * D[1]) / D[0] - newY;
            } else {
                dxExpected = xp[j] - (xp[j] * D[1]) / D[0];
            }
            xpReduced[j] -= (_fee * dxExpected) / FEE_DENOMINATOR;
        }
        dy = xpReduced[i] - getYD(amp, i, xpReduced, D[1]);
        dy = ((dy - 1) * PRECISION) / rates[i]; // Withdraw less to account for rounding errors
        dyFee = dy0 - dy;
    }

    /// @notice Calculate the amount received when withdrawing a single coin
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @return Amount of coin received
    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, false);
        return result;
    }

    /// @notice Calculate the amount received when withdrawing a single coin without fee
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @return Amount of coin received
    function calcWithdrawOneCoinWithoutFee(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        (uint256 result, , ) = _calcWithdrawOneCoin(_tokenAmount, i, true);
        return result;
    }

    /// @notice Withdraw a single coin from the pool
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @param _minAmount Minimum amount of coin to receive
    /// @return Amount of coin received
    function removeLiquidityOneCoin(
        uint256 _tokenAmount,
        uint256 i,
        uint256 _minAmount
    ) external override nonReentrant whenNotPaused returns (uint256) {
        (uint256 dy, uint256 dyFee, uint256 totalSupply) = _calcWithdrawOneCoin(_tokenAmount, i, false);
        _checkSlippage(dy, _minAmount);

        _storedBalances[i] -= (dy + (dyFee * adminFee) / FEE_DENOMINATOR);
        _burnLp(msg.sender, _tokenAmount);
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
        require(recipient != address(0));
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
