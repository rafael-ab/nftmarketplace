const NFTMarketplaceV1 = artifacts.require("NFTMarketplaceV1");
const ERC1155 = artifacts.require("ERC1155");
const { assert, web3 } = require("hardhat");
const { expectEvent, expectRevert, time } = require("@openzeppelin/test-helpers");

const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const LINK_ADDRESS = "0x514910771AF9Ca656af840dff83E8264EcF986CA";

const ADMIN = "0xE92d1A43df510F82C66382592a047d288f85226f";
const SELLER = "0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e";
const BUYER = "0xDf9Eb223bAFBE5c5271415C75aeCD68C21fE3D7F";
const RECIPIENT = "0x9BF4001d307dFd62B26A2F1307ee0C0307632d59";

const toWei = (value, type) => web3.utils.toWei(String(value), type);
const fromWei = (value, type) => Number(web3.utils.fromWei(String(value), type));
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
        params: [BUYER],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [RECIPIENT],
      });

      marketplaceV1 = await NFTMarketplaceV1.new({from: ADMIN});
      marketplaceV1.initialize(RECIPIENT, 100, {from: ADMIN});

      // set whitelist for payments
      marketplaceV1.setWhitelistedPaymentToken(WETH_ADDRESS, {from: ADMIN});
      marketplaceV1.setWhitelistedPaymentToken(DAI_ADDRESS, {from: ADMIN});
      marketplaceV1.setWhitelistedPaymentToken(LINK_ADDRESS, {from: ADMIN});
  });

  it("only admin should change fees", async() => {
    await marketplaceV1.setFee(1000, {from: ADMIN});
    await expectRevert.unspecified(marketplaceV1.setFee(999999));
  })

  it("only admin should change recipient", async() => {
    await marketplaceV1.setFeeRecipient(BUYER, { from: ADMIN });
    await expectRevert.unspecified(marketplaceV1.setFeeRecipient(BUYER));
  })

  it("seller should create an offer", async () => {
    const timestamp = await time.latest();
    const token = await ERC1155.new("", {from: SELLER});
    await token.setApprovalForAll(marketplaceV1.address, true, {from: SELLER});
    console.log('await marketplaceV1.offers(SELLER, 1) :>> ', await marketplaceV1.offers(SELLER, 1));
    const tx = await marketplaceV1.createOffer(
      token.address,
      1,
      10,
      timestamp + 360,
      250,
      {from: SELLER}
    );

    await expectEvent(tx, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
      amount: toBN(10),
      deadline: timestamp + 360,
      priceUSD: toBN(250)
    });
    console.log('await marketplaceV1.offers(SELLER, 1) :>> ', await marketplaceV1.offers(SELLER, 1));
    console.log("Gas Used:", tx.receipt.gasUsed);
  });


  it("seller should cancel an offer", async () => {
    const timestamp = await time.latest();
    const token = await ERC1155.new("", {from: SELLER});
    await token.setApprovalForAll(marketplaceV1.address, true, {from: SELLER});
    const tx1 = await marketplaceV1.createOffer(
      token.address,
      1,
      10,
      timestamp + 360,
      250,
      {from: SELLER}
    );

    await expectEvent(tx1, "OfferCreated", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1),
      amount: toBN(10),
      deadline: timestamp + 360,
      priceUSD: toBN(250)
    });
    console.log("Tx1 Gas Used:", tx1.receipt.gasUsed);

    const tx2 = await marketplaceV1.cancelOffer(1, {from: SELLER});

    await expectEvent(tx2, "OfferCancelled", {
      seller: SELLER,
      token: token.address,
      tokenId: toBN(1)
    });
    console.log("Tx2 Gas Used:", tx2.receipt.gasUsed);
  });
})