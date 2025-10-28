// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ProjectPNK
 * @dev Simple ERC20 token for staking in the MiniKleros system
 */
contract ProjectPNK is ERC20, Ownable {
    constructor() ERC20("Project Pinakion", "PNK") Ownable(msg.sender) {
        // Mint initial supply to owner for testing
        _mint(msg.sender, 1_000_000 * 10**decimals());
    }

    /**
     * @dev Allows the owner to mint new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

