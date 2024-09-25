// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.25 <0.9.0;

import { Script } from "forge-std/src/Script.sol";
import { console2 } from "forge-std/src/console2.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICreateX } from "./utils/ICreateX.sol";
import { ReceiverHypERC20 } from "./utils/ReceiverHypERC20.sol";
import { OwnableMulticallFactory } from "../src/OwnableMulticallFactory.sol";

import { InterchainAccountRouter } from "@hyperlane-xyz/middleware/InterchainAccountRouter.sol";
import { InterchainAccountMessage } from "@hyperlane-xyz/middleware/libs/InterchainAccountMessage.sol";
import { CallLib } from "@hyperlane-xyz/middleware/libs/Call.sol";
import { TypeCasts } from "@hyperlane-xyz/libs/TypeCasts.sol";
import { Router } from "@hyperlane-xyz/client/Router.sol";
import { IMailbox } from "@hyperlane-xyz/interfaces/IMailbox.sol";
import { StandardHookMetadata } from "@hyperlane-xyz/hooks/libs/StandardHookMetadata.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

interface CallRemoteInterface {
    function callRemote(
        uint32 _destination,
        CallLib.Call[] calldata _calls,
        bytes calldata _hookMetadata
    )
        external
        payable
        returns (bytes32);
}

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
        address multicallFactory = vm.envAddress("MMULTICALL_FACTORY");

        OwnableMulticallFactory multicallFactoryContract = OwnableMulticallFactory(payable(multicallFactory));
        InterchainAccountRouter localRouter = InterchainAccountRouter(0xa95B9cE4B887Aa659e266a5BA9F7E1792bB5080C);
        ICreateX createXContract = ICreateX(createX);
        address deployerAddress = vm.addr(deployerPrivateKey);

        address deployerMulticall = multicallFactoryContract.getMulticallAddress(deployerAddress);

        address icaAddressOp = localRouter.getRemoteInterchainAccount(uint32(11_155_420), deployerMulticall);
        address icaAddressArb = localRouter.getRemoteInterchainAccount(uint32(421_614), deployerMulticall);

        bytes32 routerSalt = encodeSalt(icaAddressOp, "WARPROUTE-3");
        bytes32 guardedSalt = _efficientHash({ a: bytes32(uint256(uint160(icaAddressOp))), b: routerSalt });

        bytes32 localRouterSalt = encodeSalt(deployerMulticall, "WARPROUTE-3");
        bytes32 localGuardedSalt =
            _efficientHash({ a: bytes32(uint256(uint160(deployerMulticall))), b: localRouterSalt });

        address warpRouteOp = createXContract.computeCreate3Address(guardedSalt);
        address warpRouteArb = createXContract.computeCreate3Address(guardedSalt);
        address warpRouteSep = createXContract.computeCreate3Address(localGuardedSalt);

        uint32[] memory domains = new uint32[](3);
        domains[0] = uint32(11_155_420);
        domains[1] = uint32(421_614);
        domains[2] = uint32(84_532);

        bytes32[] memory addresses = new bytes32[](3);
        addresses[0] = TypeCasts.addressToBytes32(warpRouteOp);
        addresses[1] = TypeCasts.addressToBytes32(warpRouteArb);
        addresses[2] = TypeCasts.addressToBytes32(warpRouteSep);

        vm.startBroadcast(deployerPrivateKey);

        bytes memory routerCreationCode = type(TransparentUpgradeableProxy).creationCode;

        // calls for deploying local router and enrolling remote routers --->

        bytes memory localRouterBytecode = abi.encodePacked(
            routerCreationCode,
            abi.encode(
                address(0xF2385f323653E663F0C27d118beE8e2162Ca6372), // implementation
                admin,
                abi.encodeWithSelector(
                    ReceiverHypERC20.initialize.selector,
                    1_000_000_000_000_000_000_000_000_000, // initialSupply
                    "TestWarp", // name
                    "TW", // symbol
                    address(0), // hook
                    address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC), // InterchainAccountISM
                    deployerMulticall, // owner
                    owner // receiver
                )
            )
        );

        bytes memory localCreateXPayload =
            abi.encodeWithSignature("deployCreate3(bytes32,bytes)", localRouterSalt, localRouterBytecode);

        CallLib.Call[] memory localCalls = new CallLib.Call[](4);
        localCalls[0] = CallLib.Call(TypeCasts.addressToBytes32(createX), 0, localCreateXPayload);

        localCalls[1] = CallLib.Call(
            TypeCasts.addressToBytes32(warpRouteSep),
            0,
            abi.encodeWithSelector(Router.enrollRemoteRouters.selector, domains, addresses)
        );

        // <-- calls for deploying local router and enrolling remote routers

        // calls for deploying remote routers and enrolling remotes --->

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
                    icaAddressOp, // owner - ica should have the same address on every chain if remote routers has the
                        // same addresses also
                    owner // receiver
                )
            )
        );

        bytes memory createXPayload =
            abi.encodeWithSignature("deployCreate3(bytes32,bytes)", routerSalt, routerBytecode);

        CallLib.Call[] memory callsOp = new CallLib.Call[](2);
        callsOp[0] = CallLib.Call(TypeCasts.addressToBytes32(createX), 0, createXPayload);

        callsOp[1] = CallLib.Call(
            TypeCasts.addressToBytes32(warpRouteOp),
            0,
            abi.encodeWithSelector(Router.enrollRemoteRouters.selector, domains, addresses)
        );

        bytes memory messageOp = abi.encode(
            TypeCasts.addressToBytes32(deployerAddress),
            TypeCasts.addressToBytes32(address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC)),
            callsOp
        );

        CallLib.Call[] memory callsArb = new CallLib.Call[](2);
        callsArb[0] = CallLib.Call(TypeCasts.addressToBytes32(createX), 0, createXPayload);

        callsArb[1] = CallLib.Call(
            TypeCasts.addressToBytes32(warpRouteArb),
            0,
            abi.encodeWithSelector(Router.enrollRemoteRouters.selector, domains, addresses)
        );

        bytes memory messageArb = abi.encode(
            TypeCasts.addressToBytes32(deployerAddress),
            TypeCasts.addressToBytes32(address(0xb7484d3CA5Cb573a148DA31d408fd0EfBAAC8aAC)),
            callsArb
        );

        uint256 _gasPaymentOp = localRouter.quoteGasPayment(11_155_420, messageOp, 2_456_224);
        uint256 _gasPaymentArb = localRouter.quoteGasPayment(421_614, messageArb, 2_456_224);

        // <--- calls for deploying remote routers and enrolling remotes

        console2.log("icaAddressOp", icaAddressOp);
        console2.log("icaAddressArb", icaAddressArb);
        console2.log("warpRouteOpp", warpRouteOp);
        console2.log("warpRouteArb", warpRouteArb);
        console2.log("warpRouteSep", warpRouteSep);
        console2.log("_gasPaymentOp", _gasPaymentOp);
        console2.log("_gasPaymentArb", _gasPaymentArb);

        // include previous calls in the multicall calls array --->

        localCalls[2] = CallLib.Call(
            TypeCasts.addressToBytes32(address(localRouter)),
            _gasPaymentOp,
            abi.encodeWithSelector(
                CallRemoteInterface.callRemote.selector,
                11_155_420,
                callsOp,
                StandardHookMetadata.overrideGasLimit(2_456_224)
            )
        );

        localCalls[3] = CallLib.Call(
            TypeCasts.addressToBytes32(address(localRouter)),
            _gasPaymentArb,
            abi.encodeWithSelector(
                CallRemoteInterface.callRemote.selector,
                421_614,
                callsArb,
                StandardHookMetadata.overrideGasLimit(2_456_224)
            )
        );

        // <--- include previous calls in the multicall calls array

        // make the magic happen

        (address multicall, bytes[] memory returnData) =
            multicallFactoryContract.deployAndCall{ value: _gasPaymentOp + _gasPaymentArb }(localCalls);

        // <--- make the magic happen

        vm.stopBroadcast();

        console2.log("multicall", multicall);
        console2.log("messageIdOp");
        for (uint256 i = 0; i < returnData.length; i++) {
            console2.logBytes(returnData[i]);
        }
    }
}
