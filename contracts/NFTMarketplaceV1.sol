// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "./libraries/PriceTokenPairUSD.sol";

/// @title A NFT Marketplace Contract
/// @author Rafael Romero
contract NFTMarketplace is Initializable, ContextUpgradeable, OwnableUpgradeable {
    using SafeMathUpgradeable for uint256;

    address payable public feeRecipient;
    uint256 public fee;
    mapping(address => bool) private _whitelistedERC20; 

    enum OfferStatus { ONGOING, CANCELLED }

    struct Offer {
        address seller;
        address token;
        uint256 tokenId;
        uint256 amount;
        uint256 deadline;
        uint256 priceUSD;
        OfferStatus status;
    }

    mapping(address => mapping(uint256 => Offer)) public offers;

    event OfferCreated(
        address indexed seller,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 deadline,
        uint256 priceUSD
    );

    event OfferAccepted(
        address indexed buyer,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 priceUSD
    );

    event OfferCancelled(
        address indexed seller,
        address indexed token,
        uint256 indexed tokenId
    );

    function initialize(
        address payable _feeRecipient, 
        uint256 _fee
    ) external initializer {
        require(_feeRecipient != address(0));
        require(_fee > 0);
        feeRecipient = _feeRecipient;
        fee = _fee;
    }

    function createOffer(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _deadline,
        uint256 _priceUSD
    ) external {
        require(_token != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(
            offers[_msgSender()][_tokenId].tokenId > 0, 
            "NFTMarketplace: DUPLICATE_TOKEN"
        );
        offers[_msgSender()][_tokenId] = Offer(
            _msgSender(),
            _token,
            _tokenId,
            _amount,
            _deadline,
            _priceUSD,
            OfferStatus.ONGOING
        );
        IERC1155(_token).setApprovalForAll(address(this), true);
        emit OfferCreated(
            _msgSender(), 
            _token,
            _tokenId,
            _amount, 
            _deadline, 
            _priceUSD
        );
    }

    function acceptOffer(
        address _seller,
        uint256 _tokenId,
        address _tokenPayment
    ) external payable {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");
        uint256 amount = msg.value;
        require(amount > 0, "NFTMarketplace: ZERO_AMOUNT");
        require(_whitelistedERC20[_tokenPayment], "NFTMarketplace: TOKEN_NOT_ALLOWED");

        Offer memory offer = offers[_seller][_tokenId];
        require(
            offer.status != OfferStatus.CANCELLED, 
            "NFTMarketplace: This offer is already cancelled"
        );

        uint256 tokenPrice = _getPriceByToken(_tokenPayment);
        uint256 finalAmount = offer.priceUSD.div(tokenPrice);
        require(amount >= finalAmount, "NFTMarketplace: INSUFFICIENT_AMOUNT");
        uint256 fees = finalAmount.div(fee);

        // transfer tokens to seller
        IERC20(_tokenPayment).approve(
            address(this), 
            finalAmount.sub(fees)
        );
        IERC20(_tokenPayment).transferFrom(
            _msgSender(), 
            _seller,
            finalAmount.sub(fees)
        );

        // transfer tokens to buyer
        IERC1155(offer.token).safeTransferFrom(
            address(this), 
            _msgSender(), 
            _tokenId, 
            offer.amount,
            ""
        );

        _msgSender().transfer(address(this).balance);
        feeRecipient.transfer(fees);
    }

    function cancelOffer(uint256 _tokenId) external {
        require(_tokenId > 0, "NFTMarketplace: ID_ERROR");

        Offer memory offer = offers[_msgSender()][_tokenId];
        require(
            offer.status != OfferStatus.CANCELLED, 
            "NFTMarketplace: This offer is already cancelled"
        );

        offer.status = OfferStatus.CANCELLED;
        emit OfferCancelled(offer.seller, offer.token, offer.tokenId);
    }

    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    function setFeeRecipient(address payable _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    function setWhitelistedPaymentToken(
        address _paymentToken
    ) external onlyOwner {
        _whitelistedERC20[_paymentToken] = true;
    }

    function _getPriceByToken(
        address _tokenPayment
    ) internal view returns (uint256) {
        require(_whitelistedERC20[_tokenPayment], "NFTMarketplace: TOKEN_NOT_ALLOWED");
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        address link = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        uint256 price;
        if (_tokenPayment == weth) {
            price = uint256(PriceTokenPairUSD.getETHPrice());
        } else if (_tokenPayment == dai) {
            price = uint256(PriceTokenPairUSD.getDAIPrice());
        } else if (_tokenPayment == link) {
            price = uint256(PriceTokenPairUSD.getLINKPrice());
        } else {
            revert();
        }
        return price;
    }
}
