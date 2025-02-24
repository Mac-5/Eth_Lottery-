// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, FundSubscription, AddConsumer} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() public {
        deployContract();
    }

    function deployContract() public returns (Raffle, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory Config = helperConfig.getConfig();
        if (Config.subscriptionId == 0) {
            //create Subscription
            CreateSubscription createSubscription = new CreateSubscription();
            (Config.subscriptionId, Config.vrfCoordinator) = createSubscription
                .createSubscription(Config.vrfCoordinator);
            // fund Subscription
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                Config.vrfCoordinator,
                Config.subscriptionId,
                Config.link
            );
        }
        vm.startBroadcast();
        Raffle raffle = new Raffle(
            Config.entranceFee,
            Config.interval,
            Config.vrfCoordinator,
            Config.gasLane,
            Config.subscriptionId,
            Config.callbackGasLimit
        );
        vm.stopBroadcast();

        AddConsumer addConsumer = new AddConsumer();
        addConsumer.addConsumer(
            address(raffle),
            Config.vrfCoordinator,
            Config.subscriptionId
        );

        return (raffle, helperConfig);
    }
}
