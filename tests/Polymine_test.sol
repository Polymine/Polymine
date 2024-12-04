// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Polyminetest is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 21_000_000; // Total supply in whole numbers (21 million)
    uint256 public constant INITIAL_BLOCK_REWARD = 100; // Initial block reward in whole numbers
    uint256 public constant HALVING_INTERVAL = 3 * 365 days; // Halving every 3 years
    uint256 public constant INITIAL_DIFFICULTY = 1000; // Initial difficulty in whole numbers

    uint256 public difficulty = INITIAL_DIFFICULTY; // Difficulty starts at 1000
    uint256 public lastBlockTime;
    uint256 public emissionEndTime;
    uint256 public rewardPool; // Reward pool for staking in whole numbers

    struct Stake {
        uint256 amount; // Amount of tokens staked
        uint256 stakeTime; // Timestamp of when the stake was made
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;

    event Mined(address indexed miner, uint256 reward);
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount, uint256 rewards);

    constructor(address ownerAddress) ERC20("Polyminetest", "POLMT") Ownable(ownerAddress) {
        // Mint 5% of the total supply to the owner (treasury)
        uint256 initialSupply = (TOTAL_SUPPLY * 5) / 100; // 5% of total supply
        _mint(ownerAddress, initialSupply);

        lastBlockTime = block.timestamp;
        emissionEndTime = block.timestamp + HALVING_INTERVAL;
    }

    // Mining function
    function mine(uint256 nonce) external payable {
        require(block.timestamp < emissionEndTime, "Mining ended");

        bytes32 hash = keccak256(abi.encodePacked(msg.sender, nonce));
        require(uint256(hash) < type(uint256).max / difficulty, "Invalid nonce");

        uint256 reward = getBlockReward();
        _mint(msg.sender, reward);

        // Deduct 5% of transaction gas fees for the treasury (owner)
        uint256 treasuryShare = (msg.value * 5) / 100;
        payable(owner()).transfer(treasuryShare);

        emit Mined(msg.sender, reward);

        adjustDifficulty();
    }

    // Adjust difficulty based on block time
    function adjustDifficulty() internal {
        uint256 targetTime = 15; // Target block time in seconds
        uint256 timeTaken = block.timestamp - lastBlockTime;

        if (timeTaken < targetTime) {
            difficulty = (difficulty * 105) / 100; // Increase difficulty by 5%
        } else {
            difficulty = (difficulty * 95) / 100; // Decrease difficulty by 5%
        }

        lastBlockTime = block.timestamp;
    }

    // Calculate block reward based on emission curve
    function getBlockReward() public view returns (uint256) {
        uint256 elapsed = block.timestamp - lastBlockTime;
        uint256 halvingPeriods = elapsed / HALVING_INTERVAL;
        return INITIAL_BLOCK_REWARD >> halvingPeriods; // Reward reduces by half every halving period
    }

    // Staking functionality
    function stake(uint256 _amount) external {
        require(balanceOf(msg.sender) >= _amount, "Insufficient POLM balance");

        transfer(address(this), _amount);

        stakes[msg.sender].amount += _amount;
        stakes[msg.sender].stakeTime = block.timestamp;
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    function unstake() external {
        Stake memory userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No tokens staked");

        uint256 stakingDuration = block.timestamp - userStake.stakeTime;
        uint256 rewards = (userStake.amount * stakingDuration) / 365 days;

        require(rewardPool >= rewards, "Not enough rewards in pool");

        rewardPool -= rewards;
        totalStaked -= userStake.amount;

        _mint(msg.sender, rewards);
        transfer(msg.sender, userStake.amount);

        delete stakes[msg.sender];

        emit Unstaked(msg.sender, userStake.amount, rewards);
    }

    function addRewards(uint256 _amount) external onlyOwner {
        _mint(address(this), _amount);
        rewardPool += _amount;
    }
}
