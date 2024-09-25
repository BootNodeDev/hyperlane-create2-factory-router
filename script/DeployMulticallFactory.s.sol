// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICreateX } from "./utils/ICreateX.sol";
import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";

import { OwnableMulticallFactory } from "../src/OwnableMulticallFactory.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployMulticallFactory is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PK");
        address createX = vm.envAddress("CREATEX_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // TODO - CreteX uses some special salts, improve this
        bytes32 factorySalt = keccak256(abi.encodePacked("MulticallFactory-0.0.1", vm.addr(deployerPrivateKey)));
        bytes memory factoryCreationCode = type(OwnableMulticallFactory).creationCode;

        address factory = ICreateX(createX).deployCreate3(factorySalt, factoryCreationCode);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console2.log("Multical Factory:", factory);
    }
}
