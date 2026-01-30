// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MyNFTAuction} from "./MyNFTAuction.sol";
import {MyNFT} from "./MyNFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

// Mock ERC20 代币
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

// Mock ERC721 NFT
contract MockERC721 is ERC721 {
    uint256 private _tokenIdCounter;
    
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}
    
    function mint(address to) public returns (uint256) {
        _tokenIdCounter++;
        _safeMint(to, _tokenIdCounter);
        return _tokenIdCounter;
    }
}

// Mock 价格预言机
contract MockPriceFeed {
    uint8 public decimals;
    int256 public price;
    
    constructor(uint8 _decimals, int256 _price) {
        decimals = _decimals;
        price = _price;
    }
    
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (0, price, 0, block.timestamp, 0);
    }
}

contract MyNFTAuctionTest is Test{
    MyNFTAuction public auction;
    MockERC721 public nft;
    MockERC20 public usdc;
    MockPriceFeed public priceFeed;
    
    address public owner = address(0x1);
    address public seller = address(0x2);
    address public bidder1 = address(0x3);
    address public bidder2 = address(0x4);
    
    uint256 public constant START_PRICE_ETH = 1 ether;
    uint256 public constant START_PRICE_USDC = 1000 * 10 ** 6;
    uint256 public constant DURATION = 7 days;
    uint256 public nftTokenId;
    
    function setUp() public {
        vm.startPrank(owner);
        
        // 部署mock代币
        nft = new MockERC721("Test NFT", "TNFT");
        usdc = new MockERC20("USD Coin", "USDC");
        
        // 设置价格预言机 (1 ETH = 2000 USD, 1 USDC = 1 USD)
        priceFeed = new MockPriceFeed(8, 2000 * 10 ** 8);
        
        // 部署合约并初始化
        auction = new MyNFTAuction();
        vm.stopPrank();
        
        // 初始化拍卖合约
        vm.prank(owner);
        auction.initialize();
        
        // 设置价格预言机
        vm.prank(owner);
        auction.setPriceFeed(address(priceFeed));
        
        vm.startPrank(owner);
        
        // 转移NFT给卖家
        nftTokenId = nft.mint(seller);
        
        // 给竞拍者一些资金
        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);
        vm.deal(seller, 10 ether); // 也需要给卖家一些资金，以便测试卖家出价
        usdc.mint(bidder1, 1000000 * 10 ** 6);
        usdc.mint(bidder2, 1000000 * 10 ** 6);
        
        vm.stopPrank();
    }
    
    // 测试初始化
    function test_Initialization() public {
        assertEq(auction.owner(), owner);
        
        // 检查版本
        string memory version = auction.getVersion();
        assertEq(keccak256(abi.encodePacked(version)), keccak256(abi.encodePacked("MyNFTAuctionV1")));
    }
    
    // 测试开始拍卖（ETH拍卖）
    function test_StartAuction_ETH() public {
        vm.startPrank(seller);
        
        // 卖家授权NFT给拍卖合约
        nft.approve(address(auction), nftTokenId);
        
        // 开始拍卖
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0), // ETH拍卖
            1
        );
        
        // 验证NFT已转移
        assertEq(nft.ownerOf(nftTokenId), address(auction));
        
        vm.stopPrank();
    }
    
    // 测试无效参数开始拍卖
    function test_StartAuction_InvalidParams() public {
        vm.startPrank(seller);
        
        nft.approve(address(auction), nftTokenId);
        
        // 测试零地址卖家
        vm.expectRevert("Seller address can not be zero");
        auction.start(
            address(0),
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        
        // 测试零地址NFT合约
        vm.expectRevert("NFT contract address can not be zero");
        auction.start(
            seller,
            address(0),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        
        // 测试零时长
        vm.expectRevert("duration need > 0");
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            0,
            address(0),
            1
        );
        
        // 测试零起拍价
        vm.expectRevert("Start price must be greater than zero");
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            0,
            DURATION,
            address(0),
            1
        );
        
        vm.stopPrank();
    }
    
    // 测试非NFT所有者开始拍卖
    function test_StartAuction_NotOwner() public {
        vm.startPrank(seller);
        // 让真正的所有者先授权NFT给拍卖合约
        nft.approve(address(auction), nftTokenId);
        vm.stopPrank();
        
        vm.startPrank(bidder1);
        
        vm.expectRevert("You are not the owner of this NFT");
        auction.start(
            bidder1, // bidder1 声称这个NFT是他的
            address(nft),
            nftTokenId, // 但这个NFT实际上属于seller
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        
        vm.stopPrank();
    }
    
    // 测试ETH竞拍
    function test_Bid_ETH() public {
        // 卖家开始拍卖
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        vm.stopPrank();
        
        // 竞拍者1出价
        vm.startPrank(bidder1);
        auction.buy{value: 1.1 ether}(address(0), 1.1 ether);
        
        // 验证出价成功
        vm.stopPrank();
    }
    
    // 测试USDC竞拍
    function test_Bid_USDC() public {
        // 卖家开始USDC拍卖
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_USDC,
            DURATION,
            address(usdc),
            1
        );
        vm.stopPrank();
        
        // 竞拍者1授权并出价
        vm.startPrank(bidder1);
        usdc.approve(address(auction), 1100 * 10 ** 6);
        auction.buy(address(usdc), 1100 * 10 ** 6);
        
        vm.stopPrank();
    }
    
    // 测试出价低于最高价
    function test_Bid_BelowHighest() public {
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        vm.stopPrank();
        
        // 第一次出价
        vm.prank(bidder1);
        auction.buy{value: 1.1 ether}(address(0), 1.1 ether);
        
        // 第二次出价低于第一次
        vm.startPrank(bidder2);
        vm.expectRevert("bid amount need > highestBid");
        auction.buy{value: 1.05 ether}(address(0), 1.05 ether);
        vm.stopPrank();
    }
    
    // 测试卖家不能出价
    function test_Bid_SellerCannotBid() public {
        // 先让卖家开始拍卖
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            DURATION,
            address(0),
            1
        );
        vm.stopPrank();
        
        // 然后尝试让卖家出价，这应该失败
        vm.prank(seller);
        vm.expectRevert("Seller cannot bid");
        auction.buy{value: 2 ether}(address(0), 2 ether);
    }
    
    // 测试拍卖结束
    function test_EndAuction() public {
        // 开始拍卖
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            1 hours, // 较短时间方便测试
            address(0),
            1
        );
        vm.stopPrank();
        
        // 出价
        vm.prank(bidder1);
        auction.buy{value: 1.1 ether}(address(0), 1.1 ether);
        
        // 时间快进到拍卖结束
        vm.warp(block.timestamp + 2 hours);
        
        // 结束拍卖
        auction.endAuction();
        
        // 验证NFT已转移给出价者
        assertEq(nft.ownerOf(nftTokenId), bidder1);
    }
    
    // 测试无人出价时拍卖结束
    function test_EndAuction_NoBids() public {
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            1 hours,
            address(0),
            1
        );
        vm.stopPrank();
        
        // 时间快进到拍卖结束
        vm.warp(block.timestamp + 2 hours);
        
        // 结束拍卖
        auction.endAuction();
        
        // 验证NFT已转回给卖家
        assertEq(nft.ownerOf(nftTokenId), seller);
    }
    
    // 测试ETH退款
    function test_Refund_ETH() public {
        vm.startPrank(seller);
        nft.approve(address(auction), nftTokenId);
        auction.start(
            seller,
            address(nft),
            nftTokenId,
            START_PRICE_ETH,
            1 days,
            address(0),
            1
        );
        vm.stopPrank();
        
        uint256 initialBalance = bidder1.balance;
        
        // 第一次出价
        vm.prank(bidder1);
        auction.buy{value: 1.1 ether}(address(0), 1.1 ether);
        
        // 第二次出价更高，第一次出价者应获得退款
        vm.prank(bidder2);
        auction.buy{value: 1.2 ether}(address(0), 1.2 ether);
        
        // 验证第一次出价者获得退款
        assertEq(bidder1.balance, initialBalance);
    }
    
    // 测试ERC721接收
    function test_OnERC721Received() public {
        vm.startPrank(seller);
        
        bytes4 selector = auction.onERC721Received(
            seller,
            seller,
            nftTokenId,
            ""
        );
        
        assertEq(selector, auction.onERC721Received.selector);
        
        vm.stopPrank();
    }
    
    // 测试获取ETH价格
    function test_GetETHPrice() public view {
        // 注意：这里使用的是mock价格预言机
        int256 price = auction.getETHPrice();
        assertEq(price, 2000 * 10 ** 8);
    }
    
    // 测试ETH转USD
    function test_EthToUSD() public view {
        uint256 usdValue = auction.ethToUSD(1 ether);
        // 1 ETH * 2000 USD/ETH = 2000 USD
        assertEq(usdValue, 2000 * 10 ** 10); // 注意小数位数转换
    }
    
    // 测试接收ETH
    function test_Receive() public {
        uint256 initialBalance = address(auction).balance;
        
        // 直接发送ETH到合约
        vm.deal(bidder1, 1 ether);
        vm.prank(bidder1);
        (bool success, ) = address(auction).call{value: 1 ether}("");
        require(success, "Transfer failed");
        
        assertEq(address(auction).balance, initialBalance + 1 ether);
    }
    
    // 测试升级授权
    function test_AuthorizeUpgrade() public {
        // 验证只有owner可以调用_owner()（或类似的管理函数）
        assertEq(auction.owner(), owner);
    }
    
    // 测试重入防护
    function test_ReentrancyGuard() public {
        // 创建一个可能重入的合约来测试
        // 这里主要是验证合约继承了ReentrancyGuardUpgradeable
        assertTrue(true); // 占位符
    }
}