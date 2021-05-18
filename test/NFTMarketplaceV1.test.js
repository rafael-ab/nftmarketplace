const NFTMarketplaceV1 = artifacts.require("NFTMarketplaceV1");
const Token = artifacts.require("Token");
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

contract("NFTMarketplaceV1", () => {
  let marketplaceV1;

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

    marketplaceV1 = await NFTMarketplaceV1.new({ from: ADMIN });
    marketplaceV1.initialize(RECIPIENT, 100, { from: ADMIN });

    // set whitelist tokens for payments
    marketplaceV1.setWhitelistedPaymentToken(WETH_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV1.setChainlinkUSDToken(WETH_ADDRESS, USD_ETH_ADDRESS, {
      from: ADMIN,
    });

    marketplaceV1.setWhitelistedPaymentToken(DAI_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV1.setChainlinkUSDToken(DAI_ADDRESS, USD_DAI_ADDRESS, {
      from: ADMIN,
    });

    marketplaceV1.setWhitelistedPaymentToken(LINK_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV1.setChainlinkUSDToken(LINK_ADDRESS, USD_LINK_ADDRESS, {
      from: ADMIN,
    });
  });

  it("only admin should change fees", async () => {
    await marketplaceV1.setFee(100, { from: ADMIN });
    await expectRevert.unspecified(marketplaceV1.setFee(999999));
  });

  it("only admin should change recipient", async () => {
    await marketplaceV1.setFeeRecipient(BUYER_ETH, { from: ADMIN });
    await expectRevert.unspecified(marketplaceV1.setFeeRecipient(BUYER_ETH));
  });

  it("seller should create an offer", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    const tx = await marketplaceV1.createOffer(
      token.address,
      1,
      10,
      timestamp + 1,
      250,
      { from: SELLER }
    );

    await expectEvent(tx, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
      amount: toBN(10),
      deadline: timestamp + 1,
      priceUSD: toBN(250),
    });

    console.log("Gas Used :>> ", tx.receipt.gasUsed);
  });

  it("seller should cancel an offer", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });

    const tx1 = await marketplaceV1.createOffer(
      token.address,
      1,
      10,
      timestamp + 1,
      250,
      { from: SELLER }
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
      amount: toBN(10),
      deadline: timestamp + 1,
      priceUSD: toBN(250),
    });

    const tx2 = await marketplaceV1.cancelOffer(1, { from: SELLER });

    await expectEvent(tx2, "OfferCancelled", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
    });
    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });

  it("should accept an offer using ETH", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 1, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    console.log(
      "SELLER Token 1 Balance :>> ",
      String(await token.balanceOf(SELLER, 1))
    );
    console.log(
      "BUYER Token 1 Balance :>> ",
      String(await token.balanceOf(BUYER_ETH, 1))
    );

    const tx1 = await marketplaceV1.createOffer(
      token.address,
      1,
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

    const tx2 = await marketplaceV1.acceptOfferWithETH(SELLER, 1, {
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

    console.log(
      "SELLER Token 1 Balance :>> ",
      String(await token.balanceOf(SELLER, 1))
    );
    console.log(
      "BUYER Token 1 Balance :>> ",
      String(await token.balanceOf(BUYER_ETH, 1))
    );

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });

  it("should accept an offer using DAI", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 1254, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    console.log(
      "SELLER Token 1254 Balance :>> ",
      String(await token.balanceOf(SELLER, 1254))
    );
    console.log(
      "BUYER Token 1254 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 1254))
    );

    const tx1 = await marketplaceV1.createOffer(
      token.address,
      1254,
      1,
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
    await daiToken.approve(marketplaceV1.address, toWei(3000, "ether"), {
      from: BUYER_TOKEN,
    });

    const tx2 = await marketplaceV1.acceptOfferWithTokens(
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

    console.log(
      "SELLER Token 1254 Balance :>> ",
      String(await token.balanceOf(SELLER, 1254))
    );
    console.log(
      "BUYER Token 1254 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 1254))
    );

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });

  it("should accept an offer using LINK", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 12548, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    console.log(
      "SELLER Token 12548 Balance :>> ",
      String(await token.balanceOf(SELLER, 12548))
    );
    console.log(
      "BUYER Token 12548 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 12548))
    );

    const tx1 = await marketplaceV1.createOffer(
      token.address,
      12548,
      1,
      timestamp + 1,
      2500,
      { from: SELLER }
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(12548),
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

    const linkToken = await IERC20.at(LINK_ADDRESS);
    await linkToken.approve(marketplaceV1.address, toWei(100, "ether"), {
      from: BUYER_TOKEN,
    });

    const tx2 = await marketplaceV1.acceptOfferWithTokens(
      SELLER,
      12548,
      toWei(100, "ether"), // LINK and ETH have the same decimals (18)
      LINK_ADDRESS,
      { from: BUYER_TOKEN }
    );

    await expectEvent(tx2, "OfferAccepted", {
      buyer: BUYER_TOKEN,
      seller: SELLER,
      tokenId: toBN(12548),
      amount: toBN(1),
      priceUSD: toBN(2500),
    });

    console.log(
      "SELLER Token 12548 Balance :>> ",
      String(await token.balanceOf(SELLER, 12548))
    );
    console.log(
      "BUYER Token 12548 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 12548))
    );

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });

  it("should fail when ERC-1155 token is not approved", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 1, 1, 0, { from: SELLER });
    // await token.setApprovalForAll(marketplaceV1.address, true, {from: SELLER});

    await marketplaceV1.createOffer(token.address, 1, 1, timestamp + 1, 250, {
      from: SELLER,
    });

    expectRevert(
      marketplaceV1.acceptOfferWithETH(SELLER, 1, {
        from: BUYER_ETH,
        value: toWei(1, "ether"),
      }),
      "NTFMarketplace: NOT_APPROVAL"
    );
  });

  it("should fail when ERC-20 token is not approved for payment", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 12548, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    await marketplaceV1.createOffer(
      token.address,
      12548,
      1,
      timestamp + 1,
      2500,
      { from: SELLER }
    );

    // send some funds to pay fees for tx
    await web3.eth.sendTransaction({
      from: BUYER_ETH,
      to: BUYER_TOKEN,
      value: toWei(1, "ether"),
    });

    // const linkToken = await IERC20.at(LINK_ADDRESS);
    // await linkToken.approve(marketplaceV1.address, toWei(100, "ether"), { from: BUYER_TOKEN });

    await expectRevert(
      marketplaceV1.acceptOfferWithTokens(
        SELLER,
        12548,
        toWei(100, "ether"), // LINK and ETH have the same decimals (18)
        LINK_ADDRESS,
        { from: BUYER_TOKEN }
      ),
      "NTFMarketplace: INSUFFICIENT_ALLOWANCE"
    );
  });

  it("should fail if tries to accept the same offer twice", async () => {
    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 12548, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    await marketplaceV1.createOffer(
      token.address,
      12548,
      1,
      timestamp + 1,
      2500,
      { from: SELLER }
    );

    // send some funds to pay fees for tx
    await web3.eth.sendTransaction({
      from: BUYER_ETH,
      to: BUYER_TOKEN,
      value: toWei(1, "ether"),
    });

    const linkToken = await IERC20.at(LINK_ADDRESS);
    await linkToken.approve(marketplaceV1.address, toWei(100, "ether"), {
      from: BUYER_TOKEN,
    });

    await marketplaceV1.acceptOfferWithTokens(
      SELLER,
      12548,
      toWei(100, "ether"), // LINK and ETH have the same decimals (18)
      LINK_ADDRESS,
      { from: BUYER_TOKEN }
    );

    await expectRevert(
      marketplaceV1.acceptOfferWithTokens(
        SELLER,
        12548,
        toWei(100, "ether"), // LINK and ETH have the same decimals (18)
        LINK_ADDRESS,
        { from: BUYER_TOKEN }
      ),
      "NFTMarketplace: This offer is already cancelled or accepted"
    );
  });

  it("should support accept an offer using USDC, ERC20 with 6 decimals", async () => {
    const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
    const USD_USDC_ADDRESS = "0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6";

    marketplaceV1.setWhitelistedPaymentToken(USDC_ADDRESS, true, {
      from: ADMIN,
    });
    marketplaceV1.setChainlinkUSDToken(USDC_ADDRESS, USD_USDC_ADDRESS, {
      from: ADMIN,
    });

    const timestamp = await time.latest();

    const token = await Token.new({ from: SELLER });
    await token.mint(SELLER, 22, 1, 0, { from: SELLER });
    await token.setApprovalForAll(marketplaceV1.address, true, {
      from: SELLER,
    });

    console.log(
      "SELLER Token 22 Balance :>> ",
      String(await token.balanceOf(SELLER, 22))
    );
    console.log(
      "BUYER Token 22 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 22))
    );

    const tx1 = await marketplaceV1.createOffer(
      token.address,
      22,
      1,
      timestamp + 1,
      2500,
      { from: SELLER }
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(22),
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

    const usdcToken = await IERC20.at(USDC_ADDRESS);
    await usdcToken.approve(marketplaceV1.address, 3000 * 10 ** 6, {
      from: BUYER_TOKEN,
    });

    const tx2 = await marketplaceV1.acceptOfferWithTokens(
      SELLER,
      22,
      3000 * 10 ** 6, // USDC and ETH have different decimals (6 and 18)
      USDC_ADDRESS,
      { from: BUYER_TOKEN }
    );

    await expectEvent(tx2, "OfferAccepted", {
      buyer: BUYER_TOKEN,
      seller: SELLER,
      tokenId: toBN(22),
      amount: toBN(1),
      priceUSD: toBN(2500),
    });

    console.log(
      "SELLER Token 22 Balance :>> ",
      String(await token.balanceOf(SELLER, 22))
    );
    console.log(
      "BUYER Token 22 Balance :>> ",
      String(await token.balanceOf(BUYER_TOKEN, 22))
    );

    console.log("Gas Used :>> ", tx1.receipt.gasUsed + tx2.receipt.gasUsed);
  });
});
