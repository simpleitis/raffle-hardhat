// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// VRFConsumerBaseV2 comes with a 'fulfillRandomWords' virutal function. The virtual keyword indicates that it expects to be overriden. The 'fullfillRandomWords' function is defined inside 'VRFConsumerBaseV2.sol' because this helps the 'VRFCoordinator' to know that it can call the 'fulfillRandomWords' function
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";

error Raffle_NotEnoughEthEntered();
error Raffle_TransferFailed();
error Raffle_NotOpen();
error Raffle_UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

/** @title A sample raffle contract
 * @author Amar Krishna
 * @notice This contract is for creating an untamperable decentralized smart contract
 * @dev This implements chainlink VRF_V2 and chainlink keeepers
 */

// we have to make raffle contract vrf and keepers consumeable
contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {
    // when using enum we are secretly creating a data structure like a uint256 array with 'OPEN' resulting in  0 and 'CALCULATING' resulting in 1
    /* Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }

    /* State Variables */
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    uint256 private immutable i_entraceFee;
    // when one of the players win, we would have to pay them and that is why we are makking the array entries payable
    address payable[] private s_players;
    bytes32 private immutable i_gasLane; // sets the max gas we are willing to spend
    uint32 private immutable i_callbackGasLimit; // sets the max gas we are willing to send when calling the 'fullFillRandomWords()' function
    uint16 private constant REQUEST_CONFIRMATIONS = 3; // no.of block confirmation we are expecting
    uint32 private constant NUM_WORDS = 1; // no.of random numbers we want the function to return

    // Raffle variables
    address private s_recentWinner;
    RaffleState private s_raffleState;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;

    /*Events*/
    // indexed events are easy to search and are expensive compared to normal declaration which are unindexed
    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed winner);

    /* Functions */
    // we are adding the 'VRFConsumerBaseV2' constructor and passing it the vrfCoordinatorV2's address from the raffle constructor to its constructor
    constructor(
        address vrfCoordinatorV2,
        uint256 entranceFee,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        uint256 interval
    ) VRFConsumerBaseV2(vrfCoordinatorV2) {
        i_entraceFee = entranceFee;
        // here we are fetching the vrfCoordinator by using the interface and the contract's address
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
        // block.timestamp return the timestamp from the blockchain
        s_lastTimeStamp = block.timestamp;
        i_interval = interval;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entraceFee) {
            revert Raffle_NotEnoughEthEntered();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        // msg.sender is not a payable address by default so we need to typecast it before pushing it into s_players array, which is an array of payable addresses
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    // both 'checkUpKeep' and 'performUpkeep' are run off chain on a node run by chainlink and it does not use gas which is on the main chain
    // 'checkUpKeep' and 'performUpkeep' are virutal functions implemented in 'KeeperCompatibleInterface.sol'

    /**
     * @dev This is the function that the chainlink keeper nodes *call when they look for the 'upkeepNeeded' to return true
     * The following should be true in order to return true:
     * 1. Our time interval should have passed
     * 2. The lottery should have at least 1 player, and have some ETH
     * 3. Our subscription is funded with LINK
     * 4. The lottery should be in an 'open' state
     * */
    // 'checkData' is pased from 'checkUpKepp' to 'performUpKeep' automatically
    function checkUpkeep(
        bytes memory /*checkData*/
    )
        public
        override
        returns (
            bool upkeepNeeded,
            bytes memory /*performData*/
        )
    {
        bool isOpen = (RaffleState.OPEN == s_raffleState);
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);
        bool hasPlayers = (s_players.length > 0);
        bool hasBalance = address(this).balance > 0;
        // since we initialised 'upkeepNeeded' in the return section we dont need to initialise it here as this is an overriden function
        upkeepNeeded = (isOpen && timePassed && hasPlayers && hasBalance);
    }

    // external functions are little bit cheaper than public functions becuase solidity knows the our own contract cannot call the function
    function performUpkeep(
        bytes calldata /*checkData*/
    ) external override {
        // we are passing a blank 'callData' to 'checkUpKeep'
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gasLane - helps to set a limit on max gas
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit, //callbackGasLimit set the max gas fulfillRandomWords function can use
            NUM_WORDS //numWords is used to set the number of random numbers we want to generate
        );

        // this is redundant as the 'requestRandomWords' defined in the 'vrfcoordinator'  return the 'requestId' by default
        emit RequestedRaffleWinner(requestId);
    }

    // 'fullfillRandomWords' mean the same as fulfillRandomNumbers
    // we are commenting out 'requestId' becuse we do not need the variable inside the function but we need it as a placeholder as the function expects the requestId
    function fulfillRandomWords(
        uint256,
        /*requestId*/
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        s_recentWinner = s_players[indexOfWinner];
        s_raffleState = RaffleState.OPEN;
        s_players = new address payable[](0);
        s_lastTimeStamp = block.timestamp;
        // ("") is used to trigger the fallback function of the receiving argument
        (bool success, ) = s_recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle_TransferFailed();
        }
        emit WinnerPicked(s_recentWinner);
    }

    /* VIEW/PURE functions */
    function getEntranceFee() public view returns (uint256) {
        return i_entraceFee;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    // as 'NUM_WORDS' is a constant we are not actually reading from storage, so we can mark the function as 'pure'
    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }

    function getLatestTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRequestConfirmations() public pure returns (uint16) {
        return REQUEST_CONFIRMATIONS;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }
}
