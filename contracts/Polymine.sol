// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Polymine is ERC20, Ownable {
    uint256 public constant TOTAL_SUPPLY = 21_000_000 * 10 ** 18; // Total supply in decimals
    uint256 public constant INITIAL_BLOCK_REWARD = 10 * 10 ** 18; // Initial block reward in decimals
    uint256 public constant HALVING_INTERVAL = 3 * 365 days; // Halving every 3 years
    uint256 public constant INITIAL_DIFFICULTY = 1000; // Initial difficulty

    uint256 public difficulty = INITIAL_DIFFICULTY; // Difficulty starts at 1000
    uint256 public lastBlockTime;
    uint256 public emissionEndTime;
    uint256 public rewardPool; // Reward pool for staking rewards
    uint256 public totalStaked;

    struct Stake {
        uint256 amount; // Amount of tokens staked
        uint256 stakeTime; // Timestamp of when the stake was made
    }

    mapping(address => Stake) public stakes;

    event Mined(address indexed miner, uint256 reward);
    event Staked(address indexed staker, uint256 amount);
    event Unstaked(address indexed staker, uint256 amount, uint256 rewards);
    event MaticTransferred(address indexed owner, uint256 amount);

    constructor(address ownerAddress) ERC20("Polymine", "POLM") Ownable(ownerAddress) {
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
        uint256 minerShare = (reward * 80) / 100; // 80% to the miner
        uint256 stakerShare = (reward * 20) / 100; // 20% to the stakers

        _mint(msg.sender, minerShare);
        rewardPool += stakerShare; // Add staker share to reward pool

        emit Mined(msg.sender, minerShare);

        // Transfer 90% of the received MATIC to the owner
        uint256 ownerShare = (msg.value * 90) / 100;
        payable(owner()).transfer(ownerShare);

        emit MaticTransferred(owner(), ownerShare);

        adjustDifficulty();
    }

    // Adjust difficulty based on block time
    function adjustDifficulty() internal {
        uint256 targetTime = 180; // Target block time in seconds
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

        // Calculate rewards proportionally
        uint256 userShare = (userStake.amount * 1e18) / totalStaked; // User's share as a percentage
        uint256 rewards = (rewardPool * userShare) / 1e18; // Rewards for the user

        require(rewardPool >= rewards, "Not enough rewards in pool");

        rewardPool -= rewards; // Deduct rewards from the pool
        totalStaked -= userStake.amount;

        _mint(msg.sender, rewards); // Mint rewards to the user
        transfer(msg.sender, userStake.amount); // Return staked amount to the user

        delete stakes[msg.sender];

        emit Unstaked(msg.sender, userStake.amount, rewards);
    }
}