// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(uint256 amountToMint) ERC20("MockERC20", "Mock") {
        _mint(msg.sender, amountToMint);
    }
}
