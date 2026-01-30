const { run, ethers } = require("hardhat");

async function main() {
  console.log("开始部署NFT拍卖合约...");
  
  // 获取部署账户
  const [deployer] = await ethers.getSigners();
  console.log("部署账户:", deployer.address);
  console.log("账户余额:", (await deployer.provider.getBalance(deployer.address)).toString());

  // 部署实现合约
  console.log("\n部署拍卖合约实现...");
  const AuctionImpl = await ethers.getContractFactory("MyNFTAuction");
  const auctionImpl = await AuctionImpl.deploy();
  await auctionImpl.waitForDeployment();
  console.log("拍卖合约实现地址:", await auctionImpl.getAddress());

  // 部署代理合约
  console.log("\n部署代理合约...");
  const Proxy = await ethers.getContractFactory("TransparentUpgradeableProxy");
  
  // 编码初始化数据
  const initializeData = auctionImpl.interface.encodeFunctionData("initialize", []);
  
  const proxy = await Proxy.deploy(
    await auctionImpl.getAddress(),
    deployer.address, // admin
    initializeData
  );
  await proxy.waitForDeployment();
  console.log("代理合约地址:", await proxy.getAddress());

  // 获取通过代理访问的合约实例
  const auction = await ethers.getContractAt("MyNFTAuction", await proxy.getAddress());
  console.log("\n合约部署完成!");
  console.log("最终可访问合约地址:", await auction.getAddress());
  console.log("合约所有者:", await auction.owner());

  // 提示用户设置价格预言机
  console.log("\n重要提示:");
  console.log("- 部署完成后需要调用 setPriceFeed() 函数设置价格预言机");
  console.log("- 价格预言机地址需要根据部署的网络进行配置");
  console.log("- Sepolia测试网示例: 0x694AA1769357215DE4FAC081bf1f309aDC325306 (ETH/USD)");

  return {
    implAddress: await auctionImpl.getAddress(),
    proxyAddress: await proxy.getAddress(),
    contractAddress: await auction.getAddress()
  };
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });