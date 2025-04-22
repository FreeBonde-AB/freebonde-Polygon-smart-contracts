solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract Insurance is AccessControl, Pausable {
    using SafeMath for uint256;

    // Roles
    bytes32 public constant CLAIM_VALIDATOR_ROLE = keccak256("CLAIM_VALIDATOR_ROLE");

    // Token Addresses
    IERC20 public growToken;
    IERC20 public farmToken;

    // Insurance Pool
    struct InsurancePool {
        string name;
        uint256 balance;
        uint256 premiumRate;
    }

    // Coverage Level
    struct CoverageLevel {
        string name;
        uint256 coverageAmount;
        uint256 premium;
        bool active;
    }

    // Claim
    struct Claim {
        address claimant;
        uint256 amount;
        string description;
        bool validated;
        bool paid;
        uint256 poolId;
        uint256 coverageId;
    }

    // Mappings
    mapping(uint256 => InsurancePool) public insurancePools;
    mapping(uint256 => mapping(uint256 => CoverageLevel)) public coverageLevels;
    mapping(uint256 => Claim) public claims;
    mapping(address => mapping(uint256 => uint256)) public userCoverage; // user address => pool id => coverage id

    // Counters
    uint256 public insurancePoolCount;
    uint256 public coverageLevelCount;
    uint256 public claimCount;

    // Events
    event InsurancePoolCreated(uint256 indexed poolId, string name, uint256 premiumRate);
    event CoverageLevelCreated(uint256 indexed poolId, uint256 indexed coverageId, string name, uint256 coverageAmount, uint256 premium);
    event PremiumPaid(address indexed user, uint256 indexed poolId, uint256 indexed coverageId, uint256 amount);
    event ClaimSubmitted(uint256 indexed claimId, address indexed claimant, uint256 amount, string description);
    event ClaimValidated(uint256 indexed claimId, bool validated);
    event ClaimPaid(uint256 indexed claimId, uint256 amount);
    event CoverageActivated(uint256 indexed poolId, uint256 indexed coverageId);
    event CoverageDeactivated(uint256 indexed poolId, uint256 indexed coverageId);

    constructor(address _growTokenAddress, address _farmTokenAddress) {
        require(_growTokenAddress != address(0), "GROW Token address is the zero address");
        require(_farmTokenAddress != address(0), "FARM Token address is the zero address");

        growToken = IERC20(_growTokenAddress);
        farmToken = IERC20(_farmTokenAddress);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CLAIM_VALIDATOR_ROLE, msg.sender);
    }

    // Function to create a new insurance pool
    function createInsurancePool(string memory name, uint256 premiumRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 poolId = ++insurancePoolCount;
        insurancePools[poolId] = InsurancePool({
            name: name,
            balance: 0,
            premiumRate: premiumRate
        });
        emit InsurancePoolCreated(poolId, name, premiumRate);
    }

    // Function to create a new coverage level
    function createCoverageLevel(uint256 poolId, string memory name, uint256 coverageAmount, uint256 premium) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(insurancePools[poolId].balance > 0, "This pool do not exist.");
        uint256 coverageId = ++coverageLevelCount;
        coverageLevels[poolId][coverageId] = CoverageLevel({
            name: name,
            coverageAmount: coverageAmount,
            premium: premium,
            active: true
        });
        emit CoverageLevelCreated(poolId, coverageId, name, coverageAmount, premium);
    }
    // Activate coverage.
    function activateCoverage(uint256 poolId, uint256 coverageId) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(coverageLevels[poolId][coverageId].active == false, "This coverage is active");
         coverageLevels[poolId][coverageId].active = true;
         emit CoverageActivated(poolId, coverageId);
    }

     // Deactivate coverage.
    function deactivateCoverage(uint256 poolId, uint256 coverageId) external onlyRole(DEFAULT_ADMIN_ROLE){
        require(coverageLevels[poolId][coverageId].active == true, "This coverage is not active");
         coverageLevels[poolId][coverageId].active = false;
          emit CoverageDeactivated(poolId, coverageId);
    }
    // Function to pay premium
    function payPremium(uint256 poolId, uint256 coverageId) external whenNotPaused {
        require(coverageLevels[poolId][coverageId].active == true, "This coverage is not active");
         CoverageLevel storage coverage = coverageLevels[poolId][coverageId];
        require(growToken.balanceOf(msg.sender) >= coverage.premium, "Insufficient GROW balance");

        // Transfer premium to the insurance pool
        growToken.transferFrom(msg.sender, address(this), coverage.premium);
        insurancePools[poolId].balance = insurancePools[poolId].balance.add(coverage.premium);
        userCoverage[msg.sender][poolId] = coverageId;

        emit PremiumPaid(msg.sender, poolId, coverageId, coverage.premium);
    }
    
      // Function to submit a claim
    function submitClaim(uint256 poolId,uint256 coverageId,uint256 amount, string memory description) external whenNotPaused{
        require(coverageLevels[poolId][coverageId].active == true, "This coverage is not active");
        require(userCoverage[msg.sender][poolId] == coverageId, "You do not have this coverage.");
        uint256 claimId = ++claimCount;
        claims[claimId] = Claim({
            claimant: msg.sender,
            amount: amount,
            description: description,
            validated: false,
            paid: false,
            poolId: poolId,
            coverageId: coverageId
        });
        emit ClaimSubmitted(claimId, msg.sender, amount, description);
    }

    // Function to validate a claim
    function validateClaim(uint256 claimId, bool validated) external onlyRole(CLAIM_VALIDATOR_ROLE) {
        Claim storage claim = claims[claimId];
        require(!claim.validated, "Claim already validated");
        claim.validated = validated;
        emit ClaimValidated(claimId, validated);
    }
    // Function to pay a claim
    function payClaim(uint256 claimId) external onlyRole(CLAIM_VALIDATOR_ROLE) {
        Claim storage claim = claims[claimId];
        require(claim.validated, "Claim not validated");
        require(!claim.paid, "Claim already paid");

        // Transfer payout to the claimant
        require(insurancePools[claim.poolId].balance >= claim.amount, "Insufficient insurance pool balance");
        insurancePools[claim.poolId].balance = insurancePools[claim.poolId].balance.sub(claim.amount);
        require(growToken.transfer(claim.claimant, claim.amount), "grow token transfer failed.");
        claim.paid = true;

        emit ClaimPaid(claimId, claim.amount);
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
