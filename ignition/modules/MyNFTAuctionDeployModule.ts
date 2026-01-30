import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const MyNFTAuctionDeployModule = buildModule("MyNFTAuctionDeployModule", (m) => {
  const deployer = m.getAccount(0);

  // 部署 NFT 拍卖合约 (实现合约)
  const auctionImpl = m.contract("MyNFTAuction");

  // 编码初始化函数调用
  const initializeData = m.encodeFunctionCall(
    auctionImpl,
    "initialize",
    []
  );

  // 部署代理合约 - 使用辅助合约
  const proxy = m.contract("ProxyHelper", [
    auctionImpl,
    deployer,
    initializeData,
  ], { id: "AuctionProxy" });

  // 获取代理合约上的拍卖实例
  const auction = m.contractAt("MyNFTAuction", proxy, { id: "MyNFTAuctionProxy" });

  return { auction, proxy /*, mockPriceFeed */ };
});

export default MyNFTAuctionDeployModule;