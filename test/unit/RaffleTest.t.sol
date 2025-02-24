// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Vm} from "forge-std/Vm.sol";
import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {LinkToken} from "../mock/LinkToken.sol";
import {VRFCoordinatorV2_5Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract RaffleTest is Test {
    Raffle public raffle;
    HelperConfig public helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint32 callbackGasLimit;
    uint256 subscriptionId;
    LinkToken linkToken;
    address public PLAYER = makeAddr("player");
    uint public constant STARTING_BALANCE = 10 ether;
    event EnteredRaffle(address indexed player);

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        console.log("Raffle address:", address(raffle));
        console.log("VRF Coordinator:", config.vrfCoordinator);
        console.log("Subscription ID:", config.subscriptionId);
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        gasLane = config.gasLane;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;
        linkToken = LinkToken(config.link);
        vm.deal(PLAYER, STARTING_BALANCE);
    }

    function testY() public pure {
        assert(1 == 1);
    }

    function testRaffleIinitializesWithOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /*//////////////////////////////////////////////////////////////
                              EVENT TEST 
    //////////////////////////////////////////////////////////////*/
    function testEmitsEventOnEntrance() public {
        //Arrange
        vm.prank(PLAYER);
        //Act / Assert
        vm.expectEmit(true, false, false, false, address(raffle));

        emit EnteredRaffle(PLAYER);

        raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                               TEST ENTRY
    //////////////////////////////////////////////////////////////*/

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act/Assert

        vm.expectRevert(Raffle.Raffle_NotEnoughEth.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayersWhenTheyEnter() public {
        //Arrange
        vm.prank(PLAYER);
        //Act
        raffle.enterRaffle{value: entranceFee}();
        //Assert
        address playerRecorded = raffle.getPlayers(0);
        assert(playerRecorded == PLAYER);
    }

    function testCheckUpKeepReturnsFalseIfItsHasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        //Act
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(!upKeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsNotOpen()
        public
        raffleEnteredAndTimePassed
    {
        //Arrange
        raffle.performUpkeep("");
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        //Act
        (bool upKeepNeeded, ) = raffle.checkUpKeep("");
        //Assert
        assert(raffleState == Raffle.RaffleState.CLOSED);
        assert(upKeepNeeded == false);
    }

    function testDontAllowPlayersEnterWhileCalculating()
        public
        raffleEnteredAndTimePassed
    {
        //Arrange
        raffle.performUpkeep("");

        //Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    /*//////////////////////////////////////////////////////////////
                             PERFORMUPKEEP
    //////////////////////////////////////////////////////////////*/

    function testPerformUpKeepRevertsIfCheckUpKeepIsFalse() public {
        //Arrange
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState rState = raffle.getRaffleState();

        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayers = 1;

        //Act / Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpKeepUpdatesRaffleStateAndEventsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        //Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory enteries = vm.getRecordedLogs();
        bytes32 requestId = enteries[1].topics[1];

        //Arrange
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(uint(raffleState) == 1); // 1 = CALCULATING, 0 = OPEN
    }

    /*//////////////////////////////////////////////////////////////
                               FUZZ TEST
    //////////////////////////////////////////////////////////////*/
    function testFulfillRandomwordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 requestId
    ) public raffleEnteredAndTimePassed {
        //Act / Assert
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            requestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicskAWinnerAndSendsMoney()
        public
        raffleEnteredAndTimePassed
    {
        // Arrange

        address expectedWinner = address(1);
        uint256 additionalEntrants = 3;
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));

            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 winnerStartingBalance = expectedWinner.balance;
        uint256 startingTimeStamp = raffle.getLastTimeStamp();

        //Act
        vm.recordLogs();
        raffle.performUpkeep(""); // emits the requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        //Assert
        address recentWinner = raffle.getRecentWinner();
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();
        uint256 prize = entranceFee * (additionalEntrants + 1);

        assert(expectedWinner == recentWinner);
        assert(uint256(raffleState) == 0);
        assert(winnerBalance == winnerStartingBalance + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
