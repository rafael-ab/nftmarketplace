// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./NFTMarketplaceV1.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title An upgraded version of NFT Marketplace Contract
 * @author Rafael Romero
 *
 * IMPORTANT: This contract only supports pay with token using ERC-20 Standard.
 * That is, you cannot pay using USDT (Tether) because this token not follows
 * the ERC-20 Standard.
 */
contract NFTMarketplaceV2 is NFTMarketplaceV1 {
    using SafeMath for uint256;

    /**
     * @dev Creates an offer of an ERC-721 Token.
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
     * @dev See {_acceptOfferERC721WithTokens}.
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
     * @dev See {_acceptOfferERC721WithETH}
     */
    function acceptOfferERC721WithETH(address _seller, uint256 _tokenId)
        external
        payable
    {
        _acceptOfferERC721WithETH(_seller, _tokenId);
    }

    /**
     * @dev Accepts an offer of an ERC-721 Token using ETH.
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
