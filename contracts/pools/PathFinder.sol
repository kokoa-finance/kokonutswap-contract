// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../library/Pausable.sol";
import "../library/kip/IKIP7.sol";
import "../interface/IMetaPool.sol";
import "../library/openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interface/ICryptoSwap2Pool.sol";

contract PathFinder is Pausable, ReentrancyGuard {
    event SwapWithPath(address user, address inputToken, uint256 inputAmount, address outputToken, uint256 outputAmount);

    address private constant KLAY_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    mapping(address => mapping(address => bool)) public isApproved;

    function __PathFinder_init() public initializer {
        __Pausable_init();
    }

    function getDy(
        address[] calldata _path,
        uint256[3][] calldata _swapParams,
        uint256 _amount
    ) external view returns (uint256[] memory) {
        return _getDy(_path, _swapParams, _amount, false);
    }

    function getDyWithoutFee(
        address[] calldata _path,
        uint256[3][] calldata _swapParams,
        uint256 _amount
    ) external view returns (uint256[] memory) {
        return _getDy(_path, _swapParams, _amount, true);
    }

    /// @notice Perform up to multiple swaps in a single transaction
    /// @dev Routing and swap params must be determined off-chain. This
    ///      functionality is designed for gas efficiency over ease-of-use.
    /// @param _path Array of [initial token, pool, token, pool, token, ...]
    ///               The array is iterated until a pool address of 0x00, then the last
    ///               given token is transferred to `_receiver`
    /// @param _swapParams Multidimensional array of [i, j, swap type] where i and j are the correct
    ///                     values for the n'th pool in `_route`. The swap type should be 1 for
    ///                     a stableswap `exchange`, 2 for stableswap `exchange_underlying` and 3
    ///                     for a cryptoswap `exchange`.
    /// @param _amount The amount of input token.
    /// @return _outputs The array of the amount of all output tokens through the _path
    function _getDy(
        address[] calldata _path,
        uint256[3][] calldata _swapParams,
        uint256 _amount,
        bool withoutFee
    ) internal view returns (uint256[] memory _outputs) {
        address inputToken = _path[0];
        address outputToken = address(0);
        _outputs = new uint256[](_path.length / 2);

        for (uint256 i = 1; i < _path.length / 2 + 1; i++) {
            // 4 rounds of iteration to perform up to 4 swaps
            address swap = _path[i * 2 - 1];
            if (swap == address(0)) {
                break;
            }
            outputToken = _path[i * 2];
            uint256[3] memory params = _swapParams[i - 1]; // i, j, swap type

            if (params[2] == 1) {
                _outputs[i - 1] = withoutFee
                    ? IStableSwap(swap).getDyWithoutFee(params[0], params[1], _amount)
                    : IStableSwap(swap).getDy(params[0], params[1], _amount);
            } else if (params[2] == 2) {
                _outputs[i - 1] = withoutFee
                    ? IMetaPool(swap).getDyUnderlyingWithoutFee(params[0], params[1], _amount)
                    : IMetaPool(swap).getDyUnderlying(params[0], params[1], _amount);
            } else if (params[2] == 3) {
                _outputs[i - 1] = withoutFee
                    ? ICryptoSwap2Pool(swap).getDyWithoutFee(params[0], params[1], _amount)
                    : ICryptoSwap2Pool(swap).getDy(params[0], params[1], _amount);
            } else {
                revert("Bad swap type");
            }

            // sanity check, if the routing data is incorrect we will have a 0 balance and that is bad
            require(_amount != 0, "Received nothing");

            // if there is another swap, the output token becomes the input for the next round
            _amount = _outputs[i - 1];
            inputToken = outputToken;
        }
    }

    /// @notice Perform up to multiple swaps in a single transaction
    /// @dev Routing and swap params must be determined off-chain. This
    ///      functionality is designed for gas efficiency over ease-of-use.
    /// @param _path Array of [initial token, pool, token, pool, token, ...]
    ///               The array is iterated until a pool address of 0x00, then the last
    ///               given token is transferred to `msg.sender`
    /// @param _swapParams Multidimensional array of [i, j, swap type] where i and j are the correct
    ///                     values for the n'th pool in `_route`. The swap type should be 1 for
    ///                     a stableswap `exchange`, 2 for stableswap `exchange_underlying` and 3
    ///                     for a cryptoswap `exchange`.
    /// @param _amount The amount of input token.
    /// @param _minAmount The minimum amount received after the final swap.
    /// @return _outputs The array of the amount of all output tokens through the _path
    function swapWithPath(
        address[] calldata _path,
        uint256[3][] calldata _swapParams,
        uint256 _amount,
        uint256 _minAmount
    ) external payable whenNotPaused nonReentrant returns (uint256[] memory _outputs) {
        address curInputToken = _path[0];
        address curOutputToken = address(0);
        uint256 inputAmount = _amount;
        _outputs = new uint256[](_path.length / 2);

        if (curInputToken == KLAY_ADDRESS) {
            require(msg.value == _amount);
        } else {
            require(msg.value == 0);
            IKIP7(curInputToken).transferFrom(msg.sender, address(this), _amount);
        }

        for (uint256 i = 1; i < _path.length / 2 + 1; i++) {
            // 4 rounds of iteration to perform up to 4 swaps
            address swap = _path[i * 2 - 1];
            if (swap == address(0)) {
                break;
            }
            curOutputToken = _path[i * 2];
            uint256[3] memory params = _swapParams[i - 1]; // i, j, swap type
            if (!isApproved[curInputToken][swap] && curInputToken != KLAY_ADDRESS) {
                // approve the pool to transfer the input token
                IKIP7(curInputToken).approve(swap, type(uint256).max);
            }

            if (params[2] == 1) {
                uint256 klayAmount = 0;
                if (curInputToken == KLAY_ADDRESS) {
                    klayAmount = _amount;
                }
                _outputs[i - 1] = IStableSwap(swap).exchange{value: klayAmount}(params[0], params[1], _amount, 0);
            } else if (params[2] == 2) {
                _outputs[i - 1] = IMetaPool(swap).exchangeUnderlying(params[0], params[1], _amount, 0);
            } else if (params[2] == 3) {
                uint256 klayAmount = 0;
                if (curInputToken == KLAY_ADDRESS) {
                    klayAmount = _amount;
                }
                _outputs[i - 1] = ICryptoSwap2Pool(swap).exchange{value: klayAmount}(params[0], params[1], _amount, 0);
            } else {
                revert("Bad swap type");
            }

            // update the amount received
            if (curOutputToken == KLAY_ADDRESS) {
                _amount = address(this).balance;
            } else {
                _amount = IKIP7(curOutputToken).balanceOf(address(this));
            }

            // sanity check, if the routing data is incorrect we will have a 0 balance and that is bad
            require(_amount != 0, "Received nothing");

            // if there is another swap, the output token becomes the input for the next round
            curInputToken = curOutputToken;
        }

        // validate the final amount received
        require(_amount >= _minAmount);
        require(curOutputToken == _path[_path.length - 1], "wrong output");

        // transfer the final token to the msg.sender
        if (curOutputToken == KLAY_ADDRESS) {
            (bool success, ) = msg.sender.call{value: _amount}("");
            require(success);
        } else {
            IKIP7(curOutputToken).transfer(msg.sender, _amount);
        }

        emit SwapWithPath(msg.sender, _path[0], inputAmount, curOutputToken, _amount);
    }

    receive() external payable {}
}
