// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DutchMarket {
    // 账号集合映射 
    // 账号地址 => 以太坊余额 + (代币地址 => 代币余额)数组
    mapping(address => Account) public accounts;
    // 卖单集合映射
    mapping(uint256 => Offer) public offers;
    // 买单集合映射
    mapping(uint256 => Bid) private bids;

    // 卖单数量
    uint256 public offersCount;
    // 买单数量
    uint256 public bidsCount;

    // 全局卖单号
    uint256 public lastOfferNumber;
    // 全局买单号
    uint256 public lastBidNumber;

    // 模式枚举
    enum Mode { DepositWithdraw, Offer, BidOpening, Matching }
    // 当前模式
    Mode public currentMode;
    
    // 上个模式切换时间
    uint256 public timeOfLastModeChange;
    // 模式切换间隔
    uint256 public constant timeBetweenModes = 5 minutes;

    // 合约所有者
    address public owner;

    // 账号结构体
    struct Account {
        // 托管ETH余额
        uint256 balance;
        // 托管代币余额
        mapping(address => uint256) tokenBalances;
    }

    // 买单结构体
    struct Bid {
        // 代币合约
        address tokenAddress;
        // 买价
        uint256 price;
        // 数量
        uint256 quantity;
        // 买单号
        uint256 bidNumber;
        // 买家地址
        address buyer;
        // 是否已成交
        bool matched;
    }

    // 卖单结构体
    struct Offer {
        // 代币合约
        address tokenAddress;
        // 卖价
        uint256 price;
        // 数量
        uint256 quantity;
        // 卖单号
        uint256 offerNumber;
        // 卖家地址
        address seller;
        // 是否已成交
        bool matched;
    }

    // 存取款事件
    event Deposit(address indexed tokenAddress, address indexed account, uint256 amount);
    event Withdraw(address indexed tokenAddress, address indexed account, uint256 amount);
    // 卖家事件
    event OfferAdded(address indexed tokenAddress, uint256 indexed offerNumber, uint256 price, uint256 quantity, address indexed account);
    event OfferChanged(uint256 indexed offerNumber, uint256 price, address indexed account);
    event OfferRemoved(uint256 indexed offerNumber, address indexed account);
    // 成交事件
    event Trade(address tokenAddress, uint256 offerNumber, uint256 bidNumber, uint256 price, uint256 indexed quantity, address indexed seller, address indexed buyer);

    // 合约初始化
    constructor() {
        // 设置合约所有者为合约部署者
        owner = msg.sender;
        // 设置模式为存/提款模式
        currentMode = Mode.DepositWithdraw;
        // 设置上个切换时间为当前区块时间
        timeOfLastModeChange = block.timestamp;
    }

    // 修饰器，只有合约所有者才能调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    // 获取账户托管ETH余额
    function getAccountBalance() public view returns (uint256) {
        return accounts[msg.sender].balance;
    }

    // 获取账户托管代币余额
    function getAccountTokenBalance(address tokenAddress) public view returns (uint256) {
        return accounts[msg.sender].tokenBalances[tokenAddress];
    }

    // 获取卖单信息
    function getOffer(uint256 offerNumber) public view returns (address tokenAddress, uint256 price, uint256 quantity, address seller) {
        Offer memory offer = offers[offerNumber];
        return (offer.tokenAddress, offer.price, offer.quantity, offer.seller);
    }

    // 获取买单信息
    function getBid(uint256 bidNumber) public view returns (address tokenAddress, uint256 price, uint256 quantity, address buyer) {
        Bid memory bid = bids[bidNumber];
        return (bid.tokenAddress, bid.price, bid.quantity, bid.buyer);
    }

    // 强制设置模式
    // 方便测试，正式环境不需要
    function setMode(Mode mode) public onlyOwner {
        currentMode = mode;
    }

    // 切换到下个模式，外部定时任务触发
    function nextMode() public {
        // 检查是否间隔5分钟以上
        if (block.timestamp >= timeOfLastModeChange + timeBetweenModes) {
            // 如果不是最后一个模式，递增
            if (currentMode != Mode.Matching) {
                currentMode = Mode(uint256(currentMode) + 1);
            } else {
                // 否则从头开始
                currentMode = Mode.DepositWithdraw;
            }
            // 记录模式切换时间为当前区块时间
            timeOfLastModeChange = block.timestamp;
        }
    }

    // ETH存款
    function depositETH() public payable {
        // 校验模式
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        // 检查存款金额必须大于0
        require(msg.value > 0, "Amount must be greater than 0");
        // 托管ETH余额增加
        accounts[msg.sender].balance += msg.value;
        // 发出ETH存款事件
        emit Deposit(address(this), msg.sender, msg.value);
    }

    // ETH提款
    function withdrawETH(uint256 amount) public {
        // 校验模式
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        // 检查提款金额必须大于0
        require(amount > 0, "Amount must be greater than 0");
        // 检查托管ETH余额必须 >= 提款金额
        require(accounts[msg.sender].balance >= amount, "Insufficient balance");
        // 托管ETH余额扣除
        accounts[msg.sender].balance -= amount;
        // 用户钱包余额增加
        payable(msg.sender).transfer(amount);
        // 发出ETH提款事件
        emit Withdraw(address(this), msg.sender, amount);
    }

    // token存款
    function depositToken(address tokenAddress, uint256 amount) public {
        // 校验模式
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        // 确保是代币地址是有效地址
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        // 检查存款金额
        require(amount > 0, "Amount must be greater than 0");
        // 划转token到合约
        require(IERC20(tokenAddress).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        // 账户token余额增加
        accounts[msg.sender].tokenBalances[tokenAddress] += amount;
        // 发出代币存款事件
        emit Deposit(tokenAddress, msg.sender, amount);
    }

    // token提款
    function withdrawToken(address tokenAddress, uint256 amount) public {
        // 校验模式
        require(currentMode == Mode.DepositWithdraw, "Not in DepositWithdraw mode");
        // 传引用
        Account storage account = accounts[msg.sender];
        // 确保是代币地址是有效地址
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        // 检查提款金额必须大于0
        require(amount > 0, "Amount must be greater than 0");
        // 检查账户余额必须 >= 提款金额
        require(account.tokenBalances[tokenAddress] >= amount, "Insufficient token balance");
        // 账户扣款
        account.tokenBalances[tokenAddress] -= amount;
        // 用户钱包代币增加
        require(IERC20(tokenAddress).transfer(msg.sender, amount), "Transfer failed");
        // 发出提款事件
        emit Withdraw(tokenAddress, msg.sender, amount);
    }

    // 提交卖单，参数：erc20合约地址，卖出价格、卖出数量
    function addOffer(address tokenAddress, uint256 price, uint256 quantity) public {
        // 校验模式
        require(currentMode == Mode.Offer, "Not in Offer mode");
        // 传引用
        Account storage account = accounts[msg.sender];
        // 确保是代币地址是有效地址
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        // 卖出价格必须大于0
        require(price > 0, "Price must be greater than 0");
        // 卖出数量必须大于0
        require(quantity > 0, "Quantity must be greater than 0");
        // 账户里面代币余额必须 >= 卖出数量
        require(account.tokenBalances[tokenAddress] >= quantity, "Insufficient token balance");
        // 全局卖单号递增
        lastOfferNumber++;
        // 卖单数量递增
        offersCount++;
        // 创建卖单
        offers[lastOfferNumber] = Offer(tokenAddress, price, quantity, lastOfferNumber, msg.sender, false);
        // 账户代币余额减少
        account.tokenBalances[tokenAddress] -= quantity;
        // 发出卖单事件
        emit OfferAdded(tokenAddress, lastOfferNumber, price, quantity, msg.sender);
    }

    // 修改卖单，参数：卖单号，卖出价格
    function changeOffer(uint256 offerNumber, uint256 price) public {
        // 校验模式
        require(currentMode == Mode.Offer, "Not in Offer mode");
        // 卖出价格必须大于0
        require(price > 0, "Price must be greater than 0");
        // 鉴权，只有卖单创建者才能修改
        require(offers[offerNumber].seller == msg.sender, "Only the offer creator can change the offer");
        // 卖家只能降低价格，不能提高价格
        require(offers[offerNumber].price > price, "Price can only be decreased");
        // 更新卖出价格
        offers[offerNumber].price = price;
        // 发出卖单修改事件
        emit OfferChanged(offerNumber, price, msg.sender);
    }

    // 删除卖单(撤单)，参数：卖单号
    function removeOffer(uint256 offerNumber) public {
        // 校验模式
        require(currentMode == Mode.Offer, "Not in Offer mode");
        // 鉴权，只有卖单创建者才能删除
        require(offers[offerNumber].seller == msg.sender, "Only the offer creator can remove the offer");
        // 账户代币余额增加
        accounts[msg.sender].tokenBalances[offers[offerNumber].tokenAddress] += offers[offerNumber].quantity;
        // 删除卖单
        delete offers[offerNumber];
        // 卖单数量减少
        offersCount--;
        //  发出卖单删除事件
        emit OfferRemoved(offerNumber, msg.sender);
    }

    // 提交买单，参数：erc20合约地址，买入价格、买入数量
    function addBid(address tokenAddress, uint256 price, uint256 quantity) public {
        // 校验模式
        require(currentMode == Mode.BidOpening, "Not in BidOpening mode");
        // 确保是代币地址是有效地址
        require(tokenAddress != address(0) && tokenAddress != address(this), "Invalid Token Address");
        // 买入价格必须大于0
        require(price > 0, "Price must be greater than 0");
        // 买入数量必须大于0
        require(quantity > 0, "Quantity must be greater than 0");
        // 计算实际金额
        uint256 amount = price * quantity / 10 ** 18;
        // 托管账户ETH余额必须 >= 买入价格 * 买入数量
        require(accounts[msg.sender].balance >= amount, "Insufficient ETH balance");
        // 全局买单号递增
        lastBidNumber++;
        // 买单数量递增
        bidsCount++;
        // 创建买单
        bids[lastBidNumber] = Bid(tokenAddress, price, quantity, lastBidNumber, msg.sender, false);
        // 账户ETH余额减少
        accounts[msg.sender].balance -= amount;
    }
    
    // 删除买单(撤单)，参数：买单号
    function removeBid(uint256 bidNumber) public {
        // 校验模式
        require(currentMode == Mode.BidOpening, "Not in BidOpening mode");
        // 鉴权，只有买单创建者才能删除
        require(bids[bidNumber].buyer == msg.sender, "Only the bid creator can remove the bid");
        // 账户ETH余额增加
        accounts[msg.sender].balance += (bids[bidNumber].price * bids[bidNumber].quantity) / 10 ** 18;
        // 删除买单
        delete bids[bidNumber];
        // 买单数量减少
        bidsCount--;
    }
    
    // 匹配订单
    function matching() public {
        // 校验模式
        require(currentMode == Mode.Matching, "Not in Matching mode");
        // 遍历所有买单，订单号从1开始递增，代表优先处理等待时间最长的
        for (uint256 i = 1; i <= lastBidNumber; i++) {
            // 跳过已经完全成交的买单
            if (bids[i].matched == true) continue;

            // 遍历所有卖单，订单号从1开始递增，同样代表优先处理等待时间最长的
            for (uint256 j = 1; j <= lastOfferNumber; j++) {
                // 如果买单已经完全成交，不再继续匹配其他卖单
                if (bids[i].matched == true) break;

                // 如果买卖单都未成交，买卖双方代币也相同，且卖单价格 <= 买单价格，且卖单数量 > 0，且买单数量 > 0
                if (
                    bids[i].matched == false &&
                    offers[j].matched == false && 
                    offers[j].tokenAddress == bids[i].tokenAddress && 
                    offers[j].price <= bids[i].price && 
                    offers[j].quantity > 0 && bids[i].quantity > 0
                ) {
                    // 交易数量 = 卖单数量 < 买单数量 ? 卖单数量 : 买单数量
                    uint256 quantity = offers[j].quantity < bids[i].quantity ? offers[j].quantity : bids[i].quantity;

                    // 交易金额 = 交易数量 * 卖单价格
                    // 在价格为p的卖出报价与价格为 q ≥ p 的买入订单匹配时，买家始终是支付更低的价格p
                    uint256 cost = quantity * offers[j].price / 10 ** 18;

                    // 卖家获得ETH
                    accounts[offers[j].seller].balance += cost;
                    // 卖单数量减少
                    offers[j].quantity -= quantity;
                    // 如果卖单数量为0，标记为已成交
                    if (offers[j].quantity == 0) {
                        // 标记为已成交
                        offers[j].matched = true;
                        // 总卖单减少
                        offersCount--;
                    }

                    // 买家获得代币
                    accounts[bids[i].buyer].tokenBalances[bids[i].tokenAddress] += quantity;
                    // 买单数量减少
                    bids[i].quantity -= quantity;
                    // 如果买单数量为0，标记为已成交
                    if (bids[i].quantity == 0) {
                        // 买单标记为已成交
                        bids[i].matched = true;
                        // 总买单减少
                        bidsCount--;
                    }
                    // 如果买家价格比卖家价格大，且以卖家的价格成交了，需要返还买家ETH差额
                    // 因为：在价格为p的卖出报价与价格为 q ≥ p 的买入订单匹配时，买家始终是支付更低的价格p，故需要返还买家ETH差额
                    if (offers[j].price < bids[i].price) {
                        accounts[bids[i].buyer].balance += quantity * (bids[i].price - offers[j].price) / 10 ** 18;
                    }

                    // 发出成交事件
                    // 公开卖单号、买单号、价格、数量、卖家、买家
                    emit Trade(offers[j].tokenAddress, offers[j].offerNumber, bids[i].bidNumber, offers[j].price, quantity, offers[j].seller, bids[i].buyer);
                }
            }
        }
    }
}
