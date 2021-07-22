// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";

contract MockRouter is IUniswapV3MintCallback, IUniswapV3SwapCallback {
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    function mint(
        IUniswapV3Pool pool,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external returns (uint256, uint256) {
        return
            pool.mint(
                msg.sender,
                tickLower,
                tickUpper,
                amount,
                abi.encode(msg.sender)
            );
    }

    function getSwapResult(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    )
        external
        returns (
            int256 amount0Delta,
            int256 amount1Delta,
            uint160 nextSqrtRatio
        )
    {
        (amount0Delta, amount1Delta) = IUniswapV3Pool(pool).swap(
            msg.sender,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );

        (nextSqrtRatio, , , , , , ) = IUniswapV3Pool(pool).slot0();
    }

    function swapExact0For1(
        address pool,
        uint256 amount0In,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IUniswapV3Pool(pool).swap(
            recipient,
            true,
            amount0In.toInt256(),
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
    }

    function swap0ForExact1(
        address pool,
        uint256 amount1Out,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IUniswapV3Pool(pool).swap(
            recipient,
            true,
            -amount1Out.toInt256(),
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
    }

    function swapExact1For0(
        address pool,
        uint256 amount1In,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IUniswapV3Pool(pool).swap(
            recipient,
            false,
            amount1In.toInt256(),
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
    }

    function swap1ForExact0(
        address pool,
        uint256 amount0Out,
        address recipient,
        uint160 sqrtPriceLimitX96
    ) external {
        IUniswapV3Pool(pool).swap(
            recipient,
            false,
            -amount0Out.toInt256(),
            sqrtPriceLimitX96,
            abi.encode(msg.sender)
        );
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));
        if (amount0Owed > 0)
            IERC20(IUniswapV3Pool(msg.sender).token0()).transferFrom(
                sender,
                msg.sender,
                amount0Owed
            );
        if (amount1Owed > 0)
            IERC20(IUniswapV3Pool(msg.sender).token1()).transferFrom(
                sender,
                msg.sender,
                amount1Owed
            );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata data
    ) external override {
        address sender = abi.decode(data, (address));

        if (amount0Delta > 0) {
            IERC20(IUniswapV3Pool(msg.sender).token0()).transferFrom(
                sender,
                msg.sender,
                uint256(amount0Delta)
            );
        } else if (amount1Delta > 0) {
            IERC20(IUniswapV3Pool(msg.sender).token1()).transferFrom(
                sender,
                msg.sender,
                uint256(amount1Delta)
            );
        } else {
            // if both are not gt 0, both must be 0.
            assert(amount0Delta == 0 && amount1Delta == 0);
        }
    }
}
