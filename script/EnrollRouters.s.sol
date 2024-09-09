// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { InterchainCreate2FactoryRouter } from "src/InterchainCreate2FactoryRouter.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract EnrollRouters is Script {
    function run() public {
        uint256 ownerPrivateKey = vm.envUint("ROUTER_OWNER_PK");

        address[] memory routers = vm.envAddress("ROUTERS", ",");
        uint256[] memory domains = vm.envUint("DOMAINS", ",");

        address localRouter = vm.envAddress("ROUTER");

        if (routers.length != domains.length) {
            revert("Invalid input");
        }

        vm.startBroadcast(ownerPrivateKey);

        for (uint256 i = 0; i < routers.length; i++) {
            InterchainCreate2FactoryRouter(localRouter).enrollRemoteRouter(
                uint32(domains[i]), TypeCasts.addressToBytes32(routers[i])
            );
        }

        vm.stopBroadcast();
    }
}
