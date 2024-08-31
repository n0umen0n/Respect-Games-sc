// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CommunityToken is ERC20, Ownable {

    constructor(string memory name, string memory symbol, address communityOwner) 
        ERC20(name, symbol) 
        Ownable(communityOwner)
    {
    }
}