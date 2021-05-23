// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface INFT20Pair {
    /**
     * @dev Burns ERC20 tokens to redeem ERC721/ERC1155 tokens from the pool.
     */
    function withdraw(
        uint256[] calldata _tokenIds,
        uint256[] calldata amounts,
        address receipient
    ) external;

    /**
     * @dev Deposits multiple ERC721 tokens in exchange for the pair’s ERC20 token in one transaction.
     */
    function multi721Deposit(
        uint256[] memory _ids, 
        address _referral
    ) external;

    /**
     * @dev Swaps an ERC721 token for a different ERC721 token in the pool.
     */
    function swap721(uint256 _in, uint256 _out) external;

    /**
     * @dev Swaps ERC1155 token(s) for different ERC115 token(s) in the pool.
     */
    function swap1155(
        uint256[] calldata in_ids,
        uint256[] calldata in_amounts,
        uint256[] calldata out_ids,
        uint256[] calldata out_amounts
    ) external;

    /**
     * @dev Returns the type of NFT held in this pair, 721 for ERC721 or 1155 for ERC1155.
     */
    function nftType() external returns (uint256);
}
