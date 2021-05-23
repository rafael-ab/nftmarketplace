// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface INFT20Factory {
    /**
     * @dev Returns the NFT20Pair address for a supplied ERC721/ERC1155 contract address (if one exists).
     */
    function nftToToken(address) external returns (address);
}
