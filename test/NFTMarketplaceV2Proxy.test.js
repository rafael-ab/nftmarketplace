const { assert, upgrades, ethers } = require("hardhat");

const ADMIN = "0xE92d1A43df510F82C66382592a047d288f85226f";
const RECIPIENT = "0x9BF4001d307dFd62B26A2F1307ee0C0307632d59";
const FEE = 100;

contract("MarketplaceV2 (Proxy)", () => {
  let instance, upgraded, adminSigner, proxyAdmin;;

  before(async () => {
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [ADMIN],
    });
    await hre.network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [RECIPIENT],
    });

    adminSigner = await ethers.getSigner(ADMIN);
    const MarketplaceV1 = await ethers.getContractFactory("NFTMarketplaceV1", adminSigner);
    const MarketplaceV2 = await ethers.getContractFactory("NFTMarketplaceV2", adminSigner);

    instance = await upgrades.deployProxy(MarketplaceV1, [RECIPIENT, FEE]);
    upgraded = await upgrades.upgradeProxy(instance.address, MarketplaceV2);
    proxyAdmin = await upgrades.admin.getInstance();
  });

  it("upgraded contract should be initialized", async () => {
    assert.equal(RECIPIENT, await upgraded.feeRecipient());
    assert.equal(FEE, await upgraded.fee());
  });

  it("proxy admin should be the admin", async () => {
    assert.equal(ADMIN, await proxyAdmin.owner());
  });
});