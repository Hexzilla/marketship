// contracts/Market.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./Mercury.sol";

contract Market is Ownable, ReentrancyGuard {
	Mercury private mercury;

    //inventory
	struct Item {
		address owner;
        uint64 minted;
		uint128 price;
		string url;
    }

	Item[] private items;
	uint256 public totalItems;

    mapping(uint256 => uint256) private indexTokens;

    constructor(Mercury _mercury) {
		mercury = _mercury;
	}

    function addItem(uint128 price, string memory url) public onlyOwner returns (uint256) {
		items.push(Item(msg.sender, 0, price, url));
		totalItems ++;
		return totalItems;
	}

	function updateItem(uint256 index, uint128 price, string memory url) public onlyOwner {
		require(index < totalItems, "Invalid item index");
		items[index] = Item(msg.sender, 0, price, url);
	}

    function mint(uint256 index) public returns (uint256) {
		require(index >= 0, "Invalid item index");
        require(index < totalItems, "Invalid item index");
		require(items[index].owner == msg.sender, "Invalid owner");
		
		uint256 tokenId = _mint(msg.sender, index);
        indexTokens[index] = tokenId;
        return tokenId;
	}

    function burn(uint256 index) public {
		require(index >= 0, "Invalid item index");
        require(index < totalItems, "Invalid item index");
		require(items[index].owner == msg.sender, "Invalid owner");

        _burn(index);
    }

    function _mint(address to, uint256 index) internal returns (uint256) {
		uint64 minted = items[index].minted;
		require(minted == 0, "Item already minted");

        items[index].minted = 1;
		return mercury.mint(to, items[index].url);
	}

    function _burn(uint256 index) internal {
		uint64 minted = items[index].minted;
		require(minted == 1, "Item not minted");

        uint256 tokenId = indexTokens[index];
        require(tokenId != 0, "Invalid token ID");

        items[index].minted = 0;
		mercury.burn(tokenId);
	}
}