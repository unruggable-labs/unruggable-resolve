// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// equivalent to: https://github.com/ensdomains/ens-contracts/blob/master/contracts/utils/UniversalResolver.sol

import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {CCIPReader} from "@unruggable/CCIPReader.sol/contracts/CCIPReader.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {IReverseUR} from "./IReverseUR.sol";
import {DNSCoder} from "./DNSCoder.sol";

struct Result {
    bool success;
    bytes returnData;
}

contract UniversalResolverOld is CCIPReader {
    IUR public immutable ur;

    constructor(IUR _ur) {
        ur = _ur;
    }

    function registry() external view returns (address) {
        return ur.registry();
    }

    function resolve(bytes calldata name, bytes memory data) external view returns (bytes memory, address) {
        return resolve(name, data, new string[](0));
    }

    function resolve(bytes calldata name, bytes[] memory data) external view returns (Result[] memory, address) {
        return resolve(name, data, new string[](0));
    }

    function resolve(bytes calldata name, bytes memory data, string[] memory gateways)
        public
        view
        returns (bytes memory, address)
    {
        bytes[] memory calls = new bytes[](1);
        calls[0] = data;
        bytes memory v = ccipRead(
            address(ur), abi.encodeCall(IUR.resolve, (name, calls, gateways)), this.resolveCallbackSingle.selector, ""
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolve(bytes calldata name, bytes[] memory data, string[] memory gateways)
        public
        view
        returns (Result[] memory, address)
    {
        bytes memory v = ccipRead(
            address(ur), abi.encodeCall(IUR.resolve, (name, data, gateways)), this.resolveCallbackMany.selector, ""
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolveCallbackSingle(bytes calldata ccip, bytes calldata)
        external
        pure
        returns (bytes memory answer, address resolver)
    {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        answer = _extractRecord(res[0]);
        resolver = lookup.resolver;
    }

    function resolveCallbackMany(bytes calldata ccip, bytes calldata)
        external
        pure
        returns (Result[] memory answers, address resolver)
    {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        answers = new Result[](res.length);
        for (uint256 i; i < res.length; i++) {
            answers[i] = Result({success: (res[i].bits & ResponseBits.ERROR) == 0, returnData: res[i].data});
        }
        resolver = lookup.resolver;
    }

    function findResolver(bytes calldata name)
        external
        view
        returns (address resolver, bytes32 namehash, uint256 finalOffset)
    {
        Lookup memory lookup = ur.lookupName(name);
        resolver = lookup.resolver;
        namehash = lookup.node;
        finalOffset = lookup.offset;
    }

    function reverse(bytes calldata reverseName) external view returns (string memory, address, address, address) {
        return reverse(reverseName, new string[](0));
    }

    function reverse(bytes calldata reverseName, string[] memory gateways)
        public
        view
        returns (string memory, address, address, address)
    {
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(INameResolver.name, (0));
        bytes memory v = ccipRead(
            address(ur),
            abi.encodeCall(IUR.resolve, (reverseName, calls, gateways)),
            this.reverseCallback1.selector,
            abi.encode(gateways)
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function reverseCallback1(bytes calldata ccip, bytes calldata carry)
        external
        view
        returns (string memory, address, address, address)
    {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        string memory primary = abi.decode(_extractRecord(res[0]), (string));
        if (bytes(primary).length == 0) return ("", address(0), lookup.resolver, address(0));
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IAddrResolver.addr, (0));
        bytes memory v = ccipRead(
            address(ur),
            abi.encodeCall(IUR.resolve, (DNSCoder.encode(primary), calls, abi.decode(carry, (string[])))),
            this.reverseCallback2.selector,
            abi.encode(lookup.resolver, primary)
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function reverseCallback2(bytes calldata ccip, bytes calldata carry)
        external
        pure
        returns (string memory primary, address addr, address revResolver, address fwdResolver)
    {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        addr = abi.decode(_extractRecord(res[0]), (address));
        (revResolver, primary) = abi.decode(carry, (address, string));
        fwdResolver = lookup.resolver;
    }

    function _extractRecord(Response memory r) internal pure returns (bytes memory v) {
        v = r.data;
        if ((r.bits & ResponseBits.ERROR) != 0) {
            assembly {
                revert(add(v, 32), mload(v))
            }
        }
    }
}
