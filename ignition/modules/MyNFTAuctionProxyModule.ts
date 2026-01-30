import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MyNFTAuctionProxyModule = buildModule(
  "MyNFTAuctionProxyModule",
  (m) => {
    const deployer = m.getAccount(0);

    const auctionImpl = m.contract("MyNFTAuction");

    // 编码初始化函数调用
    const initializeData = m.encodeFunctionCall(
      auctionImpl,
      "initialize",
      []
    );

    // 部署代理合约
    const proxy = m.contract("TransparentUpgradeableProxy", [
      auctionImpl,
      deployer,
      initializeData,
    ]);

    return { proxy };
  },
);

const MyNFTAuctionModule = buildModule("MyNFTAuctionModule", (m) => {
  const { proxy } = m.useModule(MyNFTAuctionProxyModule);

  const auction = m.contractAt("MyNFTAuction", proxy);

  return { auction, proxy };
});

export default MyNFTAuctionModule;