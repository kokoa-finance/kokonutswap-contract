// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "../library/kip/IKIP7Detailed.sol";
import "../interface/IMetaPool.sol";
import "../interface/IBasePool.sol";
import "../interface/IExtended.sol";

abstract contract MetaPoolExtended is Pausable, IExtended {
    uint256 private immutable N_COINS;
    uint256 private immutable MAX_COIN;
    uint256 private immutable BASE_N_COINS;
    uint256 private immutable N_ALL_COINS;

    IMetaPool private immutable POOL;
    IKIP7 private immutable TOKEN;
    IBasePool private immutable BASE_POOL;

    uint256 private constant PRECISION = 10**18;
    uint256 private constant FEE_DENOMINATOR = 10**10;
    uint256 private constant FEE_IMPRECISION = 100 * 10**8;

    address[] public coins;
    address[] public baseCoins;

    constructor(IMetaPool _POOL) {
        POOL = _POOL;
        TOKEN = IKIP7(_POOL.token());
        IBasePool _basePool = IBasePool(_POOL.basePool());
        BASE_POOL = _basePool;
        N_COINS = _POOL.N_COINS();
        MAX_COIN = N_COINS - 1;
        BASE_N_COINS = _basePool.N_COINS();
        N_ALL_COINS = N_COINS + BASE_N_COINS - 1;
    }

    function __MetaPoolExtended_init() internal initializer {
        __Pausable_init();

        address[] memory coinList = POOL.coinList();
        coins = coinList;
        for (uint256 i = 0; i < N_COINS; i++) {
            _maxApprove(coinList[i], address(POOL));
        }

        address[] memory baseCoinList = BASE_POOL.coinList();
        baseCoins = baseCoinList;
        for (uint256 i = 0; i < BASE_N_COINS; i++) {
            _maxApprove(baseCoinList[i], address(BASE_POOL));
        }
    }

    function pool() external view override returns (address) {
        return address(POOL);
    }

    function coinIndex(address coin) external view override returns (uint256) {
        uint256 metaIndex = _coinIndex(address(POOL), coin);
        if (metaIndex < MAX_COIN) {
            return metaIndex;
        }
        uint256 baseIndex = _coinIndex(address(BASE_POOL), coin);
        return baseIndex == type(uint256).max ? baseIndex : baseIndex + MAX_COIN;
    }

    function getPrice(uint256 i, uint256 j) external view override returns (uint256) {
        if (i == j) {
            return PRECISION;
        }
        if (i >= MAX_COIN && j >= MAX_COIN) {
            return BASE_POOL.getPrice(i - MAX_COIN, j - MAX_COIN);
        }
        if (i < MAX_COIN && j < MAX_COIN) {
            return POOL.getPrice(i, j);
        }
        uint256 price = PRECISION;
        if (i < MAX_COIN) {
            price = price * POOL.getPrice(i, MAX_COIN) / PRECISION;
        } else {
            price = price * PRECISION / BASE_POOL.getLpPrice(i - MAX_COIN);
        }

        if (j < MAX_COIN) {
            price = price * POOL.getPrice(MAX_COIN, j) / PRECISION;
        } else {
            price = price * BASE_POOL.getLpPrice(j - MAX_COIN) / PRECISION;
        }
        return price;
    }

    function _coinIndex(address _pool, address coin) internal view returns (uint256) {
        return II4ISwapPool(_pool).coinIndex(coin);
    }

    /// @notice Wrap underlying coins and deposit them in the pool
    /// @param amounts List of amounts of underlying coins to deposit
    /// @param minMintAmount Minimum amount of LP tokens to mint from the deposit
    /// @return Amount of LP tokens received by depositing
    function addLiquidity(uint256[] calldata amounts, uint256 minMintAmount) external override whenNotPaused returns (uint256) {
        uint256[] memory metaAmounts = new uint256[](N_COINS);
        uint256[] memory baseAmounts = new uint256[](BASE_N_COINS);
        bool depositBase = false;

        for (uint256 i = 0; i < N_ALL_COINS; i++) {
            uint256 amount = amounts[i];
            if (amount == 0) {
                continue;
            }
            address coin = address(0);
            if (i < MAX_COIN) {
                coin = coins[i];
                metaAmounts[i] = amount;
            } else {
                uint256 x = i - MAX_COIN;
                coin = baseCoins[x];
                baseAmounts[x] = amount;
                depositBase = true;
            }
            _pullToken(coin, msg.sender, amount);
        }
        if (depositBase) {
            _addLiquidity(address(BASE_POOL), baseAmounts, 0);
            metaAmounts[MAX_COIN] = _getThisTokenBalance(coins[MAX_COIN]);
        }
        _addLiquidity(address(POOL), metaAmounts, minMintAmount);

        uint256 _lpAmount = _getThisTokenBalance(address(TOKEN));
        _pushToken(address(TOKEN), msg.sender, _lpAmount);

        return _lpAmount;
    }

    function _addLiquidity(
        address _pool,
        uint256[] memory amounts,
        uint256 minMintAmount
    ) internal {
        rawCall(_pool, abi.encodeWithSignature("addLiquidity(uint256[],uint256)", amounts, minMintAmount));
    }

    /// @notice Withdraw and unwrap coins from the pool
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @param minAmounts Minimum amounts of underlying coins to receive
    /// @return List of amounts of underlying coins that were withdrawn
    function removeLiquidity(uint256 _amount, uint256[] calldata minAmounts) external override returns (uint256[] memory) {
        _pullToken(address(TOKEN), msg.sender, _amount);

        uint256[] memory minAmountsMeta = new uint256[](N_COINS);
        uint256[] memory minAmountsBase = new uint256[](BASE_N_COINS);
        uint256[] memory amounts = new uint256[](N_ALL_COINS);

        for (uint256 i = 0; i < MAX_COIN; i++) {
            minAmountsMeta[i] = minAmounts[i];
        }
        _removeLiquidity(address(POOL), _amount, minAmountsMeta);

        uint256 _baseAmount = _getThisTokenBalance(coins[MAX_COIN]);
        for (uint256 i = 0; i < BASE_N_COINS; i++) {
            minAmountsBase[i] = minAmounts[MAX_COIN + i];
        }
        _removeLiquidity(address(BASE_POOL), _baseAmount, minAmountsBase);

        for (uint256 i = 0; i < N_ALL_COINS; i++) {
            address coin = address(0);
            if (i < MAX_COIN) {
                coin = coins[i];
            } else {
                coin = baseCoins[i - MAX_COIN];
            }
            amounts[i] = _getThisTokenBalance(coin);
            _pushToken(coin, msg.sender, amounts[i]);
        }
        return amounts;
    }

    function _removeLiquidity(
        address _pool,
        uint256 amount,
        uint256[] memory minAmounts
    ) internal {
        rawCall(_pool, abi.encodeWithSignature("removeLiquidity(uint256,uint256[])", amount, minAmounts));
    }

    /// @notice Calculate estimated coins from the pool when remove by lp tokens
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _amount Quantity of LP tokens to burn in the withdrawal
    /// @return List of amounts of coins that were withdrawn
    function calcWithdraw(uint256 _amount) external view override returns (uint256[] memory) {
        uint256[] memory amounts = new uint256[](N_ALL_COINS);
        uint256[] memory metaAmounts = _calcWithdraw(address(POOL), _amount);
        uint256[] memory baseAmounts = _calcWithdraw(address(BASE_POOL), metaAmounts[MAX_COIN]);

        for (uint256 i = 0; i < N_ALL_COINS; i++) {
            if (i < MAX_COIN) {
                amounts[i] = metaAmounts[i];
            } else {
                amounts[i] = baseAmounts[i - MAX_COIN];
            }
        }

        return amounts;
    }

    function _calcWithdraw(address _pool, uint256 amount) internal view returns (uint256[] memory) {
        return II4ISwapPool(_pool).calcWithdraw(amount);
    }

    /// @notice Withdraw and unwrap a single coin from the pool
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the coin to withdraw
    /// @param _minAmount Minimum amount of underlying coin to receive
    /// @return Amount of underlying coin received
    function removeLiquidityOneCoin(
        uint256 _tokenAmount,
        uint256 i,
        uint256 _minAmount
    ) external override whenNotPaused returns (uint256) {
        _pullToken(address(TOKEN), msg.sender, _tokenAmount);

        address coin = address(0);
        if (i < MAX_COIN) {
            coin = coins[i];
            // Withdraw a metapool coin
            _removeLiquidityOneCoin(address(POOL), _tokenAmount, i, _minAmount);
        } else {
            coin = baseCoins[i - MAX_COIN];
            // Withdraw a base pool coin
            _removeLiquidityOneCoin(address(POOL), _tokenAmount, MAX_COIN, 0);
            _removeLiquidityOneCoin(address(BASE_POOL), _getThisTokenBalance(coins[MAX_COIN]), i - MAX_COIN, _minAmount);
        }

        uint256 coinAmount = _getThisTokenBalance(coin);
        _pushToken(coin, msg.sender, coinAmount);

        return coinAmount;
    }

    function _removeLiquidityOneCoin(
        address _pool,
        uint256 amount,
        uint256 i,
        uint256 minAmount
    ) internal {
        rawCall(_pool, abi.encodeWithSignature("removeLiquidityOneCoin(uint256,uint256,uint256)", amount, i, minAmount));
    }

    /// @notice Calculate the amount received when withdrawing and unwrapping a single coin
    /// @param _tokenAmount Amount of LP tokens to burn in the withdrawal
    /// @param i Index value of the underlying coin to withdraw
    /// @return Amount of coin received
    function calcWithdrawOneCoin(uint256 _tokenAmount, uint256 i) external view override returns (uint256) {
        if (i < MAX_COIN) {
            return _calcWithdrawOneCoin(address(POOL), _tokenAmount, i);
        } else {
            return _calcWithdrawOneCoin(address(BASE_POOL), _calcWithdrawOneCoin(address(POOL), _tokenAmount, MAX_COIN), i - MAX_COIN);
        }
    }

    function _calcWithdrawOneCoin(
        address _pool,
        uint256 amount,
        uint256 i
    ) internal view returns (uint256) {
        return II4ISwapPool(_pool).calcWithdrawOneCoin(amount, i);
    }

    /// @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    /// @dev This calculation accounts for slippage, but not fees.
    /// Needed to prevent front-running, not for precise calculations!
    /// @param amounts Amount of each underlying coin being deposited
    /// @param isDeposit set True for deposits, False for withdrawals
    /// @return Expected amount of LP tokens received
    function calcTokenAmount(uint256[] calldata amounts, bool isDeposit) external view returns (uint256) {
        uint256[] memory metaAmounts = new uint256[](N_COINS);
        uint256[] memory baseAmounts = new uint256[](BASE_N_COINS);

        for (uint256 i = 0; i < MAX_COIN; i++) {
            metaAmounts[i] = amounts[i];
        }
        for (uint256 i = 0; i < BASE_N_COINS; i++) {
            baseAmounts[i] = amounts[i + MAX_COIN];
        }

        metaAmounts[MAX_COIN] = _calcTokenAmount(address(BASE_POOL), baseAmounts, isDeposit);

        return _calcTokenAmount(address(POOL), metaAmounts, isDeposit);
    }

    function _calcTokenAmount(
        address _pool,
        uint256[] memory amounts,
        bool isDeposit
    ) internal view returns (uint256) {
        return II4ISwapPool(_pool).calcTokenAmount(amounts, isDeposit);
    }

    function rawCall(address to, bytes memory data) internal {
        (bool success, bytes memory ret) = to.call(data);
        require(success, string(ret)); // dev: failed transfer
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

    function _maxApprove(address _token, address _to) internal {
        rawCall(_token, abi.encodeWithSignature("approve(address,uint256)", _to, type(uint256).max));
    }
}
