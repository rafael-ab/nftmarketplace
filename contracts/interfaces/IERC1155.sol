//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IERC1155 {
    function isApprovedForAll(address account, address operator) external view returns (bool);
    function setApprovalForAll(address operator, bool approved) external;
    function safeTransferFrom(
        address from, 
        address to, 
        uint256 id, 
        uint256 amount, 
        bytes calldata data
    ) external;
    function balanceOf(address account, uint256 id) external view returns (uint256);
}
