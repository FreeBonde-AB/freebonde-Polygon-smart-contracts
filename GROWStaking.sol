solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GROWStaking is AccessControl, Pausable {
    using SafeMath for uint256;

    // Roles
    bytes32 public constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    // GROW Token Address
    IERC20 public growToken;

    // Staking Information
    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 lockDuration;
        uint256 rewardEarned;
    }

    // Staking Tiers
    enum Tier {
        TIER_30,
        TIER_90,
        TIER_180,
        TIER_365
    }

    mapping(address => mapping(Tier => StakeInfo)) public stakeInfo;
    mapping(address => mapping(Tier => uint256)) public pendingRewards;

    // Tier Reward Multipliers
    mapping(Tier => uint256) public tierRewardMultipliers;

    // Events
    event Staked(address indexed user, Tier tier, uint256 amount);
    event Unstaked(address indexed user, Tier tier, uint256 amount);
    event RewardsClaimed(address indexed user, Tier tier, uint256 amount);

    constructor(address _growTokenAddress) {
        require(_growTokenAddress != address(0), "GROW Token address is the zero address");
        growToken = IERC20(_growTokenAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REWARD_MANAGER_ROLE, msg.sender);

        // Set default tier multipliers (these can be updated later)
        tierRewardMultipliers[Tier.TIER_30] = 100;   // 1x
        tierRewardMultipliers[Tier.TIER_90] = 125;   // 1.25x
        tierRewardMultipliers[Tier.TIER_180] = 150;  // 1.5x
        tierRewardMultipliers[Tier.TIER_365] = 200;  // 2x
    }

    modifier onlyStaked(address user, Tier tier) {
        require(stakeInfo[user][tier].amount > 0, "User has no stake in this tier");
        _;
    }

     modifier onlyValidTier(Tier tier) {
        require(uint256(tier) <= uint256(Tier.TIER_365), "Invalid tier");
        _;
    }

    function stake(uint256 amount, Tier tier) external whenNotPaused onlyValidTier(tier) {
        require(amount > 0, "Amount must be greater than zero");
        require(growToken.balanceOf(msg.sender) >= amount, "Insufficient GROW balance");
        // Transfer GROW tokens to this contract
        growToken.transferFrom(msg.sender, address(this), amount);
        uint256 lockDuration;
        if(tier == Tier.TIER_30){
             lockDuration = 30 days;
        } else if(tier == Tier.TIER_90){
             lockDuration = 90 days;
        } else if(tier == Tier.TIER_180){
             lockDuration = 180 days;
        } else {
            lockDuration = 365 days;
        }

        // Update stake information
        stakeInfo[msg.sender][tier].amount = stakeInfo[msg.sender][tier].amount.add(amount);
        stakeInfo[msg.sender][tier].startTime = block.timestamp;
        stakeInfo[msg.sender][tier].lockDuration = lockDuration;
        emit Staked(msg.sender, tier, amount);
    }

    function unstake(Tier tier) external whenNotPaused onlyStaked(msg.sender,tier) onlyValidTier(tier){
        StakeInfo storage currentStake = stakeInfo[msg.sender][tier];
         require(block.timestamp >= currentStake.startTime.add(currentStake.lockDuration), "Lock period not ended");
        uint256 amount = currentStake.amount;
        // Remove stake information
        stakeInfo[msg.sender][tier].amount = 0;
        stakeInfo[msg.sender][tier].startTime = 0;
        stakeInfo[msg.sender][tier].lockDuration = 0;

        // Transfer GROW tokens back to the user
        growToken.transfer(msg.sender, amount);
        emit Unstaked(msg.sender, tier, amount);
    }

    function claimRewards(Tier tier) external whenNotPaused onlyStaked(msg.sender,tier) onlyValidTier(tier){
         StakeInfo storage currentStake = stakeInfo[msg.sender][tier];
        uint256 earned = _calculateRewards(msg.sender, tier);
        require(earned > 0, "No rewards to claim");
        stakeInfo[msg.sender][tier].rewardEarned = stakeInfo[msg.sender][tier].rewardEarned.add(earned);
        pendingRewards[msg.sender][tier] = 0;
        // Transfer rewards to the user
        // _mint reward in GROWToken.sol
        IERC20 rewardToken = IERC20(address(growToken));
        require(rewardToken.transfer(msg.sender, earned), "reward transfer failed.");
        emit RewardsClaimed(msg.sender, tier, earned);

    }

    function _calculateRewards(address user, Tier tier) internal view returns (uint256) {
        StakeInfo storage currentStake = stakeInfo[user][tier];
        uint256 timeElapsed = block.timestamp.sub(currentStake.startTime);
        uint256 rewardMultiplier = tierRewardMultipliers[tier];
        // Example: 10% APY (adjust as needed)
        uint256 apy = 10; 
        uint256 rewards = currentStake.amount.mul(timeElapsed).mul(apy).mul(rewardMultiplier).div(365 days).div(100).div(100);
        return rewards;
    }

    function updateTierMultiplier(Tier tier, uint256 multiplier) external onlyRole(REWARD_MANAGER_ROLE) onlyValidTier(tier){
        tierRewardMultipliers[tier] = multiplier;
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
