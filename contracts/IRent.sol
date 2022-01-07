// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./IResolver.sol";

interface IRent is IERC721Receiver {
    event Lent(
        uint256 indexed tokenId,
        uint256 lendingId,
        address indexed lenderAddress,
        uint8 maxRentDuration,
        bytes4 dailyRentPrice,
        bytes4 nftPrice,
        IResolver.PaymentToken paymentToken
    );

    event Rented(
        uint256 lendingId,
        address indexed renterAddress,
        uint8 rentDuration,
        uint32 rentedAt
    );

    event Returned(uint256 indexed lendingId, uint32 returnedAt);

    event CollateralClaimed(uint256 indexed lendingId, uint32 claimedAt);

    event LendingStopped(uint256 indexed lendingId, uint32 stoppedAt);

    /**
     * @dev sends your NFT to ReNFT contract, which acts as an escrow
     * between the lender and the renter
     */
    function lend(
        uint256 _tokenId,
        uint8 _maxRentDuration,
        bytes4 _dailyRentPrice,
        bytes4 _nftPrice,
        IResolver.PaymentToken _paymentToken
    ) external;

    /**
     * @dev renter sends rentDuration * dailyRentPrice
     * to cover for the potentially full cost of renting. They also
     * must send the collateral (nft price set by the lender in lend)
     */
    function rent(
        uint256 _tokenId,
        uint256 _lendingId,
        uint8 _rentDuration
    ) external;

    /**
     * @dev renters call this to return the rented NFT before the
     * deadline. If they fail to do so, they will lose the posted
     * collateral
     */
    function returnIt(
        uint256 _tokenId,
        uint256 _lendingId
    ) external;

    /**
     * @dev claim collateral on rentals that are past their due date
     */
    function claimCollateral(
        uint256 _tokenId,
        uint256 _lendingId
    ) external;

    /**
     * @dev stop lending releases the NFT from escrow and sends it back
     * to the lender
     */
    function stopLending(
        uint256 _tokenId,
        uint256 _lendingId
    ) external;
}
