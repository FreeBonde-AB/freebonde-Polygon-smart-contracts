solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FARMToken is ERC20, AccessControl, ERC20Pausable {
    using SafeMath for uint256;
    // Roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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
    uint256 public constant INITIAL_SUPPLY = 100_000_000 * 10**18; // 100 million with 18 decimals

    event Minted(address to, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 startTime, uint256 cliff, uint256 duration, uint256 amount);
    event VestingScheduleReleased(address indexed beneficiary, uint256 amount);

    constructor() ERC20("FARMToken", "FARM") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);

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
}