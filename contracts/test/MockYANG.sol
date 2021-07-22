// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "../interfaces/ICHIManager.sol";

contract MockYANG {
    using SafeERC20 for IERC20;

    address public chiManager;

    uint256 public totallyShares = 0;

    constructor() {}

    struct SubscribeParam {
        uint256 yangId;
        uint256 chiId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct UnSubscribeParam {
        uint256 yangId;
        uint256 chiId;
        uint256 shares;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    function setCHIManager(address _chiManager) external {
        chiManager = _chiManager;
    }

    function deposit(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external {
        require(amount0 > 0, "NZ");
        require(amount1 > 0, "NZ");
        IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0);
        IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1);
    }

    function withdraw(
        address token0,
        uint256 amount0,
        address token1,
        uint256 amount1
    ) external {
        require(amount0 > 0, "NZ");
        require(amount1 > 0, "NZ");
        IERC20(token0).safeTransfer(msg.sender, amount0);
        IERC20(token1).safeTransfer(msg.sender, amount1);
    }

    function subscribe(SubscribeParam memory params)
        external
        returns (uint256)
    {
        (, , address _pool, , , , , ) = ICHIManager(chiManager).chi(
            params.chiId
        );
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);
        IERC20(pool.token0()).safeApprove(chiManager, params.amount0Desired);
        IERC20(pool.token1()).safeApprove(chiManager, params.amount1Desired);
        (uint256 share, , ) = ICHIManager(chiManager).subscribe(
            params.yangId,
            params.chiId,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Min,
            params.amount1Min
        );
        IERC20(pool.token0()).safeApprove(chiManager, 0);
        IERC20(pool.token1()).safeApprove(chiManager, 0);
        totallyShares = totallyShares + share;
        return share;
    }

    function unsubscribe(UnSubscribeParam memory params) external {
        require(totallyShares >= params.shares, "insufficient shares");
        ICHIManager(chiManager).unsubscribe(
            params.yangId,
            params.chiId,
            params.shares,
            params.amount0Min,
            params.amount1Min
        );
        totallyShares -= params.shares;
    }
}
