// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract MultiProxyAdmin is ProxyAdmin {
    mapping(address => bool) public upgradesLocked;

    event UpgradesLocked(address indexed proxy);

    constructor(address initialOwner) ProxyAdmin(initialOwner) {}

    function upgradeAndCall(ITransparentUpgradeableProxy proxy, address implementation, bytes memory data) public payable override {
        require(!upgradesLocked[address(proxy)], "Upgrades are locked for this proxy");
        super.upgradeAndCall(proxy, implementation, data);
    }

    function lockUpgrades(ITransparentUpgradeableProxy proxy) public onlyOwner {
        require(!upgradesLocked[address(proxy)], "Upgrades are already locked for this proxy");
        upgradesLocked[address(proxy)] = true;
        emit UpgradesLocked(address(proxy));
    }
}