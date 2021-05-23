//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IUniswapV2Router {
    function factory() external pure returns (address);

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}