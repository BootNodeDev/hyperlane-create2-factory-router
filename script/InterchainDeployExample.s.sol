// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { InterchainCreate2FactoryRouter } from "src/InterchainCreate2FactoryRouter.sol";
import { InterchainCreate2FactoryMessage } from "src/libs/InterchainCreate2FactoryMessage.sol";
import { TestDeployContract} from "./utils/TestDeployContract.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract InterchainDeployExample is Script {
    function run() public {
        uint256 ownerPrivateKey = vm.envUint("ROUTER_OWNER_PK");
        address localRouter = vm.envAddress("ROUTER");

        bytes memory bytecode = type(TestDeployContract).creationCode;
        bytes32 salt = "testDeployContract.0.0.2";
        bytes32 ism = TypeCasts.addressToBytes32(address(0));
        uint32 destination = uint32(11155111);

        bytes memory messageBody = InterchainCreate2FactoryMessage.encode(
            vm.addr(ownerPrivateKey),
            ism,
            salt,
            bytecode,
            new bytes(0)
        );

        vm.startBroadcast(ownerPrivateKey);

        uint256 gasPayment = InterchainCreate2FactoryRouter(localRouter).quoteGasPayment(
            destination,
            messageBody,
            new bytes(0)
        );

        bytes32 messageId = InterchainCreate2FactoryRouter(localRouter).deployContractAndInit{value: gasPayment}(
            destination,
            ism,
            salt,
            bytecode,
            abi.encodeWithSelector(TestDeployContract.increment.selector)
        );

        vm.stopBroadcast();

        console2.log('Gas Payment:', gasPayment);
        console2.log('messageId:');
        console2.logBytes32(messageId);
    }
}
