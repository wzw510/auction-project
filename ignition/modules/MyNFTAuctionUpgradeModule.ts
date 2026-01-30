import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

import MyNFTAuctionModule from "./MyNFTAuctionProxyModule.js";

const MyNFTAuctionUpgradeModule = buildModule(
  "MyNFTAuctionUpgradeModule",
  (m) => {
    const deployer = m.getAccount(0);

    const { proxy } = m.useModule(MyNFTAuctionModule);

    const auctionV2 = m.contract("MyNFTAuctionV2");

    // 升级代理合约到 V2 版本
    const upgradeTx = m.call(proxy, "upgradeToAndCall", [auctionV2, "0x"], {
      id: "upgradeToV2",
      from: deployer,
    });

    const upgradedAuction = m.contractAt("MyNFTAuctionV2", proxy, {
      id: "MyNFTAuctionV2AtProxy",
    });

    return { upgradedAuction, proxy };
  },
);

export default MyNFTAuctionUpgradeModule;