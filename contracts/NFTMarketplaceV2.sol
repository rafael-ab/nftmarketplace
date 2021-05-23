// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./NFTMarketplaceV1.sol";
import "./interfaces/NFT20/INFT20Factory.sol";
import "./interfaces/NFT20/INFT20Pair.sol";
import "./interfaces/UniswapV2/IUniswapV2Router.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title An upgraded version of NFT Marketplace Contract
 * @author Rafael Romero
 */
contract NFTMarketplaceV2 is NFTMarketplaceV1 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /**
     * @notice Accepts an offer of an ERC-1155 Token using NFT-721.
     * @param _seller Address of the seller
     * @param _sellerTokenId ID of the token of the seller
     * @param _buyerNFTAddress Address of the buyer NFT provider
     * @param _buyerTokenId ID of the token of the buyer for payment
     * @param _tokenPayment Address of the ERC-20 Token
     */
    function acceptOfferWithNFT(
        address _seller,
        uint256 _sellerTokenId,
        address _buyerNFTAddress,
        uint256 _buyerTokenId,
        address _tokenPayment
    ) external {
        _acceptOfferWithNFT(
            _seller,
            _sellerTokenId,
            _buyerNFTAddress,
            _buyerTokenId,
            _tokenPayment
        );
    }

    /**
     * @dev Accepts an offer of an ERC-1155 Token using NFT-721.
     * @param _seller Address of the seller
     * @param _sellerTokenId ID of the token of the seller
     * @param _buyerNFTAddress Address of the buyer NFT provider
     * @param _buyerTokenId ID of the token of the buyer for payment
     * @param _tokenPayment Address of the ERC-20 Token
     *
     * Emits a {NFTMarketplaceV1-OfferAccepted} event.
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_sellerTokenId` must be greater than zero.
     * - `_buyerNFTAddress` cannot be the zero address.
     * - `_buyerTokenId` must be greater than zero.
     * - `_tokenPayment` cannot be the zero address and must be a
     * valid ERC-20 Token address.
     */
    function _acceptOfferWithNFT(
        address _seller,
        uint256 _sellerTokenId,
        address _buyerNFTAddress,
        uint256 _buyerTokenId,
        address _tokenPayment
    ) internal {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_buyerNFTAddress != address(0), "NFTMarketplace: ZERO_ADDRESS");
        require(_tokenPayment != address(0), "NFTMarketplace: ZERO_ADDRESS");
        require(_sellerTokenId > 0, "NTFMarketplace: ID_ERROR");
        require(_buyerTokenId > 0, "NFTMarketplace: ID_ERROR");

        Offer storage offer = offers[_seller][_sellerTokenId];
        if (offer.deadline < block.timestamp) {
            offer.status = OfferStatus.CANCELLED;
        }
        require(
            offer.status == OfferStatus.ONGOING,
            "NFTMarketplace: This offer is already cancelled or accepted"
        );
        
        // swap in NFT20 an NFT to Tokens
        bool success = _swapNFTToTokens(
            _seller,
            _sellerTokenId,
            _buyerNFTAddress, 
            _buyerTokenId,
            _tokenPayment
        );
        require(success, "NFTMarketplace: NFT_SWAP_ERROR");

        uint256 tokenPrice;
        uint256 tokenDecimals = IERC20(_tokenPayment).decimals();

        if (tokenDecimals > 8) {
            // the price in USD has 8 decimals,
            // so we calculate the decimals with 10 ** (tokenDecimals - 8)
            // to get to 18 decimals
            tokenPrice = _getPriceByToken(_tokenPayment).mul(
                10**(tokenDecimals.sub(8))
            );
        } else {
            // the price in USD has 8 decimals,
            // so we need to get the same decimals that tokenDecimals
            // we calculate that with 8 - tokenDecimals
            uint256 usdDecimals = 8;
            uint256 priceDivider = 10**(usdDecimals.sub(tokenDecimals));
            // and divide the token price by that amount
            tokenPrice = _getPriceByToken(_tokenPayment).div(priceDivider);
        }
        // multiply tokenDecimals by 2 to maintain precision in the next divide
        uint256 priceUSD = offer.priceUSD.mul(10**(tokenDecimals * 2));

        uint256 finalAmount = priceUSD.div(tokenPrice);
        uint256 fees = finalAmount.div(fee);

        require(
            IERC20(_tokenPayment).balanceOf(address(this)) >=
                finalAmount,
            "NTFMarketplace: INSUFFICIENT_AMOUNT"
        );

        offer.status = OfferStatus.ACCEPTED;

        // transfer tokens to the seller
        IERC20(_tokenPayment).safeTransfer(
            _seller,
            finalAmount.sub(fees)
        );

        require(
            IERC1155(offer.token).isApprovedForAll(_seller, address(this)),
            "NTFMarketplace: NOT_APPROVAL"
        );

        // transfer tokens to buyer
        IERC1155(offer.token).safeTransferFrom(
            _seller,
            _msgSender(),
            offer.tokenId,
            offer.amount,
            ""
        );

        IERC20(_tokenPayment).safeTransfer(feeRecipient, fees);

        IERC20(_tokenPayment).safeTransfer(
            _msgSender(), 
            IERC20(_tokenPayment).balanceOf(address(this))
        );

        emit OfferAccepted(
            _msgSender(),
            _seller,
            _sellerTokenId,
            offer.amount,
            offer.priceUSD
        );
    }

    /**
     * @dev Swaps an NFT to ERC-20 Tokens.
     * @param _seller Address of the seller
     * @param _sellerTokenId ID of the token of the seller
     * @param _buyerNFTAddress Address of the buyer NFT provider
     * @param _buyerTokenId ID of the token of the buyer for payment
     * @param _tokenPayment Address of the ERC-20 Token
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_sellerTokenId` must be greater than zero.
     * - `_buyerNFTAddress` cannot be the zero address.
     * - `_buyerTokenId` must be greater than zero.
     * - `_tokenPayment` cannot be the zero address and must be a
     * valid ERC-20 Token address.
     */
    function _swapNFTToTokens(
        address _seller,
        uint256 _sellerTokenId,
        address _buyerNFTAddress,
        uint256 _buyerTokenId,
        address _tokenPayment
    ) internal returns (bool) {
        require(_buyerNFTAddress != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_buyerTokenId > 0, "NTFMarketplace: ID_ERROR");

        Offer memory _offer = offers[_seller][_sellerTokenId];

        INFT20Factory factory = INFT20Factory(0x0f4676178b5c53Ae0a655f1B19A96387E4b8B5f2);
        address nftAddress = factory.nftToToken(_buyerNFTAddress);
        require(nftAddress != address(0), "NFTMarketplace: NFT20_ZERO_ADDRESS");

        INFT20Pair pair = INFT20Pair(nftAddress);
        if (pair.nftType() == 1155) {
            require(_offer.tokenId > 0, "NTFMarketplace: ID_ERROR");
            require(_offer.amount > 0, "NFTMarketplace: ZERO_AMOUNT");
            IERC1155(_buyerNFTAddress).safeTransferFrom(
                _msgSender(), 
                nftAddress, 
                _buyerTokenId, 
                1, 
                ""
            );
        } else {
            IERC721(_buyerNFTAddress).safeTransferFrom(_msgSender(), nftAddress, _buyerTokenId);
        }

        uint256 balance = IERC20(nftAddress).balanceOf(address(this));

        IUniswapV2Router router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        IERC20(nftAddress).approve(address(router), balance);
        // path is nftAddress => WETH => _tokenPayment
        address[] memory path = new address[](3);
        path[0] = nftAddress;
        // weth address
        path[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        path[2] = _tokenPayment;
        router.swapExactTokensForTokens(
            balance,
            1,
            path,
            address(this),
            _offer.deadline
        );

        return true;
    }

    /**
     * @notice Creates an offer of an ERC-721 Token.
     *
     * Emits a {NFTMarketplaceV1-OfferCreated} event.
     *
     * Requirements:
     *
     * - `_token` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     * - `_deadline` must be greater than the current `block.timestamp`.
     * - `_priceUSD` must be greater than zero.
     */
    function createOfferERC721(
        address _token,
        uint256 _tokenId,
        uint256 _deadline,
        uint256 _priceUSD
    ) external {
        _createOffer(_token, _tokenId, 1, _deadline, _priceUSD);
    }

    /**
     * @notice Accepts an offer of an ERC-721 Token using ERC-20 Tokens.
     * @dev See {_acceptOfferERC721WithTokens} for more details.
     * @param _seller Address of the seller
     * @param _tokenId ID of the token
     * @param _amount Amount of the token 
     * @param _tokenPayment Address of the ERC-20 Token
     */
    function acceptOfferERC721WithTokens(
        address _seller,
        uint256 _tokenId,
        uint256 _amount,
        address _tokenPayment
    ) external {
        _acceptOfferERC721WithTokens(_seller, _tokenId, _amount, _tokenPayment);
    }

    /**
     * @dev Accepts an offer of an ERC-721 Token using ERC-20 Tokens.
     *
     * Emits a {NFTMarketplaceV1-OfferAccepted} event.
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     * - `_amount` must be greater than zero.
     * - `_tokenPayment` cannot be the zero address and must be a
     * valid ERC-20 Token address.
     */
    function _acceptOfferERC721WithTokens(
        address _seller,
        uint256 _tokenId,
        uint256 _amount,
        address _tokenPayment
    ) internal {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");
        require(_amount > 0, "NFTMarketplace: ZERO_AMOUNT");
        require(
            _whitelistedERC20[_tokenPayment],
            "NFTMarketplace: TOKEN_NOT_ALLOWED"
        );

        Offer storage offer = offers[_seller][_tokenId];
        require(offer.amount == 1, "NFTMarketplace: INVALID_ERC721");
        if (offer.deadline < block.timestamp) {
            offer.status = OfferStatus.CANCELLED;
        }
        require(
            offer.status == OfferStatus.ONGOING,
            "NFTMarketplace: This offer is already cancelled or accepted"
        );

        uint256 tokenPrice;
        uint256 tokenDecimals = IERC20(_tokenPayment).decimals();

        if (tokenDecimals > 8) {
            // the price in USD has 8 decimals,
            // so we calculate the decimals with 10 ** (tokenDecimals - 8)
            // to get to 18 decimals
            tokenPrice = _getPriceByToken(_tokenPayment).mul(
                10**(tokenDecimals.sub(8))
            );
        } else {
            // the price in USD has 8 decimals,
            // so we need to get the same decimals that tokenDecimals
            // we calculate that with 8 - tokenDecimals
            uint256 usdDecimals = 8;
            uint256 priceDivider = 10**(usdDecimals.sub(tokenDecimals));
            // and divide the token price by that amount
            tokenPrice = _getPriceByToken(_tokenPayment).div(priceDivider);
        }
        // multiply tokenDecimals by 2 to maintain precision in the next divide
        uint256 priceUSD = offer.priceUSD.mul(10**(tokenDecimals * 2));

        uint256 finalAmount = priceUSD.div(tokenPrice);
        uint256 fees = finalAmount.div(fee);

        offer.status = OfferStatus.ACCEPTED;

        require(
            IERC20(_tokenPayment).allowance(_msgSender(), address(this)) >=
                finalAmount,
            "NTFMarketplace: INSUFFICIENT_ALLOWANCE"
        );

        // transfer tokens to the seller
        IERC20(_tokenPayment).transferFrom(
            _msgSender(),
            _seller,
            finalAmount.sub(fees)
        );

        require(
            IERC721(offer.token).isApprovedForAll(_seller, address(this)),
            "NTFMarketplace: NOT_APPROVAL"
        );

        // transfer tokens to buyer
        IERC721(offer.token).safeTransferFrom(
            _seller,
            _msgSender(),
            offer.tokenId,
            ""
        );

        IERC20(_tokenPayment).transferFrom(_msgSender(), feeRecipient, fees);

        emit OfferAccepted(_msgSender(), _seller, _tokenId, 1, offer.priceUSD);
    }

    /**
     * @notice Accepts an offer of an ERC-721 Token using ETH.
     * @dev See {_acceptOfferERC721WithETH} for more details.
     * @param _seller Address of the seller
     * @param _tokenId ID of the token
     */
    function acceptOfferERC721WithETH(address _seller, uint256 _tokenId)
        external
        payable
    {
        _acceptOfferERC721WithETH(_seller, _tokenId);
    }

    /**
     * @dev Accepts an offer of an ERC-721 Token using ETH.
     * @param _seller Address of the seller
     * @param _tokenId ID of the token
     *
     * Emits a {NFTMarketplaceV1-OfferAccepted} event.
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     */
    function _acceptOfferERC721WithETH(address _seller, uint256 _tokenId)
        internal
    {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");

        uint256 amount = msg.value;
        require(amount > 0, "NFTMarketplace: ZERO_AMOUNT");

        Offer storage offer = offers[_seller][_tokenId];
        require(offer.amount == 1, "NFTMarketplace: INVALID_ERC721");
        if (offer.deadline < block.timestamp) {
            offer.status = OfferStatus.CANCELLED;
        }
        require(
            offer.status == OfferStatus.ONGOING,
            "NFTMarketplace: This offer is already cancelled or accepted"
        );

        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        // the price in USD has 8 decimals, so multiply by 10 ** 10 to get to 18 decimals
        uint256 tokenPrice = _getPriceByToken(weth).mul(10**10);
        // add 18 twice to maintain precision in the next divide
        uint256 priceUSD = offer.priceUSD.mul(10**(18 + 18));

        uint256 finalAmount = priceUSD.div(tokenPrice);
        require(amount >= finalAmount, "NFTMarketplace: INSUFFICIENT_AMOUNT");

        uint256 fees = finalAmount.div(fee);

        offer.status = OfferStatus.ACCEPTED;

        // transfer eth to seller
        payable(_seller).transfer(finalAmount.sub(fees));

        require(
            IERC721(offer.token).isApprovedForAll(_seller, address(this)),
            "NTFMarketplace: NOT_APPROVAL"
        );
        // transfer tokens to buyer
        IERC721(offer.token).safeTransferFrom(
            _seller,
            _msgSender(),
            offer.tokenId,
            ""
        );

        //send fees to the recipient
        payable(feeRecipient).transfer(fees);
        // refund to sender
        payable(_msgSender()).transfer(address(this).balance);

        emit OfferAccepted(_msgSender(), _seller, _tokenId, 1, offer.priceUSD);
    }
}
