// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract NFTAuctionV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    
    struct Auction{
        address seller;
        address nftAddress;
        uint256 tokenId;
        uint256 startPrice;
        uint256 endPrice;
        uint256 startTime;
        uint256 duration;
        address highestBidder;
        uint256 soldPrice;
        bool ended;
    }

    mapping(uint256 => Auction) public auctions;

    uint256 public auctionIdCounter;

    AggregatorV3Interface internal priceFeed;
    
    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftAddress,
        uint256 tokenId,
        uint256 startPrice,
        uint256 endPrice,
        uint256 startTime,
        uint256 duration    
    );

    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 price
    );

    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 price
    );

    constructor(){
        _disableInitializers();
    }

    function initialize(address _priceFeed) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        auctionIdCounter = 1;
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner{}

    function getETHPrice() public view returns(int256){
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function ethToUSD(uint256 ethAmount) public view returns(uint256){
        int256 ethPrice = getETHPrice();
        require(ethPrice > 0, "Invalid ETH price");
        return (uint256(ethPrice) * ethAmount)/1e8;
    }

    function createAuction(address nftAddress,uint256 tokenId,uint256 startPrice,uint256 endPrice,uint256 duration) external{
        require(startPrice > endPrice, "Start price must be greater than end price");
        require(duration > 0,"Duration must > 0");

        IERC721 nft = IERC721(nftAddress);
        require(nft.ownerOf(tokenId) == msg.sender,"You are not the owner of this NFT");
        nft.transferFrom(msg.sender, address(this), tokenId);

        uint256 newAuctionId = auctionIdCounter;
        auctionIdCounter++;

        auctions[newAuctionId] = Auction({
            seller: msg.sender,
            nftAddress: nftAddress,
            tokenId: tokenId,
            startPrice: startPrice,
            endPrice: endPrice,
            startTime: block.timestamp,
            duration: duration,
            highestBidder: address(0),
            soldPrice: 0,
            ended: false
        });
         emit AuctionCreated(
            newAuctionId,
            msg.sender,
            nftAddress,
            tokenId,
            startPrice,
            endPrice,
            block.timestamp,
            duration
        );
    }

    function  getCurrentPrice(uint256 auctionId) public view returns(uint256){
        Auction memory auction = auctions[auctionId];

        require(auction.startTime > 0,"Auction not exists");

        if(block.timestamp >= auction.startTime + auction.duration){
            return auction.endPrice;
        }

        uint256 timePassed = block.timestamp - auction.startTime;
        uint256 priceRange = auction.startPrice - auction.endPrice;
        uint256 priceDecrease = priceRange * timePassed / auction.duration;

        return auction.startPrice - priceDecrease;
    }

    function getCurrentPriceUSD(uint256 auctionId) public view returns (uint256) {
        uint256 currentPrice = getCurrentPrice(auctionId);
        return ethToUSD(currentPrice);
    }

    function buy(uint256 auctionId) external payable{
        Auction storage auction = auctions[auctionId];
        require(auction.startTime > 0,"Auction not exists");
        require(!auction.ended,"Auction ended");
        require(block.timestamp < auction.startTime + auction.duration,"Auction ended");
        uint256 currentPrice = getCurrentPrice(auctionId);
        require(msg.value >= currentPrice,"Insufficient bid");
        auction.ended = true;
        auction.highestBidder = msg.sender;
        auction.soldPrice = currentPrice;

        IERC721 nft = IERC721(auction.nftAddress);
        nft.transferFrom(address(this), msg.sender, auction.tokenId);

        uint256 refund = msg.value - currentPrice;
        if(refund > 0){
            payable(msg.sender).transfer(refund);
        }

        payable(auction.seller).transfer(currentPrice);

        emit BidPlaced(auctionId,msg.sender,currentPrice);
        emit AuctionEnded(auctionId,msg.sender,currentPrice);
    }

    function cancelAuction(uint256 auctionId) external{
        Auction storage auction  = auctions[auctionId];
        require(msg.sender == auction.seller,"Not Seller");
        require(!auction.ended,"Already ended");
        require(auction.highestBidder == address(0),"Already bought");

        auction.ended = true;

        IERC721 nft = IERC721(auction.nftAddress);
        nft.transferFrom(address(this), auction.seller, auction.tokenId);
    }

    function settleAuction(uint256 auctionId) external{
        Auction storage auction = auctions[auctionId];
        require(!auction.ended,"Auction ended");
        require(block.timestamp >= auction.startTime + auction.duration,"Auction not ended");
        auction.ended = true;

        // 如果有买家，转移NFT，否则退回给卖家
        if(auction.highestBidder != address(0)){
            IERC721 nft = IERC721(auction.nftAddress);
            nft.transferFrom(address(this), auction.highestBidder, auction.tokenId);
            // 转移资金给卖家
            payable(auction.seller).transfer(auction.soldPrice);
        }else{
             // 无人出价，退回NFT
            IERC721 nft = IERC721(auction.nftAddress);
            nft.transferFrom(address(this), auction.seller, auction.tokenId);
        }
    }

    function getAuction(uint256 auctionId) external view returns(
        address seller,
        address nftAddress,
        uint256 tokenId,
        uint256 currentPrice,
        uint256 currentPriceUSD,
        uint256 startTime,
        uint256 endTime,
        address highestBidder,
        bool ended
    ){
        Auction memory auction = auctions[auctionId];

        seller = auction.seller;
        nftAddress = auction.nftAddress;
        tokenId = auction.tokenId;
        currentPrice = getCurrentPrice(auctionId);
        currentPriceUSD = getCurrentPriceUSD(auctionId);
        startTime = auction.startTime;
        endTime = auction.startTime + auction.duration;
        highestBidder = auction.highestBidder;
        ended = auction.ended;
    }

    receive() external payable{}
}