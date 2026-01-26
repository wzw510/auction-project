import { expect } from "chai";
import { ethers, upgrades,network } from "hardhat";
//import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";  // 正确的导入方式
import loadFixture from "@nomicfoundation/hardhat-network-helpers"

const {networkHelpers} = await network.connect();
// 定义 fixture 函数
async function deployDutchAuctionFixture() {
  const [deployer, seller, buyer1, buyer2] = await ethers.getSigners();
  
  // 部署模拟价格预言机
  const MockPriceFeed = await ethers.getContractFactory("MockPriceFeed");
  const mockPriceFeed = await MockPriceFeed.deploy(2000 * 1e8); // $2000 per ETH
  await mockPriceFeed.waitForDeployment();
  
  // 部署NFT合约
  const SimpleNFT = await ethers.getContractFactory("SimpleNFT");
  const nft = await SimpleNFT.deploy("Test NFT", "TNFT");
  await nft.waitForDeployment();
  
  // 部署拍卖合约（使用代理）
  const DutchAuction = await ethers.getContractFactory("DutchAuction");
  const auction = await upgrades.deployProxy(
    DutchAuction,
    [await mockPriceFeed.getAddress()],
    { 
      initializer: 'initialize',
      kind: 'uups'
    }
  );
  await auction.waitForDeployment();
  
  // 给卖家铸造NFT
  await nft.mint(seller.address);
  await nft.mint(seller.address);
  
  // 卖家授权拍卖合约
  await nft.connect(seller).setApprovalForAll(await auction.getAddress(), true);
  
  return { 
    nft, 
    auction, 
    mockPriceFeed, 
    deployer, 
    seller, 
    buyer1, 
    buyer2 
  };
}

describe("Dutch Auction Marketplace", function () {
  // 测试用例
  describe("NFT Contract", function () {
    it("Should mint NFT correctly", async function () {
      const { nft, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      expect(await nft.ownerOf(1)).to.equal(seller.address);
      expect(await nft.ownerOf(2)).to.equal(seller.address);
    });
  });

  describe("Dutch Auction", function () {
    it("Should create auction", async function () {
      const { nft, auction, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      // 创建荷兰拍卖：起始价格1 ETH，结束价格0.1 ETH，持续1小时
      await auction.connect(seller).createAuction(
        await nft.getAddress(),
        1,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.1"),
        3600 // 1小时
      );

      const auctionInfo = await auction.getAuctionInfo(1);
      expect(auctionInfo.seller).to.equal(seller.address);
      expect(auctionInfo.nftAddress).to.equal(await nft.getAddress());
      expect(auctionInfo.tokenId).to.equal(1);
      expect(auctionInfo.ended).to.be.false;
    });

    it("Should calculate correct current price", async function () {
      const { nft, auction, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      await auction.connect(seller).createAuction(
        await nft.getAddress(),
        1,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.1"),
        3600
      );

      // 刚开始的价格应该是起始价格
      let price = await auction.getCurrentPrice(1);
      expect(price).to.equal(ethers.parseEther("1.0"));

      // 使用硬分叉网络的时间操作
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      // 价格应该下降一半左右
      price = await auction.getCurrentPrice(1);
      const expectedPrice = ethers.parseEther("0.55"); // (1.0 + 0.1) / 2 = 0.55
      const tolerance = ethers.parseEther("0.01"); // 增加容差
      
      // 使用 closeTo 断言（chai 支持大数）
      const priceNum = Number(ethers.formatEther(price));
      const expectedNum = Number(ethers.formatEther(expectedPrice));
      const toleranceNum = Number(ethers.formatEther(tolerance));
      
      expect(priceNum).to.be.closeTo(expectedNum, toleranceNum);
    });

    it("Should allow buying at current price", async function () {
      const { nft, auction, seller, buyer1 } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      await auction.connect(seller).createAuction(
        await nft.getAddress(),
        1,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.1"),
        3600
      );

      // 前进时间
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);
      
      const currentPrice = await auction.getCurrentPrice(1);
      
      // 买家以当前价格购买
      await auction.connect(buyer1).buy(1, { value: currentPrice });

      const auctionInfo = await auction.getAuctionInfo(1);
      expect(auctionInfo.ended).to.be.true;
      expect(auctionInfo.highestBidder).to.equal(buyer1.address);
      expect(await nft.ownerOf(1)).to.equal(buyer1.address);
    });

    it("Should convert price to USD correctly", async function () {
      const { nft, auction, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      await auction.connect(seller).createAuction(
        await nft.getAddress(),
        1,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.1"),
        3600
      );

      const ethPrice = await auction.getCurrentPrice(1);
      const usdPrice = await auction.getCurrentPriceUSD(1);
      
      // 1 ETH = $2000 (mock price), 注意小数位处理
      // Chainlink 价格有8位小数，ETH有18位小数
      const ethPriceBigInt = BigInt(ethPrice.toString());
      const expectedUSD = (ethPriceBigInt * 2000n * 10000000000n) / (10n ** 18n);
      const tolerance = expectedUSD / 20n; // 5% 容差
      
      // 转换为数字进行比较
      const usdPriceNum = Number(usdPrice.toString());
      const expectedUSDNum = Number(expectedUSD.toString());
      const toleranceNum = Number(tolerance.toString());
      
      expect(usdPriceNum).to.be.closeTo(expectedUSDNum, toleranceNum);
    });

    it("Should allow seller to cancel auction", async function () {
      const { nft, auction, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      await auction.connect(seller).createAuction(
        await nft.getAddress(),
        1,
        ethers.parseEther("1.0"),
        ethers.parseEther("0.1"),
        3600
      );

      await auction.connect(seller).cancelAuction(1);
      
      const auctionInfo = await auction.getAuctionInfo(1);
      expect(auctionInfo.ended).to.be.true;
      expect(await nft.ownerOf(1)).to.equal(seller.address); // NFT退回卖家
    });
  });

  describe("State Isolation", function () {
    it("Should not be affected by previous test", async function () {
      const { nft, auction, seller } = await networkHelpers.loadFixture(deployDutchAuctionFixture);
      
      // 检查初始状态
      expect(await nft.balanceOf(seller.address)).to.equal(2);
    });
  });
});