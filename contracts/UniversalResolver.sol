// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// equivalent to: https://github.com/ensdomains/ens-contracts/blob/feat/universalresolver-3/contracts/universalResolver/UniversalResolver.sol

import {CCIPReader} from "@unruggable/CCIPReader.sol/contracts/CCIPReader.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {IReverseUR} from "./IReverseUR.sol";
import {IResolveMulticall} from "./IResolveMulticall.sol";
import {IUniversalResolver} from "./IUniversalResolver.sol";
import {DNSCoder} from "./DNSCoder.sol";

contract UniversalResolver is CCIPReader, IUniversalResolver {
    IReverseUR public immutable rr;

    constructor(IReverseUR _rr) {
        rr = _rr;
    }

    function resolve(bytes calldata name, bytes memory data) external view returns (bytes memory, address) {
        return resolveWithGateways(name, data, new string[](0));
    }

    function resolveWithGateways(bytes memory name, bytes memory data, string[] memory gateways)
        public
        view
        returns (bytes memory, address)
    {
        bytes[] memory calls;
        bool multi = bytes4(data) == IResolveMulticall.multicall.selector;
        if (multi) {
            assembly {
                mstore(add(data, 4), sub(mload(data), 4)) // drop selector
                data := add(data, 4)
            }
            calls = abi.decode(data, (bytes[]));
        } else {
            calls = new bytes[](1);
            calls[0] = data;
        }
        bytes memory v = ccipRead(
            address(rr.ur()),
            abi.encodeCall(IUR.resolve, (name, calls, gateways)),
            this.resolveWithGatewaysCallback.selector,
            abi.encode(multi)
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolveWithGatewaysCallback(bytes memory ccip, bytes memory carry)
        external
        view
        returns (bytes memory answer, address resolver)
    {
        (Lookup memory lookup, Response[] memory res) = abi.decode(ccip, (Lookup, Response[]));
        resolver = _extractResolver(lookup);
        bool multi = abi.decode(carry, (bool));
        if (multi) {
            bytes[] memory m = new bytes[](res.length);
            for (uint256 i; i < res.length; i++) {
                m[i] = res[i].data;
            }
            answer = abi.encode(m);
        } else {
            answer = res[0].data;
            if ((res[0].bits & ResponseBits.ERROR) != 0) {
                revert ResolverError(answer);
            }
        }
    }

    function reverse(bytes calldata lookupAddress, uint256 coinType)
        external
        view
        returns (string memory, address, address)
    {
        return reverseWithGateways(lookupAddress, coinType, new string[](0));
    }

    function reverseWithGateways(bytes calldata lookupAddress, uint256 coinType, string[] memory gateways)
        public
        view
        returns (string memory, address, address)
    {
        bytes memory v = ccipRead(
            address(rr),
            abi.encodeCall(IReverseUR.reverse, (lookupAddress, coinType, gateways)),
            this.reverseWithGatewaysCallback.selector,
            lookupAddress
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function reverseWithGatewaysCallback(bytes memory ccip, bytes memory addr0)
        external
        view
        returns (string memory name, address resolver, address reverseResolver)
    {
        (Lookup memory rev, Lookup memory fwd, bytes memory addr) = abi.decode(ccip, (Lookup, Lookup, bytes));
        if (keccak256(addr0) != keccak256(addr)) {
            revert ReverseAddressMismatch(addr);
        }
        name = DNSCoder.decode(fwd.dns); // wont fail
        resolver = fwd.resolver;
        reverseResolver = _extractResolver(rev);
    }

    function _extractResolver(Lookup memory lookup) internal view returns (address resolver) {
        resolver = lookup.resolver;
        if (resolver == address(0)) {
            revert ResolverNotFound(lookup.dns);
        }
        if (resolver.code.length == 0) {
            revert ResolverNotContract(lookup.dns);
        }
    }

    // ENSIP10ResolverFinder
    function findResolver(bytes calldata name)
        external
        view
        returns (address resolver, bytes32 namehash, uint256 finalOffset)
    {
        Lookup memory lookup = rr.ur().lookupName(name);
        resolver = lookup.resolver;
        namehash = lookup.node;
        finalOffset = lookup.offset;
    }
}
