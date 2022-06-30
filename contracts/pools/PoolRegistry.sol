// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/AccessControl.sol";
import "../library/kip/IKIP7Extended.sol";
import "../interface/IPoolManager.sol";
import "../interface/ICryptoSwap2Pool.sol";
import "../interface/II4ISwapPool.sol";
import "../library/openzeppelin/contracts/utils/SafeCast.sol";
import "../interface/IStakingPool.sol";
import "../interface/IPoolRegistry.sol";
import "../interface/IExtended.sol";

contract PoolRegistry is AccessControl, IPoolRegistry {
    error NoPool();
    error PoolExists();
    error WrongPoolAddress();
    error WrongPoolType();

    event PoolAdded(address _pool, address _lpToken, uint64 _nCoins, uint256 _poolType, uint256 _decimals, address[] _coins, string _name);
    event PoolRemoved(address _pool);
    event PoolManagerUpdated(address _pool, address _poolManager);
    event StakingPoolUpdated(address _pool, address _stakingPool);
    event ExtendedUpdated(address _pool, address _extended);
    event PoolNameUpdated(address _pool, string _name);

    struct CoinInfo {
        uint128 index;
        uint128 registerCount;
        address[] swapFor;
    }

    address private constant KLAY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 private constant MAX_COINS = 8;

    uint256 public lastUpdated;
    address[] public poolList;
    mapping(address => PoolInfo) internal _poolInfoMap;
    mapping(address => address) public override getPoolFromLpToken;
    mapping(address => address) public override getLpToken;
    mapping(uint256 => uint256) public marketCounts; // key => index
    mapping(uint256 => mapping(uint256 => address)) public markets; // key => index => pool

    mapping(address => CoinInfo) internal _coinInfoMap;
    address[] public coinList;
    mapping(uint256 => uint256) public coinSwapIndexes;

    mapping(address => address) public override getPoolManager;
    mapping(address => address) public override getStakingPool;
    mapping(address => address) public getExtended;

    function __PoolRegistry_init() public {
        __AccessControl_init();
    }

    function addPool(
        address _pool,
        uint64 _nCoins,
        uint64 _poolType,
        address _extended
    ) external onlyOwner {
        if (_poolInfoMap[_pool].coins.length != 0) revert PoolExists(); // dev: pool exists
        address _lpToken = II4ISwapPool(_pool).token();
        if (getPoolFromLpToken[_lpToken] != address(0)) revert PoolExists();
        // add pool to pool_list
        poolList.push(_pool);
        PoolInfo memory newPoolInfo;
        newPoolInfo.index = SafeCast.toUint128(poolList.length);
        newPoolInfo.nCoins = _nCoins;
        newPoolInfo.poolType = _poolType;
        newPoolInfo.name = IKIP7Detailed(_lpToken).name();

        // update public mappings
        getPoolFromLpToken[_lpToken] = _pool;
        getLpToken[_pool] = _lpToken;

        address[] memory coins = _getNewPoolCoins(_pool, _nCoins);
        newPoolInfo.coins = coins;
        uint256 _decimals = _getNewPoolDecimals(coins, _nCoins);
        newPoolInfo.decimals = _decimals;

        lastUpdated = block.timestamp;
        _poolInfoMap[_pool] = newPoolInfo;
        emit PoolAdded(_pool, _lpToken, newPoolInfo.nCoins, newPoolInfo.poolType, newPoolInfo.decimals, newPoolInfo.coins, newPoolInfo.name);

        if (_extended != address(0)) {
            setExtended(_pool, _extended);
        }
    }

    /// @notice Remove a pool to the registry
    /// @dev Only callable by admin
    /// @param _pool Pool address to remove
    function removePool(address _pool) external onlyOwner {
        if (_poolInfoMap[_pool].coins.length == 0) revert NoPool();

        delete getPoolFromLpToken[_pool];
        delete getLpToken[_pool];

        // remove _pool from pool_list
        uint256 arrIndex = _poolInfoMap[_pool].index - 1;
        uint256 arrEndIndex = poolList.length - 1;

        if (arrIndex < arrEndIndex) {
            // replace _pool with final value in pool_list
            address addr = poolList[arrEndIndex];
            poolList[arrIndex] = addr;
            _poolInfoMap[addr].index = SafeCast.toUint128(arrIndex + 1);
        }

        // delete final pool_list value
        delete poolList[arrEndIndex];
        poolList.pop();

        address[] memory _coins = new address[](MAX_COINS);

        uint256 nCoins = _poolInfoMap[_pool].nCoins;
        for (uint256 i = 0; i < nCoins; i++) {
            _coins[i] = _poolInfoMap[_pool].coins[i];
            // delete coin address from pool_data
            _unregisterCoin(_coins[i]);
        }
        delete _poolInfoMap[_pool];

        for (uint256 i = 0; i < nCoins; i++) {
            address _coin = _coins[i];

            // remove pool from markets
            uint256 i2 = i + 1;
            for (uint256 x = i2; x < nCoins; x++) {
                address coinX = _coins[x];
                _removeMarket(_pool, _coin, coinX);
            }
        }
        lastUpdated = block.timestamp;
        emit PoolRemoved(_pool);
    }

    /// @notice Set pool manager contracts``
    /// @param _pool Pool address
    /// @param _poolManager Pool manager address
    function setPoolManager(address _pool, address _poolManager) external onlyOwner {
        if (_pool != IPoolManager(_poolManager).pool()) revert WrongPoolAddress();
        getPoolManager[_pool] = _poolManager;
        lastUpdated = block.timestamp;
        emit PoolManagerUpdated(_pool, _poolManager);
    }

    /// @notice Set staking pool contracts``
    /// @param _pool Pool address
    /// @param _stakingPool Staking pool address
    function setStakingPool(address _pool, address _stakingPool) external onlyOwner {
        if (getLpToken[_pool] != IStakingPool(_stakingPool).token()) revert WrongPoolAddress();
        getStakingPool[_pool] = _stakingPool;
        lastUpdated = block.timestamp;
        emit StakingPoolUpdated(_pool, _stakingPool);
    }

    /// @notice Set extended contracts``
    /// @param _pool Pool address
    /// @param _extended Extended address
    function setExtended(address _pool, address _extended) public onlyOwner {
        if (_pool != IExtended(_extended).pool()) revert WrongPoolAddress();
        if (_poolInfoMap[_pool].poolType != 2) revert WrongPoolType();
        getExtended[_pool] = _extended;
        lastUpdated = block.timestamp;
        emit ExtendedUpdated(_pool, _extended);
    }

    function updatePoolName(address _pool) external onlyOwner {
        if (_poolInfoMap[_pool].coins.length == 0) revert NoPool();
        string memory _name = IKIP7Detailed(getLpToken[_pool]).name();
        if (keccak256(bytes(_poolInfoMap[_pool].name)) == keccak256(bytes(_name))) {
            revert("Nothing to update");
        }
        _poolInfoMap[_pool].name = _name;
        emit PoolNameUpdated(_pool, _name);
    }

    function _getNewPoolCoins(address _pool, uint256 _nCoins) internal returns (address[] memory) {
        address[] memory _coinList = new address[](_nCoins);
        address coin = address(0);
        for (uint256 i = 0; i < _nCoins; i++) {
            coin = II4ISwapPool(_pool).coins(i);
            _coinList[i] = coin;
        }

        for (uint256 i = 0; i < _nCoins; i++) {
            _registerCoin(_coinList[i]);
            // add pool to markets
            uint256 i2 = i + 1;
            for (uint256 x = i2; x < _nCoins; x++) {
                uint256 key = (uint256(uint160(_coinList[i])) ^ uint256(uint160(_coinList[x])));
                uint256 length = marketCounts[key];
                markets[key][length] = _pool;
                marketCounts[key] = length + 1;

                // register the coin pair
                if (length == 0) {
                    _registerCoinPair(_coinList[x], _coinList[i], key);
                }
            }
        }
        return _coinList;
    }

    function _getNewPoolDecimals(address[] memory _coins, uint256 _nCoins) internal view returns (uint256) {
        uint256 packed = 0;
        uint256 value = 0;
        for (uint256 i = 0; i < _nCoins; i++) {
            address coin = _coins[i];
            if (coin == KLAY_ADDRESS) {
                value = 18;
            } else {
                value = IKIP7Extended(coin).decimals();
                require(value < 256, "PoolRegistry: decimal overflow"); // dev: decimal overflow;
            }
            packed += (value << (i * 8));
        }
        return packed;
    }

    function _registerCoin(address _coin) internal {
        if (_coinInfoMap[_coin].registerCount == 0) {
            uint256 _coinCount = coinList.length;
            _coinInfoMap[_coin].index = SafeCast.toUint128(_coinCount);
            coinList.push(_coin);
        }
        _coinInfoMap[_coin].registerCount += 1;
    }

    function _registerCoinPair(
        address _coinA,
        address _coinB,
        uint256 _key
    ) internal {
        // register _coinB in _coinA's array of coins
        uint256 coinBPos = _coinInfoMap[_coinA].swapFor.length;
        _coinInfoMap[_coinA].swapFor.push(_coinB);
        // register _coinA in _coinB's array of coins
        uint256 coinAPos = _coinInfoMap[_coinB].swapFor.length;
        _coinInfoMap[_coinB].swapFor.push(_coinA);
        // register indexes (coinA pos in coinB array, coinB pos in coinA array)
        if (_coinA < _coinB) {
            coinSwapIndexes[_key] = (coinAPos << 128) + coinBPos;
        } else {
            coinSwapIndexes[_key] = (coinBPos << 128) + coinAPos;
        }
    }

    function _unregisterCoin(address _coin) internal {
        _coinInfoMap[_coin].registerCount -= 1;
        if (_coinInfoMap[_coin].registerCount == 0) {
            uint256 _coinCount = coinList.length - 1;
            uint256 index = _coinInfoMap[_coin].index;

            if (index < _coinCount) {
                address coinB = coinList[_coinCount];
                coinList[index] = coinB;
                _coinInfoMap[coinB].index = SafeCast.toUint128(index);
            }
            delete _coinInfoMap[_coin].index;
            delete coinList[_coinCount];
            coinList.pop();
        }
    }

    /// @param _coinBIndex the index of _coinB in _coinA's array of unique coin's
    function _unregisterCoinPair(
        address _coinA,
        address _coinB,
        uint256 _coinBIndex
    ) internal {
        require(_coinInfoMap[_coinA].swapFor[_coinBIndex] == _coinB);

        // retrieve the last currently occupied index in coinA's array
        uint256 coinAArrLastIdx = _coinInfoMap[_coinA].swapFor.length - 1;

        // if coinB's index in coinA's array is less than the last
        // overwrite it's position with the last coin
        if (_coinBIndex < coinAArrLastIdx) {
            // here's our last coin in coinA's array
            address coinC = _coinInfoMap[_coinA].swapFor[coinAArrLastIdx];
            // get the bitwise_xor of the pair to retrieve their indexes
            uint256 key = (uint256(uint160(_coinA)) ^ uint256(uint160(coinC)));
            uint256 indexes = coinSwapIndexes[key];

            // update the pairing's indexes
            if (_coinA < coinC) {
                // least complicated most readable way of shifting twice to remove the lower order bits
                coinSwapIndexes[key] = ((indexes >> 128) << 128) + _coinBIndex;
            } else {
                coinSwapIndexes[key] = (_coinBIndex << 128) + (indexes % 2**128);
            }
            // set _coinBIndex in coinA's array to coinC
            _coinInfoMap[_coinA].swapFor[_coinBIndex] = coinC;
        }

        _coinInfoMap[_coinA].swapFor[coinAArrLastIdx] = address(0);
        _coinInfoMap[_coinA].swapFor.pop();
    }

    function _removeMarket(
        address _pool,
        address _coinA,
        address _coinB
    ) internal {
        uint256 key = (uint256(uint160(_coinA)) ^ uint256(uint160(_coinB)));
        uint256 length = marketCounts[key] - 1;
        if (length == 0) {
            uint256 indexes = coinSwapIndexes[key];
            if (_coinA < _coinB) {
                _unregisterCoinPair(_coinA, _coinB, indexes % 2**128);
                _unregisterCoinPair(_coinB, _coinA, indexes >> 128);
            } else {
                _unregisterCoinPair(_coinA, _coinB, indexes >> 128);
                _unregisterCoinPair(_coinB, _coinA, indexes % 2**128);
            }
            delete coinSwapIndexes[key];
        }
        for (uint256 i = 0; i < length + 1; i++) {
            if (markets[key][i] == _pool) {
                if (i < length) {
                    markets[key][i] = markets[key][length];
                }
                delete markets[key][length];
                marketCounts[key] = length;
                break;
            }
        }
    }

    function _getBalances(address _pool) internal view returns (uint256[] memory) {
        PoolInfo memory _poolInfo = _poolInfoMap[_pool];
        uint256 nCoins = _poolInfo.nCoins;
        uint256[] memory balances = new uint256[](nCoins);
        for (uint256 i = 0; i < nCoins; i++) {
            balances[i] = II4ISwapPool(_pool).balances(i);
        }
        return balances;
    }

    /// @notice Find an available pool for exchanging two coins
    /// @param _from Address of coin to be sent
    /// @param _to Address of coin to be received
    /// @param i Index value. When multiple pools are available
    ///     this value is used to return the n'th address.
    /// @return Pool address
    function findPoolForCoins(
        address _from,
        address _to,
        uint256 i
    ) external view returns (address) {
        uint256 key = (uint256(uint160(_from)) ^ uint256(uint160(_to)));
        return markets[key][i];
    }

    /// @notice Get the number of coins in a pool
    /// @dev For non-metapools, both returned values are identical
    ///     even when the pool does not use wrapping/lending
    /// @param _pool Pool address
    /// @return Number of wrapped coins, number of underlying coins
    function getNCoins(address _pool) external view returns (uint256) {
        return _poolInfoMap[_pool].nCoins;
    }

    /// @notice Get the coins within a pool
    /// @dev For pools using lending, these are the wrapped coin addresses
    /// @param _pool Pool address
    /// @return List of coin addresses
    function getCoins(address _pool) external view returns (address[] memory) {
        uint256 nCoins = _poolInfoMap[_pool].nCoins;
        address[] memory coins = new address[](nCoins);
        for (uint256 i = 0; i < nCoins; i++) {
            coins[i] = _poolInfoMap[_pool].coins[i];
        }
        return coins;
    }

    /// @notice Get decimal places for each coin within a pool
    /// @dev For pools using lending, these are the wrapped coin decimal places
    /// @param _pool Pool address
    /// @return uint256 list of decimals
    function getDecimals(address _pool) external view override returns (uint256[] memory) {
        // decimals are tightly packed as a series of uint8 within a little-endian bytes32
        // the packed value is stored as uint256 to simplify unpacking via shift and modulo
        uint64 nCoins = _poolInfoMap[_pool].nCoins;
        uint256 packed = _poolInfoMap[_pool].decimals;
        uint256[] memory decimals = new uint256[](nCoins);
        for (uint256 i = 0; i < nCoins; i++) {
            decimals[i] = (packed >> (8 * i)) % 256;
        }

        return decimals;
    }

    /// @notice Get balances for each coin within a pool
    /// @dev For pools using lending, these are the wrapped coin balances
    /// @param _pool Pool address
    /// @return uint256 list of balances
    function getBalances(address _pool) external view returns (uint256[] memory) {
        return _getBalances(_pool);
    }

    /// @notice Get the virtual price of a pool LP token
    /// @param _token LP token address
    /// @return uint256 Virtual price
    function getVirtualPriceFromLpToken(address _token) external view returns (uint256) {
        return II4ISwapPool(getPoolFromLpToken[_token]).getVirtualPrice();
    }

    function getA(address _pool) external view returns (uint256) {
        return II4ISwapPool(_pool).A();
    }

    function getGamma(address _cryptoPool) external view returns (uint256) {
        if (_poolInfoMap[_cryptoPool].poolType != 3) revert WrongPoolType();
        return ICryptoSwap2Pool(_cryptoPool).gamma();
    }

    /// @notice Get the fees for a pool
    /// @dev Fees are expressed as integers
    /// @return Pool fee as uint256 with 1e10 precision
    ///     Admin fee as 1e10 percentage of pool fee
    ///     Mid fee
    ///     Out fee
    function getFees(address _pool) external view returns (uint256[] memory) {
        bool isCryptoPool = _poolInfoMap[_pool].poolType == 3;
        uint256[] memory result = new uint256[](isCryptoPool ? 4 : 2);
        result[0] = II4ISwapPool(_pool).fee();
        result[1] = II4ISwapPool(_pool).adminFee();
        if (isCryptoPool) {
            result[2] = ICryptoSwap2Pool(_pool).midFee();
            result[3] = ICryptoSwap2Pool(_pool).outFee();
        }
        return result;
    }

    /// @notice Get the current admin balances (uncollected fees) for a pool
    /// @param _pool Pool address
    /// @return List of uint256 admin balances
    function getAdminBalances(address _pool) external view returns (uint256[] memory) {
        PoolInfo memory _poolInfo = _poolInfoMap[_pool];
        if (_poolInfo.poolType == 3) revert WrongPoolType();
        uint256[] memory balances = _getBalances(_pool);
        uint256 nCoins = _poolInfo.nCoins;
        for (uint256 i = 0; i < nCoins; i++) {
            address coin = _poolInfo.coins[i];
            if (coin == KLAY_ADDRESS) {
                balances[i] = _pool.balance - balances[i];
            } else {
                balances[i] = IKIP7(coin).balanceOf(_pool) - balances[i];
            }
        }
        return balances;
    }

    /// @notice Convert coin addresses to indices for use with pool methods
    /// @param _from Coin address to be used as `i` within a pool
    /// @param _to Coin address to be used as `j` within a pool
    /// @return int128 `i`, int128 `j`, boolean indicating if `i` and `j` are underlying coins
    function getCoinIndices(
        address _pool,
        address _from,
        address _to
    ) external view returns (uint256, uint256) {
        // the return value is stored as `uint256[3]` to reduce gas costs
        // from index, to index, is the market underlying?
        uint256[2] memory result;
        bool foundMarket = false;

        // check coin markets
        uint256 nCoins = _poolInfoMap[_pool].nCoins;
        for (uint256 x = 0; x < nCoins; x++) {
            address coin = _poolInfoMap[_pool].coins[x];
            if (coin == _from) {
                result[0] = x;
            } else if (coin == _to) {
                result[1] = x;
            } else {
                continue;
            }
            if (foundMarket) {
                // the second time we find a match, break out of the loop
                return (result[0], result[1]);
            }
            // the first time we find a match, set `found_market` to True
            foundMarket = true;
        }
        revert("No available market");
    }

    /// @notice Get the given name for a pool
    /// @param _pool Pool address
    /// @return The name of a pool
    function getPoolName(address _pool) external view returns (string memory) {
        return _poolInfoMap[_pool].name;
    }

    /// @notice Get the number of unique coins available to swap `_coin` against
    /// @param _coin Coin address
    /// @return The number of unique coins available to swap for
    function getCoinSwapCount(address _coin) external view returns (uint256) {
        return _coinInfoMap[_coin].swapFor.length;
    }

    /// @notice Get the coin available to swap against `_coin` at `_index`
    /// @param _coin Coin address
    /// @param _index An index in the `_coin`'s set of available counter
    ///     coin's
    /// @return Address of a coin available to swap against `_coin`
    function getCoinSwapComplement(address _coin, uint256 _index) external view returns (address) {
        return _coinInfoMap[_coin].swapFor[_index];
    }

    function poolCount() external view returns (uint256) {
        return poolList.length;
    }

    function coinCount() external view returns (uint256) {
        return coinList.length;
    }

    function getPoolList() external view override returns (address[] memory) {
        return poolList;
    }

    function getCoinList() external view returns (address[] memory) {
        return coinList;
    }

    function getPoolInfo(address _pool) external view override returns (PoolInfo memory) {
        return _poolInfoMap[_pool];
    }

    function getAllPoolInfos() external view returns (address[] memory, PoolInfo[] memory) {
        uint256 length = poolList.length;
        PoolInfo[] memory result = new PoolInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = _poolInfoMap[poolList[i]];
        }
        return (poolList, result);
    }

    function getCoinInfo(address _coin) external view returns (CoinInfo memory) {
        return _coinInfoMap[_coin];
    }
}
