import { upgrades } from "@openzeppelin/hardhat-upgrades";

import { network } from "hardhat";

const { ethers } = await network.connect({
  network: "hardhatOp",
  chainType: "op",
});
async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with account:", deployer.address);
  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  // Sepolia测试网的Chainlink ETH/USD价格预言机地址
  const SEPOLIA_ETH_USD_PRICE_FEED = "0x694AA1769357215DE4FAC081bf1f309aDC325306";

  // 1. 部署NFT合约
  console.log("\n1. Deploying SimpleNFT...");
  const SimpleNFT = await ethers.getContractFactory("SimpleNFT");
  const nft = await SimpleNFT.deploy("My Dutch NFT", "MDNFT");
  await nft.waitForDeployment();
  console.log("SimpleNFT deployed to:", await nft.getAddress());

  // 2. 部署拍卖合约（使用UUPS代理）
  console.log("\n2. Deploying DutchAuction (UUPS Proxy)...");
  const DutchAuction = await ethers.getContractFactory("DutchAuction");
  const auctionProxy = await upgrades.deployProxy(
    DutchAuction,
    [SEPOLIA_ETH_USD_PRICE_FEED],
    { 
      initializer: 'initialize',
      kind: 'uups'
    }
  );
  await auctionProxy.waitForDeployment();
  console.log("DutchAuction Proxy deployed to:", await auctionProxy.getAddress());

  // 获取逻辑合约地址
  const logicAddress = await upgrades.erc1967.getImplementationAddress(await auctionProxy.getAddress());
  console.log("DutchAuction Logic contract at:", logicAddress);

  console.log("\n=== Deployment Complete ===");
  console.log("NFT Contract:", await nft.getAddress());
  console.log("Auction Proxy:", await auctionProxy.getAddress());
  console.log("Auction Logic:", logicAddress);

  // 铸造一些测试NFT
  console.log("\n3. Minting test NFTs...");
  await nft.mint(deployer.address);
  await nft.mint(deployer.address);
  console.log("Minted 2 NFTs to deployer");

  // 授权拍卖合约可以操作NFT
  console.log("\n4. Approving auction contract to handle NFTs...");
  await nft.setApprovalForAll(await auctionProxy.getAddress(), true);
  console.log("Approved auction contract for all NFTs");

  console.log("\n✅ Deployment and setup completed!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });