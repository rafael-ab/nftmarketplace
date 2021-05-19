const NFTMarketplaceV2 = artifacts.require("NFTMarketplaceV2");
const Token721 = artifacts.require("Token721");
const IERC20 = artifacts.require("IERC20");
const { assert, web3 } = require("hardhat");
const {
  expectEvent,
  expectRevert,
  time,
} = require("@openzeppelin/test-helpers");

// Token Address
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const LINK_ADDRESS = "0x514910771AF9Ca656af840dff83E8264EcF986CA";

// Account Address
const ADMIN = "0xE92d1A43df510F82C66382592a047d288f85226f";
const SELLER = "0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e";
const BUYER_ETH = "0x0a4c79cE84202b03e95B7a692E5D728d83C44c76";
const BUYER_TOKEN = "0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503";
const RECIPIENT = "0x9BF4001d307dFd62B26A2F1307ee0C0307632d59";

// Chainlink Address
const USD_ETH_ADDRESS = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419";
const USD_DAI_ADDRESS = "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9";
const USD_LINK_ADDRESS = "0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c";

const toWei = (value, type) => web3.utils.toWei(String(value), type);
const fromWei = (value, type) =>
  Number(web3.utils.fromWei(String(value), type));
const toBN = (value) => web3.utils.toBN(String(value));

contract("NFTMarketplaceV2", () => {
  let marketplaceV2;

  before(async () => {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ADMIN],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [SELLER],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [BUYER_ETH],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [BUYER_TOKEN],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [RECIPIENT],
    });

    marketplaceV2 = await NFTMarketplaceV2.new({ from: ADMIN });
    marketplaceV2.initialize(RECIPIENT, 100, { from: ADMIN });

    // set whitelist tokens for payments
    marketplaceV2.setWhitelistedPaymentToken(WETH_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV2.setChainlinkUSDToken(WETH_ADDRESS, USD_ETH_ADDRESS, {
      from: ADMIN,
    });

    marketplaceV2.setWhitelistedPaymentToken(DAI_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV2.setChainlinkUSDToken(DAI_ADDRESS, USD_DAI_ADDRESS, {
      from: ADMIN,
    });

    marketplaceV2.setWhitelistedPaymentToken(LINK_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV2.setChainlinkUSDToken(LINK_ADDRESS, USD_LINK_ADDRESS, {
      from: ADMIN,
    });
  });

  it("seller should create an 721 token offer", async () => {
    const timestamp = await time.latest();

    const token = await Token721.new({ from: SELLER });
    await token.safeMint(SELLER, 21548, { from: SELLER });
    await token.setApprovalForAll(marketplaceV2.address, true, {
      from: SELLER,
    });

    const tx = await marketplaceV2.createOfferERC721(
      token.address,
      21548,
      timestamp + 1,
      toBN(245),
      { from: SELLER }
    );

    await expectEvent(tx, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(21548),
      amount: toBN(1),
      deadline: timestamp + 1,
      priceUSD: toBN(245),
    });

    console.log("Gas Used :>> ", tx.receipt.gasUsed);
  });

  it("should accept an 721 token offer using ETH", async () => {
    const timestamp = await time.latest();

    const token = await Token721.new({ from: SELLER });
    await token.safeMint(SELLER, 1, { from: SELLER });
    await token.setApprovalForAll(marketplaceV2.address, true, {
      from: SELLER,
    });

    console.log("SELLER Address :>> ", SELLER);
    console.log("BUYER_ETH Address :>> ", BUYER_ETH);
    console.log("Token Owner Before :>> ", String(await token.ownerOf(1)));

    const tx1 = await marketplaceV2.createOfferERC721(
      token.address,
      1,
      timestamp + 1,
      250,
      { from: SELLER }
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
      amount: toBN(1),
      deadline: timestamp + 1,
      priceUSD: toBN(250),
    });

    const tx2 = await marketplaceV2.acceptOfferERC721WithETH(SELLER, 1, {
      from: BUYER_ETH,
      value: toWei(1, "ether"),
    });

    await expectEvent(tx2, "OfferAccepted", {
      buyer: BUYER_ETH,
      seller: SELLER,
      tokenId: toBN(1),
      amount: toBN(1),
      priceUSD: toBN(250),
    });

    assert.equal(BUYER_ETH, await token.ownerOf(1));

    console.log("Token Owner After :>> ", String(await token.ownerOf(1)));

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });

  it("should accept an offer 721 token using DAI", async () => {
    const timestamp = await time.latest();

    const token = await Token721.new({ from: SELLER });
    await token.safeMint(SELLER, 1254, { from: SELLER });
    await token.setApprovalForAll(marketplaceV2.address, true, {
      from: SELLER,
    });

    console.log("SELLER Address :>> ", SELLER);
    console.log("BUYER_TOKEN Address :>> ", BUYER_TOKEN);
    console.log("Token Owner Before :>> ", String(await token.ownerOf(1254)));

    const tx1 = await marketplaceV2.createOfferERC721(
      token.address,
      1254,
      timestamp + 1,
      toBN(2500),
      { from: SELLER }
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1254),
      amount: toBN(1),
      deadline: timestamp + 1,
      priceUSD: toBN(2500),
    });

    // send some funds to pay fees for tx
    await web3.eth.sendTransaction({
      from: BUYER_ETH,
      to: BUYER_TOKEN,
      value: toWei(1, "ether"),
    });

    const daiToken = await IERC20.at(DAI_ADDRESS);
    await daiToken.approve(marketplaceV2.address, toWei(3000, "ether"), {
      from: BUYER_TOKEN,
    });

    const tx2 = await marketplaceV2.acceptOfferERC721WithTokens(
      SELLER,
      1254,
      toWei(3000, "ether"), // DAI and ETH have the same decimals (18)
      DAI_ADDRESS,
      { from: BUYER_TOKEN }
    );

    await expectEvent(tx2, "OfferAccepted", {
      buyer: BUYER_TOKEN,
      seller: SELLER,
      tokenId: toBN(1254),
      amount: toBN(1),
      priceUSD: toBN(2500),
    });

    assert.equal(BUYER_TOKEN, await token.ownerOf(1254));

    console.log("Token Owner After :>> ", String(await token.ownerOf(1254)));

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });
});
