# NFT拍卖系统

一个基于以太坊的去中心化NFT拍卖智能合约系统，支持ETH和ERC20代币拍卖。

## 功能特性

- 支持ETH和ERC20代币的NFT拍卖
- 可升级智能合约架构 (UUPS)
- Chainlink价格预言机集成

## 项目结构

```
auction-project/
├── contracts/           # 智能合约源码
│   ├── MyNFTAuction.sol # 主拍卖合约
│   ├── MyNFTAuctionV2.sol # V2版本合约
│   ├── MyNFT.sol        # NFT示例合约
├── ignition/           # Hardhat Ignition 部署模块
│   └── modules/        # 部署脚本
├── scripts/            # 部署脚本
├── test/               # 测试文件
└── lib/                # 依赖库
```

## 环境设置

```bash
# 安装依赖
npm install

# 编译合约
forge build
```

## 测试

```bash
# 运行所有测试
forge test

# 查看测试覆盖率
forge coverage

# 运行特定测试
forge test --match-test testName
```

## 部署

### 本地部署

```bash
# 使用Hardhat Ignition部署
npx hardhat ignition deploy ./ignition/modules/MyNFTAuctionDeployModule.ts
```

### 测试网部署

```bash
# Sepolia测试网
npx hardhat ignition deploy ./ignition/modules/MyNFTAuctionDeployModule.ts --network sepolia
```

## 合约地址

### 测试网部署
- **Sepolia测试网**:
  - 实现合约地址: `0xfaD46c2D71F48E35Bb0d76B234CD167Fe282eBc5`
  - 代理合约地址: `0x39e75A6d09879a93906b969a7073962Ea28B8aaa`
  - 可访问合约地址: `0x39e75A6d09879a93906b969a7073962Ea28B8aaa`


### 各合约文件覆盖率详情

| 合约文件 | 行覆盖率 | 语句覆盖率 | 分支覆盖率 | 函数覆盖率 |
|----------|----------|------------|------------|------------|
| contracts/MyNFT.sol | 0.00% (0/30) | 0.00% (0/27) | 0.00% (0/1) | 0.00% (0/6) |
| contracts/MyNFTAuction.sol | 88.42% (84/95) | 90.57% (96/106) | 68.25% (43/63) | 85.71% (12/14) |
| contracts/MyNFTAuction.t.sol | 100.00% (11/11) | 100.00% (7/7) | 100.00% (0/0) | 100.00% (4/4) |
| contracts/MyNFTAuctionV2.sol | 0.00% (0/62) | 0.00% (0/58) | 0.00% (0/33) | 0.00% (0/9) |
| contracts/NFTAuctionV1.sol | 0.00% (0/85) | 0.00% (0/91) | 0.00% (0/32) | 0.00% (0/12) |

## Gas 使用报告

### 主要函数 Gas 消耗统计
| 函数名 | 最小 Gas | 平均 Gas | 中位数 Gas | 最大 Gas | 调用次数 |
|--------|----------|----------|------------|----------|----------|
| buy | 24,463 | 88,816 | 103,185 | 140,151 | 8 |
| endAuction | 97,391 | 98,385 | 98,385 | 99,380 | 2 |
| ethToUSD | 9,906 | 9,906 | 9,906 | 9,906 | 1 |
| getETHPrice | 9,172 | 9,172 | 9,172 | 9,172 | 1 |
| getVersion | 661 | 661 | 661 | 661 | 1 |
| initialize | 92,977 | 92,977 | 92,977 | 92,977 | 17 |
| onERC721Received | 1,324 | 1,324 | 1,324 | 1,324 | 1 |
| owner | 2,582 | 2,582 | 2,582 | 2,582 | 2 |
| receive | 21,055 | 21,055 | 21,055 | 21,055 | 1 |
| setPriceFeed | 46,397 | 46,397 | 46,397 | 46,397 | 17 |
| start | 24,069 | 152,652 | 229,584 | 249,700 | 13 |

### 合约部署成本
| 合约 | 部署 Gas 成本 | 部署大小 (字节) |
|------|---------------|-----------------|
| MyNFTAuction | 3,923,625 | 18,119 |
| MockERC20 | 925,027 | 5,217 |
| MockERC721 | 1,768,454 | 9,136 |
| MockPriceFeed | 212,068 | 845 |