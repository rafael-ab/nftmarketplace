// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "@chainlink/contracts/src/v0.7/interfaces/AggregatorV3Interface.sol";

library PriceTokenPairUSD {

    AggregatorV3Interface internal constant priceETH =
    AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    AggregatorV3Interface internal constant priceDAI =
    AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);

    AggregatorV3Interface internal constant priceLINK =
    AggregatorV3Interface(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c);
    
    /// @notice Retrieves the current ETH price in USD
    /// @return The price in USD with 8 decimals
    function getETHPrice() external view returns (int) {
        (, int price, , , ) = priceETH.latestRoundData();
        return price;
    }

    /// @notice Retrieves the current DAI price in USD
    /// @return The price in USD with 8 decimals
    function getDAIPrice() external view returns (int) {
        (, int price, , , ) = priceDAI.latestRoundData();
        return price;
    }

    /// @notice Retrieves the current LINK price in USD
    /// @return The price in USD with 8 decimals
    function getLINKPrice() external view returns (int) {
        (, int price, , , ) = priceLINK.latestRoundData();
        return price;
    }
}
