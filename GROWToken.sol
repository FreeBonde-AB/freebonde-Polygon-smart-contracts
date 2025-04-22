solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GROWToken is ERC20, AccessControl, ERC20Pausable, ERC20Burnable {
    using SafeMath for uint256;
    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    // Vesting information
    struct VestingSchedule {
        uint256 startTime;
        uint256 cliffDuration;
        uint256 totalDuration;
        uint256 amount;
        uint256 released;
        uint256 monthlyReleaseAmount;
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    EnumerableSet.AddressSet private _vestingAddresses;

    // Emission control
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10**18; // 1 billion with 18 decimals
    uint256 public currentEmissionRate;
    uint256 public emissionReductionRate;
    uint256 public lastEmissionUpdateTime;
    uint256 public constant EMISSION_UPDATE_INTERVAL = 1 days;

    // Burn control
    uint256 public constant MARKETPLACE_BURN_RATE_PRECISION = 1000; // 0.1%
    uint256 public marketplaceBurnRate = 5; // 0.5%

    event Minted(address to, uint256 amount);
    event Burned(address from, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 startTime, uint256 cliff, uint256 duration, uint256 amount);
    event VestingScheduleReleased(address indexed beneficiary, uint256 amount);
    event EmissionRateUpdated(uint256 newRate);
    event MarketplaceBurn(uint256 amount);
    event DailyRewardReceived(address indexed user, uint256 amount);

    constructor() ERC20("GROWToken", "GROW") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);

        // Set initial emission rate and burn rate
        currentEmissionRate = 1500000000 * 10**18 ; // First year 1.5B
        emissionReductionRate = 10; // 10% per year

        lastEmissionUpdateTime = block.timestamp;
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    // Modifier for checking if the address has a vesting schedule
    modifier onlyVestingAddress(address _address) {
        require(_vestingAddresses.contains(_address), "Address does not have a vesting schedule");
        _;
    }

    // Minting function
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    // Burning function
    function burn(uint256 amount) public override onlyRole(BURNER_ROLE) {
        _burn(_msgSender(), amount);
        emit Burned(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) external onlyRole(BURNER_ROLE) {
        _spend(account, _msgSender(), amount);
        _burn(account, amount);
        emit Burned(account, amount);
    }

    // Function to pause the contract
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    // Function to unpause the contract
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // Vesting functions
    function createVestingSchedule(
        address beneficiary,
        uint256 startTime,
        uint256 cliffDuration,
        uint256 totalDuration,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(beneficiary != address(0), "Beneficiary is the zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(totalDuration > cliffDuration, "Total duration must be greater than cliff duration");
        uint256 monthlyAmount = amount.div(totalDuration.div(30 days)); //release each month

         vestingSchedules[beneficiary] = VestingSchedule(
            startTime,
            cliffDuration,
            totalDuration,
            amount,
            0,
            monthlyAmount
        );
        _vestingAddresses.add(beneficiary);
        emit VestingScheduleCreated(beneficiary, startTime, cliffDuration, totalDuration, amount);
    }

      function release(address beneficiary) external onlyVestingAddress(beneficiary) {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
         require(block.timestamp >= schedule.startTime.add(schedule.cliffDuration), "Cliff period not ended");
         uint256 timeElapsed = block.timestamp.sub(schedule.startTime);
         uint256 monthlyTimes = timeElapsed.div(30 days);
        uint256 releasedAmount = schedule.monthlyReleaseAmount.mul(monthlyTimes);
        uint256 releasable = releasedAmount.sub(schedule.released);
        require(releasable > 0, "No tokens are due to be released");
        schedule.released = schedule.released.add(releasable);
        _mint(beneficiary, releasable);
        emit VestingScheduleReleased(beneficiary, releasable);
    }

    function batchRelease(address[] calldata beneficiaries) external {
          for (uint256 i = 0; i < beneficiaries.length; i++) {
            release(beneficiaries[i]);
        }
    }

    // Update emission rate
    function updateEmissionRate() public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(block.timestamp >= lastEmissionUpdateTime.add(EMISSION_UPDATE_INTERVAL), "Update interval not reached");
        currentEmissionRate = currentEmissionRate.sub(currentEmissionRate.mul(emissionReductionRate).div(100));
        lastEmissionUpdateTime = block.timestamp;
        emit EmissionRateUpdated(currentEmissionRate);
    }

     //Burn when transfer from marketplace
    function burnFromMarketplace(uint256 amount) external {
        uint256 burnAmount = amount.mul(marketplaceBurnRate).div(MARKETPLACE_BURN_RATE_PRECISION);
         _burn(address(this), burnAmount);
         emit MarketplaceBurn(burnAmount);
    }
    
     function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    //daily reward
    function dailyCheckIn(address user) external {
        uint256 reward = _calculateDailyReward(user); // Implement this function based on your logic
        _mint(user, reward);
        emit DailyRewardReceived(user, reward);
    }

    function _calculateDailyReward(address user) internal view returns (uint256) {
        // Implement your daily reward calculation logic here
        // This is just a placeholder implementation
        uint256 baseReward = 10 * 10**18;
        return baseReward;
    }
}
