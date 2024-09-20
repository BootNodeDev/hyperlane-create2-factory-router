// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICreateX } from "./utils/ICreateX.sol";
import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";

import { InterchainAccountRouter } from "@hyperlane-xyz/middleware/InterchainAccountRouter.sol";
import {InterchainAccountMessage} from "@hyperlane-xyz/middleware/libs/InterchainAccountMessage.sol";
import { CallLib } from "@hyperlane-xyz/middleware/libs/Call.sol";
import {TypeCasts} from "@hyperlane-xyz/libs/TypeCasts.sol";
import {Router} from "@hyperlane-xyz/client/Router.sol";
import {IMailbox} from "@hyperlane-xyz/interfaces/IMailbox.sol";
import {StandardHookMetadata} from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";


/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract DeployWarp is Script {

    function encodeSalt(address addr, string memory str) public pure returns (bytes32) {
        require(bytes(str).length <= 11, "String must be 11 bytes or less");

        bytes32 encoded;

        // Step 1: Add the address (20 bytes)
        encoded = bytes32(uint256(uint160(addr)) << 96);

        // Step 2: Add the 0 byte in the 21st position (already 0 in Solidity, so no need to set it)

        // Step 3: Add the string (11 bytes max)
        bytes memory strBytes = bytes(str);
        for (uint256 i = 0; i < strBytes.length; i++) {
            encoded |= bytes32(uint256(uint8(strBytes[i])) << (8 * (10 - i))); // Shift into the correct byte positions
        }

        return encoded;
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("ROUTER_OWNER_PK");
        address createX = vm.envAddress("CREATEX_ADDRESS");
        address admin = vm.envAddress("PROXY_ADMIN");
        address owner = vm.envAddress("ROUTER_OWNER");
        address mailbox = vm.envAddress("MAILBOX");

        InterchainAccountRouter localRouter = InterchainAccountRouter(0xa95B9cE4B887Aa659e266a5BA9F7E1792bB5080C);
        ICreateX createXContract = ICreateX(createX);
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("deployerAddress", deployerAddress);

        address icaAddressOp = localRouter.getRemoteInterchainAccount(uint32(11155420), deployerAddress);
        address icaAddressArb = localRouter.getRemoteInterchainAccount(uint32(421614), deployerAddress);
        // address icaAddressSep = localRouter.getRemoteInterchainAccount(uint32(11155111), deployerAddress);

        bytes32 routerSalt = encodeSalt(icaAddressOp, "WARPROUTE-3");
        bytes32 guardedSalt = _efficientHash({a: bytes32(uint256(uint160(icaAddressOp))), b: routerSalt});

        console2.log("routerSalt");
        console2.logBytes32(routerSalt);
        console2.log("guardedSalt");
        console2.logBytes32(guardedSalt);

        address warpRouteOp = createXContract.computeCreate3Address(guardedSalt);
        address warpRouteArb = createXContract.computeCreate3Address(guardedSalt);
        // address warpRouteSep = createXContract.computeCreate3Address(guardedSalt, deployerAddress);

        console2.logBytes(
            abi.encodeWithSelector(
                    ReceiverHypERC20.initialize.selector,
                    0, // initialSupply
                    "TestWarp", // name
                    "TW", // symbol
                    address(0), // hook
                    address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC), // InterchainAccountISM
                    icaAddressOp, // owner - ica should have the same address on every chain if remote routers has the same addresses also
                    owner// receiver
                )
        );


        vm.startBroadcast(deployerPrivateKey);

        address warpRouteSep = address(new TransparentUpgradeableProxy(
            address(0xF2385f323653E663F0C27d118beE8e2162Ca6372),
            admin,
            abi.encodeWithSelector(
                ReceiverHypERC20.initialize.selector,
                1000000000000000000000000000, // initialSupply
                "TestWarp", // name
                "TW", // symbol
                address(0), // hook
                address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC), // InterchainAccountISM
                owner, // owner
                owner // receiver
            )
        ));

        uint32[] memory domains = new uint32[](3);
        domains[0] = uint32(11155420);
        domains[1] = uint32(421614);
        domains[2] = uint32(11155111);

        bytes32[] memory addresses = new bytes32[](3);
        addresses[0] = TypeCasts.addressToBytes32(warpRouteOp);
        addresses[1] = TypeCasts.addressToBytes32(warpRouteArb);
        addresses[2] = TypeCasts.addressToBytes32(warpRouteSep);

        console2.log("owner", Router(warpRouteSep).owner());

        Router(warpRouteSep).enrollRemoteRouters(domains, addresses);

        bytes memory routerCreationCode = type(TransparentUpgradeableProxy).creationCode;

        bytes memory routerBytecode = abi.encodePacked(
            routerCreationCode,
            abi.encode(
                address(0xF2385f323653E663F0C27d118beE8e2162Ca6372),
                admin,
                abi.encodeWithSelector(
                    ReceiverHypERC20.initialize.selector,
                    0, // initialSupply
                    "TestWarp", // name
                    "TW", // symbol
                    address(0), // hook
                    address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC), // InterchainAccountISM
                    icaAddressOp, // owner - ica should have the same address on every chain if remote routers has the same addresses also
                    owner// receiver
                )
            )
        );

        bytes memory createXPayload = abi.encodeWithSignature("deployCreate3(bytes32,bytes)", routerSalt, routerBytecode);

        CallLib.Call[] memory calls = new CallLib.Call[](2);
        calls[0] = CallLib.Call(
            TypeCasts.addressToBytes32(createX),
            0,
            createXPayload
        );

        // we can use warpRouteOp because it is supposed to be the same as warpRouteArb
        calls[1] = CallLib.Call(
            TypeCasts.addressToBytes32(warpRouteOp),
            0,
            abi.encodeWithSelector(
                Router.enrollRemoteRouters.selector,
                domains,
                addresses
            )
        );

        bytes memory message = abi.encode(
            TypeCasts.addressToBytes32(deployerAddress),
            TypeCasts.addressToBytes32(address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC)),
            calls
        );

        uint256 _gasPaymentOp = localRouter.quoteGasPayment(11155420, message, 2456224);
        uint256 _gasPaymentArb = localRouter.quoteGasPayment(421614, message, 2456224);

        console2.log("icaAddressOp", icaAddressOp);
        console2.log("icaAddressArb", icaAddressArb);
        console2.log("warpRouteOpp", warpRouteOp);
        console2.log("warpRouteArb", warpRouteArb);
        console2.log("warpRouteSep", warpRouteSep);
        console2.log("_gasPaymentOp", _gasPaymentOp);
        console2.log("_gasPaymentArb", _gasPaymentArb);

        bytes32 messageIdOp = localRouter.callRemote{ value: _gasPaymentOp }(
            11155420, calls, StandardHookMetadata.overrideGasLimit(2456224)
        );

        bytes32 messageIdArb = localRouter.callRemote{ value: _gasPaymentArb }(
            421614, calls, StandardHookMetadata.overrideGasLimit(2456224)
        );

        vm.stopBroadcast();

        console2.log("messageIdOp");
        console2.logBytes32(messageIdOp);
        console2.log("_gasPaymentArb");
        console2.logBytes32(messageIdArb);
    }
}
