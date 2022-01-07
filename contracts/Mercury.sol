// contracts/Mercury.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract Mercury is Ownable, ERC721, ERC721URIStorage, AccessControl {
    // Create a new role identifier for the minter role
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    constructor() ERC721("Mercury", "MEQ") {}

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }

    function addMinter(address minter) public onlyOwner {
        _setupRole(MINTER_ROLE, minter);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) { 
        return super.tokenURI(tokenId);
    }

    function mint(address to, string memory url) public onlyMinter returns (uint256) {
        _tokenIds.increment();

        uint256 itemId = _tokenIds.current();
        _mint(to, itemId);
        _setTokenURI(itemId, url);

        return itemId;
    }

    function burn(uint256 tokenId) public onlyMinter returns (bool) {
        _burn(tokenId);
        return true;
    }
}