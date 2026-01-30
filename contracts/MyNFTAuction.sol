// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MyNFTAuction is IERC721Receiver,
                        Initializable,
                        OwnableUpgradeable,
                        UUPSUpgradeable,
                        ReentrancyGuardUpgradeable 
{
    struct Auction{
        address seller; // 卖家
        address nftContract; // 拍卖的NFT合约地址
        uint256 tokenId; // NFT ID
        uint256 startPrice; // 起拍价格
        uint256 startTime; // 开始时间
        uint256 duration;  // 拍卖时长（单位秒）
        address highestBidder;  // 最高出价者
        uint256 highestBid;  // 最高出价
        address payToken; // 参与竞价的资产类型（0x0 地址表示eth，其他地址表示erc20）
        bool ended;  // 是否结束
        uint256 auctionId;  //拍卖ID
    }
    Auction private auctionInfo; //拍卖信息存储

    //mapping(uint256 => Auction) public auctions;
    //uint256 public auctionIdCounter;

    AggregatorV3Interface internal priceFeed;
    
    event AuctionCreated(
        address indexed seller,
        address indexed nftContract,
        uint256 startTime,
        uint256 duration,
        uint256 startPrice,
        uint256 tokenId,
        address payToken,
        uint256 auctionId
    );

    // 竞拍出价事件
    event BidPlaced(
        address indexed bidder,
        address indexed nftContract,
        uint256 tokenId,
        uint256 bid,
        address payToken
    );

    // 拍卖结束事件
    event AuctionEnded(
        address indexed winner,
        address indexed nftContract,
        uint256 tokenId,
        uint256 amount,
        address payToken
    );

    constructor(){
        // 在测试环境中，我们允许初始化
        // 在生产环境中，应在部署代理时使用 _disableInitializers()
    }

    function initialize() public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        //auctionIdCounter = 1;
        // 在测试中，我们会通过其他方式设置价格预言机
    }
    
    function setPriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function getETHPrice() public view returns(int256){
        (,int256 price,,,) = priceFeed.latestRoundData();
        return price;
    }

    function ethToUSD(uint256 ethAmount) public view returns(uint256){
        int256 ethPrice = getETHPrice();
        require(ethPrice > 0, "Invalid ETH price");
        // ethPrice是以8位小数表示的USD价格 (e.g., 2000 USD = 2000 * 10**8)
        // ethAmount是以18位小数表示的ETH数量 (e.g., 1 ETH = 10**18)
        // 我们希望返回以10位小数表示的USD金额
        // 计算: ETH数量 * ETH/USD价格 = USD金额
        // (10**18) * (2000 * 10**8) / 10**16 = 2000 * 10**10
        return (uint256(ethPrice) * ethAmount) / 10**16;
    }

    // 卖家发起拍卖
    function start(address _seller,address _nftContract,uint256 _tokenId,uint256 _startPrice,uint256 _duration,address _payToken,uint256 _auctionId) external{
        require(_seller != address(0),"Seller address can not be zero");
        require(_nftContract != address(0),"NFT contract address can not be zero");
        require(_duration > 0,"duration need > 0");
        require(_startPrice > 0, "Start price must be greater than zero");
        require(_tokenId > 0,"tokenId need > 0");

        IERC721 nft = IERC721(_nftContract);
        require(nft.ownerOf(_tokenId) == _seller,"You are not the owner of this NFT");
        nft.transferFrom(msg.sender, address(this), _tokenId);

        auctionInfo = Auction(
            msg.sender,
            _nftContract,
            _tokenId,
            _startPrice,
            block.timestamp,
            _duration,
            address(0),
            0,
            _payToken,
            false,
            _auctionId
        );
         emit AuctionCreated(
            _seller,
            _nftContract,
            block.timestamp,
            _duration,
            _startPrice,
            _tokenId,
            _payToken,
            _auctionId
        );
    }

    function buy(address _payToken,uint256 _amount) external payable{
        // 禁止卖家自己出价 - 这个检查应该放在最前面，以避免不必要的计算
        require(msg.sender != auctionInfo.seller, "Seller cannot bid");
        
        require(auctionInfo.startTime > 0,"Auction not exists");
        require(!auctionInfo.ended,"Auction ended");
        require(block.timestamp < auctionInfo.startTime + auctionInfo.duration,"Auction ended");
        if(_payToken == address(0)){
            // ETH 出价，当此函数成功执行后，msg.value对应的ETH会自动存入本合约余额中
            require(msg.value == _amount,"Insufficient bid");
        }else{
            // ERC20 出价
            require(msg.value == 0, "ERC20 bid need not send ETH");
            // 查询用户是否授权拍卖合约可以操作该ERC20代币金额大于等于此次支付金额
            require(IERC20(_payToken).allowance(msg.sender, address(this)) >= _amount, "ERC20 allowance not enough");
        }

        require(_amount > 0, "bid amount need > 0");    // 出价金额必须大于0

        // 得到当前最高出价的USD价值
        uint256 hightestUSD = _getHightestUSDValue();
        // 计算出价的USD价值
        uint256 bidUSDValue = _calculateBidUSDValue(_payToken, _amount);
        require(bidUSDValue > hightestUSD, "bid amount need > highestBid");

        // 竞拍出价成功，如果是ERC20出价，则需要把出价金额转到本合约
        if (_payToken != address(0)) {
            bool transferSuccess = IERC20(_payToken).transferFrom(msg.sender, address(this), _amount);
            require(transferSuccess, "ERC20 transfer failed");
        }

        if (auctionInfo.highestBidder != address(0) && auctionInfo.highestBid > 0) {
            // 存在上一个出价者，退还上一个出价者出价金额
            _refund(auctionInfo.highestBidder, auctionInfo.payToken, auctionInfo.highestBid);
        }

        // 更新最高出价
        auctionInfo.highestBidder = msg.sender;
        auctionInfo.highestBid = _amount;
        auctionInfo.payToken = _payToken;

        emit BidPlaced(
            msg.sender,
            auctionInfo.nftContract,
            auctionInfo.tokenId,
            _amount,
            _payToken
        );
    }

    function _refund(address to, address tokenAddress, uint256 amount) internal{
        if(tokenAddress == address(0)){
             //payable(to).transfer(amount);
            (bool success,) = to.call{value: amount}("");
            require(success,"ETH refund failed");
        }else{
            bool success = IERC20(tokenAddress).transfer(to,amount);
            require(success, "ERC20 refund failed");
        }
    }

    function endAuction() public virtual{
        require(!auctionInfo.ended, "Auction ended");
        require(block.timestamp >= auctionInfo.startTime + auctionInfo.duration,"auction not ended");

        auctionInfo.ended = true;
        IERC721 nft = IERC721(auctionInfo.nftContract);

        if(auctionInfo.highestBidder != address(0)){
            // 如果有人出价，则将NFT转给最高出价者，扣除手续费后把剩余的金额转给卖家
            nft.safeTransferFrom(address(this), auctionInfo.highestBidder, auctionInfo.tokenId);
        }else{
            // 如果无人出价，则将NFT转回给卖家
            nft.safeTransferFrom(address(this), auctionInfo.seller, auctionInfo.tokenId);
        }
        emit AuctionEnded(
            auctionInfo.highestBidder,
            auctionInfo.nftContract,
            auctionInfo.tokenId,
            auctionInfo.highestBid,
            auctionInfo.payToken
        );
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
        seller = auctionInfo.seller;
        nftAddress = auctionInfo.nftContract;
        tokenId = auctionInfo.tokenId;
        //currentPrice = getCurrentPrice(auctionId);
        //currentPriceUSD = getCurrentPriceUSD(auctionId);
        startTime = auctionInfo.startTime;
        endTime = auctionInfo.startTime + auctionInfo.duration;
        highestBidder = auctionInfo.highestBidder;
        ended = auctionInfo.ended;
    }

    function _calculateBidUSDValue(
        address _payToken,
        uint256 _amount
    ) internal view virtual returns (uint256) {
        require(address(priceFeed) != address(0), "Price feed not set for payToken");
        
        (, int256 priceRaw, , , ) = priceFeed.latestRoundData();
        require(priceRaw > 0, "Invalid price from feed");
        uint256 price = uint256(priceRaw);
        uint256 feedDecimal = priceFeed.decimals();
        if (address(0) == _payToken) {
            return price * _amount / (10**(12 + feedDecimal));  // ETH 10**(18 + feedDecimal - 6) = 10**(12 + feedDecimal)
        } else {
            return price * _amount / (10**(feedDecimal));  // USDC 10**(6 + feedDecimal - 6) = 10**feedDecimal
        }
    }

    // 计算当前拍卖最高出价的 USD 价值
    function _getHightestUSDValue() internal view virtual returns (uint256) {
        require(address(priceFeed) != address(0), "Price feed not set for payToken");
        (, int256 priceRaw, , , ) = priceFeed.latestRoundData();
        require(priceRaw > 0, "Invalid price from feed");
        uint256 price = uint256(priceRaw); // 获取价格预言机喂价
        uint256 feedDecimal = priceFeed.decimals(); // 获取价格预言机小数位数

        // 获取当前最高出价，默认为起拍价格，如果有人出价，则最高出价为最高出价
        uint256 hightestAmount = auctionInfo.startPrice;
        if (auctionInfo.highestBidder != address(0)) {
            hightestAmount = auctionInfo.highestBid;
        }
        if (address(0) == auctionInfo.payToken) {
            return price * hightestAmount / (10**(12 + feedDecimal));  // ETH 10**(18 + feedDecimal - 6) = 10**(12 + feedDecimal)
        } else {
            return price * hightestAmount / (10**(feedDecimal));  // USDC 10**(6 + feedDecimal - 6) = 10**feedDecimal
        }
    }

    function getVersion() external pure returns (string memory) {
        return "MyNFTAuctionV1";
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    receive() external payable{}
}