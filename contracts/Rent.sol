// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import "./IResolver.sol";
import "./IRent.sol";
import "./Mercury.sol";

contract Rent is IRent, ERC721Holder {
    using SafeERC20 for ERC20;

    Mercury private mercury;

    IResolver private resolver;
    address private admin;
    address payable private beneficiary;
    uint256 private lendingId = 1;
    bool public paused = false;

    // in bps. so 1000 => 1%
    uint256 public rentFee = 0;

    uint256 private constant SECONDS_IN_DAY = 86400;

    // single storage slot: address - 160 bits, 168, 200, 232, 240, 248
    struct Lending {
        address payable lenderAddress;
        uint8 maxRentDuration;
        bytes4 dailyRentPrice;
        bytes4 nftPrice;
        //uint8 lentAmount;
        IResolver.PaymentToken paymentToken;
    }

    // single storage slot: 160 bits, 168, 200
    struct Renting {
        address payable renterAddress;
        uint8 rentDuration;
        uint32 rentedAt;
    }

    struct LendingRenting {
        Lending lending;
        Renting renting;
    }

    mapping(bytes32 => LendingRenting) private lendingRenting;

    modifier onlyAdmin {
        require(msg.sender == admin, "Rent::not admin");
        _;
    }

    modifier notPaused {
        require(!paused, "Rent::paused");
        _;
    }

    constructor(
        address _resolver,
        address payable _beneficiary,
        address _admin
    ) {
        ensureIsNotZeroAddr(_resolver);
        ensureIsNotZeroAddr(_beneficiary);
        ensureIsNotZeroAddr(_admin);
        resolver = IResolver(_resolver);
        beneficiary = _beneficiary;
        admin = _admin;
    }

    ////////////////////////////////////////////////////////////////////////////////////
    // lend, rent, return, stop, claim
    ////////////////////////////////////////////////////////////////////////////////////

    function lend(
        uint256 _tokenId,
        uint8 _maxRentDuration,
        bytes4 _dailyRentPrice,
        bytes4 _nftPrice,
        IResolver.PaymentToken _paymentToken
    ) external override notPaused {
        handleLend(
            _tokenId,
            _maxRentDuration,
            _dailyRentPrice,
            _nftPrice,
            _paymentToken
        );
    }

    function rent(
        uint256 _tokenId,
        uint256 _lendingId,
        uint8 _rentDuration
    ) external override notPaused {
        handleRent(_tokenId, _lendingId, _rentDuration);
    }

    function returnIt(
        uint256 _tokenId,
        uint256 _lendingId
    ) external override notPaused {
        handleReturn(_tokenId, _lendingId);
    }

    function stopLending(
        uint256 _tokenId,
        uint256 _lendingId
    ) external override notPaused {
        handleStopLending(_tokenId, _lendingId);
    }

    function claimCollateral(
        uint256 _tokenId,
        uint256 _lendingId
    ) external override notPaused {
        handleClaimCollateral(_tokenId, _lendingId);
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function takeFee(uint256 _rent, IResolver.PaymentToken _paymentToken)
        private
        returns (uint256 fee)
    {
        fee = _rent * rentFee;
        fee /= 10000;
        uint8 paymentTokenIx = uint8(_paymentToken);
        ensureTokenNotSentinel(paymentTokenIx);
        ERC20 paymentToken = ERC20(resolver.getPaymentToken(paymentTokenIx));
        paymentToken.safeTransfer(beneficiary, fee);
    }

    function distributePayments(
        LendingRenting storage _lendingRenting,
        uint256 _secondsSinceRentStart
    ) private {
        uint8 paymentTokenIx = uint8(_lendingRenting.lending.paymentToken);
        ensureTokenNotSentinel(paymentTokenIx);
        address paymentToken = resolver.getPaymentToken(paymentTokenIx);
        uint256 decimals = ERC20(paymentToken).decimals();

        uint256 scale = 10**decimals;
        uint256 nftPrice = unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice =
            unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 totalRenterPmtWoCollateral =
            rentPrice * _lendingRenting.renting.rentDuration;
        uint256 sendLenderAmt =
            (_secondsSinceRentStart * rentPrice) / SECONDS_IN_DAY;
        require(
            totalRenterPmtWoCollateral > 0,
            "Rent::total payment wo collateral is zero"
        );
        require(sendLenderAmt > 0, "Rent::lender payment is zero");
        uint256 sendRenterAmt = totalRenterPmtWoCollateral - sendLenderAmt;

        uint256 takenFee =
            takeFee(sendLenderAmt, _lendingRenting.lending.paymentToken);

        sendLenderAmt -= takenFee;
        sendRenterAmt += nftPrice;

        ERC20(paymentToken).safeTransfer(
            _lendingRenting.lending.lenderAddress,
            sendLenderAmt
        );
        ERC20(paymentToken).safeTransfer(
            _lendingRenting.renting.renterAddress,
            sendRenterAmt
        );
    }

    function distributeClaimPayment(LendingRenting memory _lendingRenting)
        private
    {
        uint8 paymentTokenIx = uint8(_lendingRenting.lending.paymentToken);
        ensureTokenNotSentinel(paymentTokenIx);
        ERC20 paymentToken = ERC20(resolver.getPaymentToken(paymentTokenIx));

        uint256 decimals = ERC20(paymentToken).decimals();
        uint256 scale = 10**decimals;
        uint256 nftPrice = unpackPrice(_lendingRenting.lending.nftPrice, scale);
        uint256 rentPrice =
            unpackPrice(_lendingRenting.lending.dailyRentPrice, scale);
        uint256 maxRentPayment =
            rentPrice * _lendingRenting.renting.rentDuration;
        uint256 takenFee =
            takeFee(maxRentPayment, IResolver.PaymentToken(paymentTokenIx));
        uint256 finalAmt = maxRentPayment + nftPrice;

        require(maxRentPayment > 0, "Rent::collateral plus rent is zero");

        paymentToken.safeTransfer(
            _lendingRenting.lending.lenderAddress,
            finalAmt - takenFee
        );
    }

    function safeTransfer(
        address _from,
        address _to,
        uint256 _tokenId
    ) private {
        IERC721(mercury).transferFrom(
            _from,
            _to,
            _tokenId
        );
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function handleLend(
        uint256 _tokenId,
        uint8 _maxRentDuration,
        bytes4 _dailyRentPrice,
        bytes4 _nftPrice,
        IResolver.PaymentToken _paymentToken
    ) private {
        ensureIsLendable(_maxRentDuration, _dailyRentPrice, _nftPrice);

        LendingRenting storage item =
            lendingRenting[
                keccak256(
                    abi.encodePacked(_tokenId, lendingId)
                )
            ];

        ensureIsNull(item.lending);
        ensureIsNull(item.renting);

        item.lending = Lending({
            lenderAddress: payable(msg.sender),
            //lentAmount: nftIs721 ? 1 : uint8(_cd.lentAmounts[i]),
            maxRentDuration: _maxRentDuration,
            dailyRentPrice: _dailyRentPrice,
            nftPrice: _nftPrice,
            paymentToken: _paymentToken
        });

        emit Lent(
            _tokenId,
            lendingId,
            msg.sender,
            _maxRentDuration,
            _dailyRentPrice,
            _nftPrice,
            _paymentToken
        );

        lendingId++;

        safeTransfer(
            msg.sender,
            address(this),
            _tokenId
        );
    }

    function handleRent(
        uint256 _tokenId,
        uint256 _lendingId,
        uint8 _rentDuration
    ) private {
        LendingRenting storage item =
            lendingRenting[
                keccak256(
                    abi.encodePacked(_tokenId, _lendingId)
                )
            ];

        ensureIsNotNull(item.lending);
        ensureIsNull(item.renting);
        ensureIsRentable(item.lending, _rentDuration, msg.sender);

        uint8 paymentTokenIx = uint8(item.lending.paymentToken);
        ensureTokenNotSentinel(paymentTokenIx);
        address paymentToken = resolver.getPaymentToken(paymentTokenIx);
        uint256 decimals = ERC20(paymentToken).decimals();

        {
            uint256 scale = 10**decimals;
            uint256 rentPrice =
                _rentDuration *
                    unpackPrice(item.lending.dailyRentPrice, scale);
            uint256 nftPrice = unpackPrice(item.lending.nftPrice, scale);

            require(rentPrice > 0, "Rent::rent price is zero");
            require(nftPrice > 0, "Rent::nft price is zero");

            ERC20(paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                rentPrice + nftPrice
            );
        }

        item.renting.renterAddress = payable(msg.sender);
        item.renting.rentDuration = _rentDuration;
        item.renting.rentedAt = uint32(block.timestamp);

        emit Rented(
            _lendingId,
            msg.sender,
            _rentDuration,
            item.renting.rentedAt
        );

        safeTransfer(
            address(this),
            msg.sender,
            _tokenId
        );
    }

    function handleReturn(
        uint256 _tokenId,
        uint256 _lendingId
    ) private {
        LendingRenting storage item =
            lendingRenting[
                keccak256(
                    abi.encodePacked(_tokenId, _lendingId)
                )
            ];

        ensureIsNotNull(item.lending);
        ensureIsReturnable(item.renting, msg.sender, block.timestamp);

        uint256 secondsSinceRentStart =
            block.timestamp - item.renting.rentedAt;
        distributePayments(item, secondsSinceRentStart);

        emit Returned(_lendingId, uint32(block.timestamp));

        delete item.renting;

        safeTransfer(
            msg.sender,
            address(this),
            _tokenId
        );
    }

    function handleStopLending(
        uint256 _tokenId,
        uint256 _lendingId
    ) private {
        LendingRenting storage item =
            lendingRenting[
                keccak256(
                    abi.encodePacked(_tokenId, _lendingId)
                )
            ];

        ensureIsNotNull(item.lending);
        ensureIsNull(item.renting);
        ensureIsStoppable(item.lending, msg.sender);

        emit LendingStopped(_lendingId, uint32(block.timestamp));

        delete item.lending;

        safeTransfer(
            address(this),
            msg.sender,
            _tokenId
        );
    }

    function handleClaimCollateral(
        uint256 _tokenId,
        uint256 _lendingId
    ) private {
        LendingRenting storage item =
            lendingRenting[
                keccak256(
                    abi.encodePacked(_tokenId, _lendingId)
                )
            ];

        ensureIsNotNull(item.lending);
        ensureIsNotNull(item.renting);
        ensureIsClaimable(item.renting, block.timestamp);

        distributeClaimPayment(item);

        emit CollateralClaimed(_lendingId, uint32(block.timestamp));

        delete item.lending;
        delete item.renting;
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function unpackPrice(bytes4 _price, uint256 _scale)
        private
        pure
        returns (uint256)
    {
        ensureIsUnpackablePrice(_price, _scale);

        uint16 whole = uint16(bytes2(_price));
        uint16 decimal = uint16(bytes2(_price << 16));
        uint256 decimalScale = _scale / 10000;

        if (whole > 9999) {
            whole = 9999;
        }
        if (decimal > 9999) {
            decimal = 9999;
        }

        uint256 w = whole * _scale;
        uint256 d = decimal * decimalScale;
        uint256 price = w + d;

        return price;
    }

    function sliceArr(
        uint256[] memory _arr,
        uint256 _fromIx,
        uint256 _toIx,
        uint256 _arrOffset
    ) private pure returns (uint256[] memory r) {
        r = new uint256[](_toIx - _fromIx);
        for (uint256 i = _fromIx; i < _toIx; i++) {
            r[i - _fromIx] = _arr[i - _arrOffset];
        }
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function ensureIsNotZeroAddr(address _addr) private pure {
        require(_addr != address(0), "Rent::zero address");
    }

    function ensureIsZeroAddr(address _addr) private pure {
        require(_addr == address(0), "Rent::not a zero address");
    }

    function ensureIsNull(Lending memory _lending) private pure {
        ensureIsZeroAddr(_lending.lenderAddress);
        require(_lending.maxRentDuration == 0, "Rent::duration not zero");
        require(_lending.dailyRentPrice == 0, "Rent::rent price not zero");
        require(_lending.nftPrice == 0, "Rent::nft price not zero");
    }

    function ensureIsNotNull(Lending memory _lending) private pure {
        ensureIsNotZeroAddr(_lending.lenderAddress);
        require(_lending.maxRentDuration != 0, "Rent::duration zero");
        require(_lending.dailyRentPrice != 0, "Rent::rent price is zero");
        require(_lending.nftPrice != 0, "Rent::nft price is zero");
    }

    function ensureIsNull(Renting memory _renting) private pure {
        ensureIsZeroAddr(_renting.renterAddress);
        require(_renting.rentDuration == 0, "Rent::duration not zero");
        require(_renting.rentedAt == 0, "Rent::rented at not zero");
    }

    function ensureIsNotNull(Renting memory _renting) private pure {
        ensureIsNotZeroAddr(_renting.renterAddress);
        require(_renting.rentDuration != 0, "Rent::duration is zero");
        require(_renting.rentedAt != 0, "Rent::rented at is zero");
    }

    function ensureIsLendable(uint8 _maxRentDuration, bytes4 _dailyRentPrice, bytes4 _nftPrice) private pure {
        require(_maxRentDuration > 0, "Rent::duration is zero");
        require(_maxRentDuration <= type(uint8).max, "Rent::not uint8");
        require(uint32(_dailyRentPrice) > 0, "Rent::rent price is zero");
        require(uint32(_nftPrice) > 0, "Rent::nft price is zero");
    }

    function ensureIsRentable(
        Lending memory _lending,
        uint8 _rentDuration,
        address _msgSender
    ) private pure {
        require(
            _msgSender != _lending.lenderAddress,
            "Rent::cant rent own nft"
        );
        require(_rentDuration <= type(uint8).max, "Rent::not uint8");
        require(_rentDuration > 0, "Rent::duration is zero");
        require(_rentDuration <= _lending.maxRentDuration,
            "Rent::rent duration exceeds allowed max"
        );
    }

    function ensureIsReturnable(
        Renting memory _renting,
        address _msgSender,
        uint256 _blockTimestamp
    ) private pure {
        require(_renting.renterAddress == _msgSender, "Rent::not renter");
        require(
            !isPastReturnDate(_renting, _blockTimestamp),
            "Rent::past return date"
        );
    }

    function ensureIsStoppable(Lending memory _lending, address _msgSender)
        private
        pure
    {
        require(_lending.lenderAddress == _msgSender, "Rent::not lender");
    }

    function ensureIsClaimable(Renting memory _renting, uint256 _blockTimestamp)
        private
        pure
    {
        require(
            isPastReturnDate(_renting, _blockTimestamp),
            "Rent::return date not passed"
        );
    }

    function ensureIsUnpackablePrice(bytes4 _price, uint256 _scale)
        private
        pure
    {
        require(uint32(_price) > 0, "Rent::invalid price");
        require(_scale >= 10000, "Rent::invalid scale");
    }

    function ensureTokenNotSentinel(uint8 _paymentIx) private pure {
        require(_paymentIx > 0, "Rent::token is sentinel");
    }

    function isPastReturnDate(Renting memory _renting, uint256 _now)
        private
        pure
        returns (bool)
    {
        require(_now > _renting.rentedAt, "Rent::now before rented");
        return
            _now - _renting.rentedAt > _renting.rentDuration * SECONDS_IN_DAY;
    }

    //      .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.     .-.
    // `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'   `._.'

    function setRentFee(uint256 _rentFee) external onlyAdmin {
        require(_rentFee < 10000, "Rent::fee exceeds 100pct");
        rentFee = _rentFee;
    }

    function setBeneficiary(address payable _newBeneficiary)
        external
        onlyAdmin
    {
        beneficiary = _newBeneficiary;
    }

    function setPaused(bool _paused) external onlyAdmin {
        paused = _paused;
    }
}
