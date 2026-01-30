// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MyNFTAuctionV2 is Initializable {
    address admin;
    uint8 private constant USD_DECIMALS = 8;


    struct Auction{
        address payable seller; // 卖家
        IERC721 nft;
        uint256 nftId;
        uint256 startingPriceInDollar; // 起拍价格
        uint256 startingTime; // 开始时间
        uint256 duration;  // 拍卖时长（单位秒）
        address highestBidder;  // 最高出价者
        uint256 highestBid;  // 最高出价
        IERC20 paymentToken; // 参与竞价的资产类型（0x0 地址表示eth，其他地址表示erc20）
        bool ended;  // 是否结束
    }
    mapping(uint256 => mapping(address => uint256)) public bids;
    mapping(uint256 => mapping(address => uint256)) public bidMethods; // 0第一次报价 1eth 2token

    mapping(uint256 => Auction) public auctions;
    uint256 public auctionId;

    AggregatorV3Interface internal priceFeed;
    
    event StartBid(uint256 startingBid);
    event Bid(address indexed sender, uint256 amount, uint256 bidMethod);
    event Withdraw(address indexed bidder, uint256 amount);
    event EndBid(uint256 indexed auctionId);

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address admin_) external initializer {
        require(admin_ != address(0),"invalid admin");
        admin = admin_;
        priceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
    }

    // 卖家发起拍卖
    function start(address seller,uint256 nftId,address nft,uint256 startingPriceInDollar,uint256 duration,address paymentToken) external onlyAdmin{
        require(nft != address(0),"Seller address can not be zero");
        require(duration > 60,"duration need > 0");
        require(paymentToken != address(0),"invalid payment token");

        auctions[auctionId] = Auction({
            seller: payable(seller),
            nft: IERC721(nft),
            nftId: nftId,
            startingPriceInDollar: startingPriceInDollar,
            startingTime: block.timestamp,
            duration: duration,
            highestBidder: address(0),
            highestBid: 0,
            paymentToken: IERC20(paymentToken),
            ended: false
        });
        auctionId++;
        emit StartBid(auctionId);
    }

    function bid(uint256 auctionId_) external payable{
        Auction memory auction = auctions[auctionId_];
        uint256 allowance = auction.paymentToken.allowance(msg.sender,address(this));
        require(msg.value > 0 || allowance > 0, "invalid bid");
        require(msg.value > 0 && allowance > 0, "only one of ETH or token");
        require(auction.startingTime > 0,"Auction not start");
        require(!auction.ended,"Auction ended");
        require(block.timestamp < auction.startingTime + auction.duration,"Auction ended");

        if(auction.highestBidder != address(0)){
            bids[auctionId_][auction.highestBidder] += auction.highestBid;
        }
        uint256 bidMethod;
        uint256 bidPrice;
        if(msg.value >0 ){
            //ETH
            bidMethod = bidMethods[auctionId_][msg.sender];
            if(bidMethod == 0){
                bidMethod = 1;
                bidMethods[auctionId_][msg.sender] = bidMethod;
            }else{
                require(bidMethod == 1, "invalid bid");
            }
            (,int256 answer,,,) = priceFeed.latestRoundData();
            uint256 price = uint256(answer);
            uint8 priceDecimals = priceFeed.decimals();
            bidPrice = _toUsd(msg.value,18,price,priceDecimals);
            auction.highestBid = msg.value;
        }
        require(auction.startingPriceInDollar < bidPrice, "invalid startingPrice");
        auction.highestBidder = msg.sender;
        emit Bid(msg.sender, msg.value, bidMethod);
    }

    function withdraw(uint256 auctionId_) internal{
        Auction memory auction = auctions[auctionId_];
        require(block.timestamp >= auction.startingTime + auction.duration, "ended");
        uint256 bal = bids[auctionId_][msg.sender];
        bids[auctionId_][msg.sender] = 0;
        payable(msg.sender).transfer(bal);
        emit Withdraw(msg.sender, bal);
    }

    function endAuction(uint256 auctionId_) public virtual{
        Auction storage auction = auctions[auctionId_];
        auction.ended = true;
        emit EndBid(auctionId_);
    }

    function _toUsd(uint256 amount, uint8 amountDecimals, uint256 price, uint8 priceDecimals)
        internal
        pure
        returns (uint256)
    {
        uint256 scale = 10 ** uint256(amountDecimals);
        uint256 usd = (amount * price) / scale;
        if (priceDecimals > USD_DECIMALS) {
            usd /= 10 ** uint256(priceDecimals - USD_DECIMALS);
        } else if (priceDecimals < USD_DECIMALS) {
            usd *= 10 ** uint256(USD_DECIMALS - priceDecimals);
        }
        return usd;
    }
    function getVersion() external pure returns (string memory) {
        return "MyNFTAuctionV2";
    }
}