// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IERC20.sol";
import "hardhat/console.sol";

/**
 * @title A NFT Marketplace Contract
 * @author Rafael Romero
 */
contract NFTMarketplaceV1 is
    Initializable,
    ContextUpgradeable,
    OwnableUpgradeable
{
    using SafeMath for uint256;

    /**
     * @dev Returns the fee value that is taken from each transaction.
     */
    uint256 public fee;

    /**
     * @dev Returns the address who is holding the fees.
     */
    address payable public feeRecipient;

    // mapping of approved tokens for payment
    mapping(address => bool) private _whitelistedERC20;

    // mapping of token address for chainlink usd-token address
    mapping(address => address) private _chainlinkUSDToken;

    enum OfferStatus {ONGOING, ACCEPTED, CANCELLED}

    struct Offer {
        address seller;
        address token;
        uint256 tokenId;
        uint256 amount;
        uint256 deadline;
        uint256 priceUSD;
        OfferStatus status;
    }

    /**
     * @dev Returns the offer of a seller given a tokenId.
     */
    mapping(address => mapping(uint256 => Offer)) public offers;

    /**
     * @dev Emitted when `seller` creates a new offer of a ERC-1155 `token`
     * and its `tokenId`.
     */
    event OfferCreated(
        address indexed seller,
        address indexed token,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 deadline,
        uint256 priceUSD
    );

    /**
     * @dev Emitted when `buyer` accepts the offer of `seller`.
     */
    event OfferAccepted(
        address indexed buyer,
        address indexed seller,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 priceUSD
    );

    /**
     * @dev Emitted when `seller` cancels his offer.
     */
    event OfferCancelled(
        address indexed seller,
        address indexed token,
        uint256 indexed tokenId
    );

    /**
     * @dev Initializes the values for {feeRecipient} and {fee}.
     *
     * It is used to make the contract upgradeable.
     *
     * Requirements:
     *
     * - `_feeRecipient` cannot be the zero address.
     * - `_fee` must be greater than zero.
     */
    function initialize(address payable _feeRecipient, uint256 _fee)
        external
        initializer
    {
        require(_feeRecipient != address(0));
        require(_fee > 0);
        __Context_init();
        __Ownable_init();
        feeRecipient = _feeRecipient;
        fee = _fee;
    }

    /**
     * @dev Creates an offer of an ERC-1155 Token.
     *
     * Emits a {OfferCreated} event.
     *
     * Requirements:
     *
     * - `_token` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     * - `_amount` must be greater than zero.
     * - `_deadline` must be greater than the current `block.timestamp`.
     * - `_priceUSD` must be greater than zero.
     */
    function createOffer(
        address _token,
        uint256 _tokenId,
        uint256 _amount,
        uint256 _deadline,
        uint256 _priceUSD
    ) external {
        require(_token != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");
        require(_amount > 0, "NFTMarketplace: ZERO_AMOUNT");
        require(_deadline > block.timestamp, "NFTMarketplace: DEADLINE_ERROR");
        require(_priceUSD > 0, "NFTMarketplace: ZERO_PRICE_USD");

        offers[_msgSender()][_tokenId] = Offer(
            _msgSender(),
            _token,
            _tokenId,
            _amount,
            _deadline,
            _priceUSD,
            OfferStatus.ONGOING
        );
        emit OfferCreated(
            _msgSender(),
            _token,
            _tokenId,
            _amount,
            _deadline,
            _priceUSD
        );
    }

    /**
     * @dev Accepts an offer of an ERC-1155 Token using ERC-20 Tokens.
     *
     * Emits a {OfferAccepted} event.
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     * - `_amount` must be greater than zero.
     * - `_tokenPayment` cannot be the zero address and must be a
     * valid ERC-20 Token address.
     */
    function acceptOfferWithTokens(
        address _seller,
        uint256 _tokenId,
        uint256 _amount,
        address _tokenPayment
    ) external {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");
        require(_amount > 0, "NFTMarketplace: ZERO_AMOUNT");
        require(
            _whitelistedERC20[_tokenPayment],
            "NFTMarketplace: TOKEN_NOT_ALLOWED"
        );

        Offer storage offer = offers[_seller][_tokenId];
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
            tokenPrice = _getPriceByToken(_tokenPayment).mul(10**(tokenDecimals.sub(8)));
        } else {
            // the price in USD has 8 decimals,
            // so we need to get the same decimals that tokenDecimals
            // we calculate that with 8 - tokenDecimals
            uint256 usdDecimals = 8;
            uint256 priceDivider = 10 ** (usdDecimals.sub(tokenDecimals));
            // and divide the token price by that amount
            tokenPrice = _getPriceByToken(_tokenPayment).div(priceDivider);
        }
        // multiply tokenDecimals by 2 to maintain precision in the next divide
        uint256 priceUSD = offer.priceUSD.mul(10**(tokenDecimals * 2));

        uint256 finalAmount = priceUSD.div(tokenPrice);
        uint256 fees = finalAmount.div(fee);

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

        IERC20(_tokenPayment).transferFrom(_msgSender(), feeRecipient, fees);

        offer.status = OfferStatus.ACCEPTED;
        emit OfferAccepted(
            _msgSender(),
            _seller,
            _tokenId,
            offer.amount,
            offer.priceUSD
        );
    }

    /**
     * @dev Accepts an offer of an ERC-1155 Token using ETH.
     *
     * Emits a {OfferAccepted} event.
     *
     * Requirements:
     *
     * - `_seller` cannot be the zero address.
     * - `_tokenId` must be greater than zero.
     */
    function acceptOfferWithETH(address _seller, uint256 _tokenId)
        external
        payable
    {
        require(_seller != address(0), "NTFMarketplace: ZERO_ADDRESS");
        require(_tokenId > 0, "NTFMarketplace: ID_ERROR");

        uint256 amount = msg.value;
        require(amount > 0, "NFTMarketplace: ZERO_AMOUNT");

        Offer storage offer = offers[_seller][_tokenId];
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

        // transfer eth to seller
        payable(_seller).transfer(finalAmount.sub(fees));

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

        //send fees to the recipient
        payable(feeRecipient).transfer(fees);
        // refund to sender
        payable(_msgSender()).transfer(address(this).balance);

        offer.status = OfferStatus.ACCEPTED;
        emit OfferAccepted(
            _msgSender(),
            _seller,
            _tokenId,
            offer.amount,
            offer.priceUSD
        );
    }

    /**
     * @dev Cancels an offer of an ERC-1155 Token.
     *
     * Emits a {OfferCancelled} event.
     *
     * Requirements:
     *
     * - `_tokenId` must be greater than zero.
     */
    function cancelOffer(uint256 _tokenId) external {
        require(_tokenId > 0, "NFTMarketplace: ID_ERROR");

        Offer storage offer = offers[_msgSender()][_tokenId];
        require(
            offer.status != OfferStatus.CANCELLED,
            "NFTMarketplace: This offer is already cancelled"
        );

        offer.status = OfferStatus.CANCELLED;
        emit OfferCancelled(offer.seller, offer.token, offer.tokenId);
    }

    /**
     * @dev Sets the fees of each transaction.
     *
     * Requirements:
     *
     * - `_fee` must be greater than zero.
     * - Only the owner can change the value of {fee}.
     */
    function setFee(uint256 _fee) external onlyOwner {
        fee = _fee;
    }

    /**
     * @dev Sets the address who is hold the fees.
     *
     * Requirements:
     *
     * - `_feeRecipient` cannot be the zero address.
     * - Only the owner can change the address of the {feeRecipient}.
     */
    function setFeeRecipient(address payable _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Sets the Chainlink address for the USD pair of the token for payment.
     *
     * Requirements:
     *
     * - `_tokenPayment` cannot be the zero address.
     * - `_chainlinkAddress` cannot be the zero address.
     * - Only the owner can change the address of a `_tokenPayment`.
     */
    function setChainlinkUSDToken(
        address _tokenPayment,
        address _chainlinkAddress
    ) external onlyOwner {
        _chainlinkUSDToken[_tokenPayment] = _chainlinkAddress;
    }

    /**
     * @dev Sets a whitelist of ERC-20 tokens for payment.
     *
     * Requirements:
     *
     * - `_paymentToken` cannot be the zero address.
     * - Only owner can change whether a token is accepted or not.
     */
    function setWhitelistedPaymentToken(address _paymentToken, bool isAccepted)
        external
        onlyOwner
    {
        require(_paymentToken != address(0), "NFTMarketplace: ZERO_ADDRESS");
        _whitelistedERC20[_paymentToken] = isAccepted;
    }

    /**
     * @dev Returns the price of a token in USD.
     *
     * Requirements:
     *
     * - `_tokenPayment` cannot be the zero address and address must be
     * in the whitelist of ERC-20 Tokens.
     */
    function _getPriceByToken(address _tokenPayment)
        internal
        view
        returns (uint256)
    {
        require(
            _whitelistedERC20[_tokenPayment],
            "NFTMarketplace: TOKEN_NOT_ALLOWED"
        );
        require(
            _chainlinkUSDToken[_tokenPayment] != address(0),
            "NFTMarketplace: TOKEN_ZERO_ADDRESS"
        );
        AggregatorV3Interface priceToken =
            AggregatorV3Interface(_chainlinkUSDToken[_tokenPayment]);
        (, int256 price, , , ) = priceToken.latestRoundData();

        return uint256(price);
    }
}
