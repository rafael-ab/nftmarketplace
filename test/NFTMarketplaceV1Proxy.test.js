const { assert, upgrades, ethers } = require("hardhat");

const ADMIN = "0xE92d1A43df510F82C66382592a047d288f85226f";
const NEW_ADMIN = "0x73BCEb1Cd57C711feaC4224D062b0F6ff338501e";
const RECIPIENT = "0x9BF4001d307dFd62B26A2F1307ee0C0307632d59";

const FEE = 100;

contract("NFTMarketplaceV1 (Proxy)", () => {
  let marketplaceV1, adminSigner, proxyAdmin;

  before(async () => {
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [ADMIN],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [NEW_ADMIN],
      });
      await hre.network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [RECIPIENT],
      });

      adminSigner = await ethers.getSigner(ADMIN);
      marketplaceV1 = await ethers.getContractFactory("NFTMarketplaceV1", adminSigner);
      instance = await upgrades.deployProxy(marketplaceV1, [RECIPIENT, FEE]);
      proxyAdmin = await upgrades.admin.getInstance();
  });

  it("contract should initialize", async () => {
    assert.ok(await instance.feeRecipient());
    assert.ok(await instance.fee());
  });

  it("should retrieves a previously initialised fee recipient", async () => {
    assert.equal(RECIPIENT, await instance.feeRecipient());
  });

  it("proxy admin should be the admin", async () => {
    assert.equal(ADMIN, await proxyAdmin.owner());
  });
});