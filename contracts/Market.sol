// contracts/GameItem.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GameItem.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Market is Ownable, ReentrancyGuard {
	GameItem gameItem;

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

    constructor(GameItem _gameItem) {
		gameItem = _gameItem;
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

    function mint(address to, uint256 index) public onlyOwner returns (uint256) {
        require(index < totalItems, "Invalid item index");
		uint256 tokenId = _mint(to, index);
        indexTokens[index] = tokenId;
        return tokenId;
	}

    function burn(uint256 index) public onlyOwner {
        _burn(index);
    }

    function _mint(address to, uint256 index) internal returns (uint256) {
		uint64 minted = items[index].minted;
		require(minted == 0, "Item already minted");

        items[index].minted = 1;
		return gameItem.mint(to, items[index].url);
	}

    function _burn(uint256 index) internal {
		uint64 minted = items[index].minted;
		require(minted == 1, "Item not minted");

        uint256 tokenId = indexTokens[index];
        require(tokenId != 0, "Invalid token ID");

        items[index].minted = 0;
		gameItem.burn(tokenId);
	}
}