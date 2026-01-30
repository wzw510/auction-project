// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// 这是一个辅助合约，用于使Hardhat Ignition能够识别TransparentUpgradeableProxy
contract ProxyHelper is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address admin_,
        bytes memory _data
    ) TransparentUpgradeableProxy(_logic, admin_, _data) {}
}