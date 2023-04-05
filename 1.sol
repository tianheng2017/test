// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract DutchMarket {
    address public owner;
    mapping(address => Account) private accounts;
    mapping(uint256 => Offer) public offers;
    uint256 public lastOfferNumber;
    uint256 public offersCount;
    mapping(uint256 => Bid) public bids;
    uint256 public lastBidNumber;
    uint256 public bidsCount;
    enum Mode { DepositWithdraw, Offer, BidOpening, Matching }
    uint256 public constant timeBetweenModes = 5 minutes;
    uint256 public timeOfLastModeChange;
    Mode public currentMode;
    struct Account {
        uint256 balance;
        mapping(address => uint256) tokenBalances;
    }
    struct Bid {
        address tokenAddress;
        uint256 price;
        uint256 quantity;
        uint256 bidNumber;
        address buyer;
        address bidder;
        bytes32 blindedBid;
        bytes signature;
        bool revealed;
        bool matched;
    }
    struct Offer {
        address tokenAddress;
        uint256 price;
        uint256 quantity;
        uint256 offerNumber;
        address seller;
        bool matched;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }
    constructor() {
        owner = msg.sender;
        currentMode = Mode.DepositWithdraw;
        timeOfLastModeChange = block.timestamp;
    }
    event Deposit(address indexed tokenAddress, address indexed account, uint256 amount);
    event Withdraw(address indexed tokenAddress, address indexed account, uint256 amount);
    event OfferAdded(address indexed tokenAddress, uint256 indexed offerNumber, uint256 price, uint256 quantity, address indexed account);
    event OfferChanged(uint256 indexed offerNumber, uint256 price, address indexed account);
    event OfferRemoved(uint256 indexed offerNumber, address indexed account);
    event BidRevealed(uint256 offerNumber, address tokenAddress, uint256 indexed price, uint256 indexed quantity, address indexed bidderAddress);
    event Trade(address tokenAddress, uint256 offerNumber, uint256 bidNumber, uint256 price, uint256 indexed quantity, address indexed seller, address indexed buyer);
    function setMode(Mode mode) public onlyOwner {
        currentMode = mode;
    }
    function nextMode() public {
        if (block.timestamp >= timeOfLastModeChange + timeBetweenModes) {
            if (currentMode != Mode.Matching) {
                currentMode = Mode(uint256(currentMode) + 1);
            } else {
                currentMode = Mode.DepositWithdraw;
            }
            timeOfLastModeChange = block.timestamp;
        }
    }
    function getAccountBalance() public view returns (uint256) {
        return accounts[msg.sender].balance;
    }
    function getAccountTokenBalance(address tokenAddress) public view returns (uint256) {
        return accounts[msg.sender].tokenBalances[tokenAddress];
    }
    function depositETH() public payable {
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        require(msg.value > 0, "Amount must be greater than 0");
        accounts[msg.sender].balance += msg.value;
        emit Deposit(address(this), msg.sender, msg.value);
    }

    function withdrawETH(uint256 amount) public {
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        require(amount > 0, "Amount must be greater than 0");
        require(accounts[msg.sender].balance >= amount, "Insufficient balance");
        accounts[msg.sender].balance -= amount;
        payable(msg.sender).transfer(amount);
        emit Withdraw(address(this), msg.sender, amount);
    }
    function depositToken(address tokenAddress, uint256 amount) public {
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        require(amount > 0, "Amount must be greater than 0");
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        accounts[msg.sender].tokenBalances[tokenAddress] += amount;
        emit Deposit(tokenAddress, msg.sender, amount);
    }
    function withdrawToken(address tokenAddress, uint256 amount) public {
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        Account storage account = accounts[msg.sender];
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        require(amount > 0, "Amount must be greater than 0");
        require(account.tokenBalances[tokenAddress] >= amount, "Insufficient token balance");
        account.tokenBalances[tokenAddress] -= amount;
        require(IERC20(tokenAddress).transfer(msg.sender, amount), "Transfer failed");
        emit Withdraw(tokenAddress, msg.sender, amount);
    }

    function getOffer(uint256 offerNumber) public view returns (Offer memory) {
        require(offers[offerNumber].offerNumber != 0, "Offer not fund");
        return offers[offerNumber];
    }
    function addOffer(address tokenAddress, uint256 price, uint256 quantity) public {
        require(currentMode == Mode.Offer, "Not in Offer mode");
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        require(price > 0, "Price must be greater than 0");
        require(quantity > 0, "Quantity must be greater than 0");
        lastOfferNumber++;
        offersCount++;
        offers[lastOfferNumber] = Offer(tokenAddress, price, quantity, lastOfferNumber, msg.sender, false);
        emit OfferAdded(tokenAddress, lastOfferNumber, price, quantity, msg.sender);
    }
    function changeOffer(uint256 offerNumber, uint256 price) public {
        require(currentMode == Mode.Offer, "Not in Offer mode");
        require(offers[offerNumber].seller == msg.sender, "Only the offer creator can change the offer");
        require(price > 0, "Price must be greater than 0");
        require(offers[offerNumber].price > price, "Price can only be decreased");
        offers[offerNumber].price = price;
        emit OfferChanged(offerNumber, price, msg.sender);
    }
    function removeOffer(uint256 offerNumber) public {
        require(currentMode == Mode.Offer, "Not in Offer mode");
        require(offers[offerNumber].seller == msg.sender, "Only the offer creator can remove the offer");
        delete offers[offerNumber];
        offersCount--;
        emit OfferRemoved(offerNumber, msg.sender);
    }
    function getBid(uint256 bidNumber) public view returns (Bid memory) {
        require(bids[bidNumber].bidNumber != 0, "Bid not fund");
        return bids[bidNumber];
    }
    function addBid(
        bytes32 _blindedBid, 
        bytes memory _signature
    ) public returns (uint256) {
        require(currentMode == Mode.BidOpening, "Not in BidOpening mode");
        require(bytes32(_blindedBid).length == 32, "The blindedBid length must be 32");
        lastBidNumber++;
        bidsCount++;
        bids[lastBidNumber] = Bid(
            address(0),
            0,
            0,
            lastBidNumber,
            msg.sender,
            address(0),
            _blindedBid,
            _signature,
            false,
            false
        );
        return lastBidNumber;
    }
    function getBuyer(
        bytes32 _blindedBid, 
        bytes memory _signature
    ) public pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := and(mload(add(_signature, 65)), 255)
        }
        if (v < 27) {
            v += 27;
        }
        bytes32 prefixedBlindedBid = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _blindedBid));
        address buyer = ecrecover(prefixedBlindedBid, v, r, s);
        return buyer;
    }
    function verifyBid(
        uint256 bidNumber,
        address tokenAddress, 
        uint256 price, 
        uint256 quantity, 
        bytes32 _blindedBid
    ) public view returns (bool) {
        if (getBuyer(_blindedBid, bids[bidNumber].signature) != bids[bidNumber].buyer) {
            return false;
        }
        if (keccak256(abi.encode(tokenAddress, price, quantity, msg.sender)) != bids[bidNumber].blindedBid) {
            return false;
        }
        return true;
    }
    function BidReveal(
        uint256 bidNumber,
        address tokenAddress, 
        uint256 price, 
        uint256 quantity, 
        bytes32 _blindedBid
    ) public {
        require(currentMode == Mode.BidOpening, "Not in BidOpening mode");
        require(bids[bidNumber].bidNumber != 0, "Bid not fund");
        require(verifyBid(bidNumber, tokenAddress, price, quantity, _blindedBid), "Invalid bid");
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        require(price > 0, "Price must be greater than 0");
        require(quantity > 0, "Quantity must be greater than 0");
        bids[bidNumber].tokenAddress = tokenAddress;
        bids[bidNumber].price = price;
        bids[bidNumber].quantity = quantity;
        bids[bidNumber].revealed = true;
        bids[bidNumber].bidder = msg.sender;
        emit BidRevealed(bidNumber, tokenAddress, price, quantity, msg.sender);
    }
    function removeBid(uint256 bidNumber) public {
        require(currentMode == Mode.BidOpening, "Not in BidOpening mode");
        require(bids[bidNumber].bidNumber != 0, "Bid not fund");
        require(bids[bidNumber].buyer == msg.sender, "Only the bid creator can remove the bid");
        delete bids[bidNumber];
        bidsCount--;
    }
    function orderMaching() public {
        require(currentMode == Mode.Matching, "Not in Matching mode");
        for (uint256 i = 1; i <= lastBidNumber; i++) {
            if (bids[i].matched == true) continue;
            if (bids[i].revealed == false) continue;
            for (uint256 j = 1; j <= lastOfferNumber; j++) {
                if (bids[i].matched == true) break;
                if (
                    bids[i].matched == false &&
                    offers[j].matched == false && 
                    offers[j].tokenAddress == bids[i].tokenAddress && 
                    offers[j].price <= bids[i].price && 
                    offers[j].quantity > 0 && bids[i].quantity > 0 &&
                    offers[j].seller != bids[i].bidder
                ) {
                    uint256 quantity = offers[j].quantity < bids[i].quantity ? offers[j].quantity : bids[i].quantity;
                    uint256 cost = quantity * offers[j].price / 10 ** 18;
                    if (accounts[offers[j].seller].tokenBalances[offers[j].tokenAddress] < quantity) continue;
                    if (accounts[bids[i].bidder].balance < cost) break;
                    accounts[offers[j].seller].balance += cost;
                    accounts[offers[j].seller].tokenBalances[offers[j].tokenAddress] -= quantity;
                    offers[j].quantity -= quantity;
                    if (offers[j].quantity == 0) {
                        offers[j].matched = true;
                        offersCount--;
                    }
                    accounts[bids[i].bidder].balance -= cost;
                    accounts[bids[i].bidder].tokenBalances[bids[i].tokenAddress] += quantity;
                    bids[i].quantity -= quantity;
                    if (bids[i].quantity == 0) {
                        bids[i].matched = true;
                        bidsCount--;
                    }
                    emit Trade(offers[j].tokenAddress, offers[j].offerNumber, bids[i].bidNumber, offers[j].price, quantity, offers[j].seller, bids[i].bidder);
                }
            }
        }
    }
}
