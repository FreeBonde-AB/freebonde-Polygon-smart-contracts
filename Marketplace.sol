solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Marketplace is AccessControl, Pausable {
    using SafeMath for uint256;

    // Roles
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    // Token and NFT Addresses
    IERC20 public growToken;
    IERC20 public farmToken;
    IERC721 public digitalFarmNFT;
    IERC721 public growingSlotNFT;

    // Fee Structure
    uint256 public constant FEE_PRECISION = 1000; // 0.1% precision
    uint256 public transactionFeeRate; // e.g., 20 for 2%
    uint256 public buyBackBurnRate; // e.g., 50 for 50% of the fee
    uint256 public stakerRewardRate; // e.g., 30 for 30% of the fee
    uint256 public developmentFundRate; // e.g., 20 for 20% of the fee

    // Other Addresses
    address public buyBackBurnWallet;
    address public stakerRewardWallet;
    address public developmentFundWallet;

    // NFT Listing
    struct Listing {
        address seller;
        uint256 price;
        bool isListed;
    }

    mapping(address => mapping(uint256 => Listing)) public nftListings;

    // Events
    event NFTListed(address indexed nftContract, uint256 indexed tokenId, address indexed seller, uint256 price);
    event NFTDelisted(address indexed nftContract, uint256 indexed tokenId);
    event NFTSold(address indexed nftContract, uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);
    event TokenTransferred(address indexed tokenContract, address indexed from, address indexed to, uint256 amount);
    event FeeCollected(uint256 amount);
    event BuyBackBurn(uint256 amount);
    event StakerReward(uint256 amount);
    event DevelopmentFund(uint256 amount);
    event MintNftByGrow(address indexed user, uint256 amount, address nftContract);

    constructor(
        address _growTokenAddress,
        address _farmTokenAddress,
        address _digitalFarmNFTAddress,
        address _growingSlotNFTAddress,
        address _buyBackBurnWallet,
        address _stakerRewardWallet,
        address _developmentFundWallet
    ) {
        require(_growTokenAddress != address(0), "GROW Token address is the zero address");
        require(_farmTokenAddress != address(0), "FARM Token address is the zero address");
        require(_digitalFarmNFTAddress != address(0), "DigitalFarmNFT address is the zero address");
        require(_growingSlotNFTAddress != address(0), "GrowingSlotNFT address is the zero address");
        require(_buyBackBurnWallet != address(0), "BuyBackBurn wallet address is the zero address");
        require(_stakerRewardWallet != address(0), "StakerReward wallet address is the zero address");
        require(_developmentFundWallet != address(0), "DevelopmentFund wallet address is the zero address");

        growToken = IERC20(_growTokenAddress);
        farmToken = IERC20(_farmTokenAddress);
        digitalFarmNFT = IERC721(_digitalFarmNFTAddress);
        growingSlotNFT = IERC721(_growingSlotNFTAddress);
        buyBackBurnWallet = _buyBackBurnWallet;
        stakerRewardWallet = _stakerRewardWallet;
        developmentFundWallet = _developmentFundWallet;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);

        // Set default fee rates
        transactionFeeRate = 20;   // 2%
        buyBackBurnRate = 50;       // 50% of the fee
        stakerRewardRate = 30;      // 30% of the fee
        developmentFundRate = 20;   // 20% of the fee
    }

    // Modifier
    modifier onlyValidContract(address nftContract){
        require(nftContract == address(digitalFarmNFT) || nftContract == address(growingSlotNFT),"invalid nft contract");
        _;
    }

    // NFT Listing Functions
    function listNFT(address nftContract, uint256 tokenId, uint256 price) external onlyValidContract(nftContract) {
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "You are not the owner of this NFT");
        require(price > 0, "Price must be greater than zero");

        nftListings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            price: price,
            isListed: true
        });

        nft.approve(address(this), tokenId);
        emit NFTListed(nftContract, tokenId, msg.sender, price);
    }

    function delistNFT(address nftContract, uint256 tokenId) external onlyValidContract(nftContract){
        Listing storage listing = nftListings[nftContract][tokenId];
        require(listing.seller == msg.sender, "You are not the seller of this NFT");
        require(listing.isListed, "This NFT is not listed");

        listing.isListed = false;
        emit NFTDelisted(nftContract, tokenId);
    }

    function buyNFT(address nftContract, uint256 tokenId) external onlyValidContract(nftContract){
        Listing storage listing = nftListings[nftContract][tokenId];
        require(listing.isListed, "This NFT is not listed");
        uint256 price = listing.price;
        address seller = listing.seller;

        require(growToken.balanceOf(msg.sender) >= price, "Insufficient GROW balance");
        listing.isListed = false;

         // Transfer NFT to buyer
        IERC721 nft = IERC721(nftContract);
        nft.transferFrom(seller, msg.sender, tokenId);
         // Collect fee
        _collectFee(price);
         // Transfer payment to seller
        growToken.transferFrom(msg.sender, seller, price);

        emit NFTSold(nftContract, tokenId, seller, msg.sender, price);
    }

    // Token Transfer Function
    function transferToken(address tokenContract, address to, uint256 amount) external {
         require(tokenContract == address(growToken) || tokenContract == address(farmToken), "Invalid Token");
        IERC20 token = IERC20(tokenContract);
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");
        
        // Collect fee
        uint256 feeAmount = _collectFee(amount);

        // Transfer tokens
        token.transferFrom(msg.sender, to, amount.sub(feeAmount));
        emit TokenTransferred(tokenContract, msg.sender, to, amount);

    }

    // Internal Function to Collect Fee
     function _collectFee(uint256 amount) internal returns(uint256) {
        uint256 feeAmount = amount.mul(transactionFeeRate).div(FEE_PRECISION);
        require(growToken.transferFrom(msg.sender, address(this), feeAmount), "fee transfer failed");
        emit FeeCollected(feeAmount);

        _distributeFees(feeAmount);
        return feeAmount;
    }

    // Internal Function to Distribute Fees
    function _distributeFees(uint256 feeAmount) internal {
        uint256 buyBackBurnAmount = feeAmount.mul(buyBackBurnRate).div(100);
        uint256 stakerRewardAmount = feeAmount.mul(stakerRewardRate).div(100);
        uint256 developmentFundAmount = feeAmount.mul(developmentFundRate).div(100);

        // Buy-Back-and-Burn
        growToken.transfer(buyBackBurnWallet, buyBackBurnAmount);
        // call burnFromMarketplace in growToken.sol
        IERC20(address(growToken)).transferFrom(buyBackBurnWallet,address(growToken),buyBackBurnAmount);

        IERC20(address(growToken)).approve(address(growToken),buyBackBurnAmount);
        (bool success,) = address(growToken).call(abi.encodeWithSignature("burnFromMarketplace(uint256)", buyBackBurnAmount));
        require(success, "call burnFromMarketplace failed.");
        emit BuyBackBurn(buyBackBurnAmount);

        // Staker Reward
        growToken.transfer(stakerRewardWallet, stakerRewardAmount);
        emit StakerReward(stakerRewardAmount);

        // Development Fund
        growToken.transfer(developmentFundWallet, developmentFundAmount);
        emit DevelopmentFund(developmentFundAmount);
    }

    //update fee rate
    function updateFeeRate(uint256 newTransactionFeeRate, uint256 newBuyBackBurnRate, uint256 newStakerRewardRate, uint256 newDevelopmentFundRate) external onlyRole(FEE_MANAGER_ROLE){
         transactionFeeRate = newTransactionFeeRate;
         buyBackBurnRate = newBuyBackBurnRate;
         stakerRewardRate = newStakerRewardRate;
         developmentFundRate = newDevelopmentFundRate;
    }
    // mint nft by paying grow token.
    function mintDigitalFarmNFT(address user, uint256 amount) external {
        require(growToken.balanceOf(msg.sender) >= amount, "Insufficient GROW balance");
        require(amount >0, "Amount must be greater than zero");
        uint256 feeAmount = _collectFee(amount);
        // mint token
        (bool success,) = address(digitalFarmNFT).call(abi.encodeWithSignature("mint(address)", user));
        require(success, "mint nft failed.");
         //pay fee
        growToken.transferFrom(msg.sender,address(this),feeAmount);
        emit MintNftByGrow(user, amount, address(digitalFarmNFT));
    }

    function mintGrowingSlotNFT(address user, uint256 amount) external {
        require(growToken.balanceOf(msg.sender) >= amount, "Insufficient GROW balance");
        require(amount >0, "Amount must be greater than zero");
        uint256 feeAmount = _collectFee(amount);
        // mint token
        (bool success,) = address(growingSlotNFT).call(abi.encodeWithSignature("mint(address)", user));
        require(success, "mint nft failed.");
         //pay fee
        growToken.transferFrom(msg.sender,address(this),feeAmount);
        emit MintNftByGrow(user, amount, address(growingSlotNFT));
    }

    // Function to pause the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    // Function to unpause the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}
