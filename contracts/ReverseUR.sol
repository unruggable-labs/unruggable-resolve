// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {URCaller} from "./URCaller.sol";
import {ReverseName} from "./ReverseName.sol";
import {ENSDNSCoder} from "./ENSDNSCoder.sol";
import {SafeDecoder} from "./SafeDecoder.sol";
import {EVM_BIT, COIN_TYPE_ETH} from "./Constants.sol";

contract ReverseUR is URCaller {
    constructor(address ur) URCaller(ur) {}

    function reverse(bytes memory addr, uint256 coinType, string[] memory batchedGateways)
        external
        view
        returns (Lookup memory, /*rev*/ Lookup memory, /*fwd*/ bytes memory /*answer*/ )
    {
        bytes memory v = _lookupPrimary(addr, coinType, coinType, batchedGateways);
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function reverseName(bytes memory addr, uint256 coinType) public pure returns (string memory) {
        return ReverseName.from(addr, coinType);
    }

    function _lookupPrimary(bytes memory addr, uint256 coinType, uint256 coinType0, string[] memory batchedGateways)
        internal
        view
        returns (bytes memory)
    {
        string memory name = ReverseName.from(addr, coinType);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(INameResolver.name, (0));
        return callResolve(
            ENSDNSCoder.dnsEncode(name),
            calls,
            batchedGateways,
            this.reverseCallback1.selector,
            abi.encode(Reverse1(addr, coinType, coinType0, batchedGateways))
        );
    }

    struct Reverse1 {
        bytes addr;
        uint256 coinType;
        uint256 coinType0;
        string[] batchedGateways;
    }

    function reverseCallback1(Lookup memory lookup, Response[] memory res, bytes memory carry)
        external
        view
        returns (Lookup memory, Lookup memory nul, bytes memory v)
    {
        Reverse1 memory state = abi.decode(carry, (Reverse1));
        bytes memory primary;
        if (lookup.ok && (res[0].bits & ResponseBits.ERROR) == 0) {
            primary = SafeDecoder.decodeBytes(res[0].data);
        }
        if (primary.length == 0) {
            if (!_shouldTryDefault(state.coinType)) return (lookup, nul, "");
            v = _lookupPrimary(state.addr, EVM_BIT, state.coinType0, state.batchedGateways);
        } else {
            v = callResolve(
                ENSDNSCoder.dnsEncode(string(primary)),
                _makeCalls(state.coinType0, state.coinType == EVM_BIT && state.coinType0 != EVM_BIT),
                state.batchedGateways,
                this.reverseCallback2.selector,
                abi.encode(Reverse2(state.addr, state.coinType, state.batchedGateways, lookup))
            );
        }
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function _makeCalls(uint256 coinType, bool useFallback) internal pure returns (bytes[] memory calls) {
        calls = new bytes[](useFallback ? 4 : 1);
        calls[0] = abi.encodeCall(IAddressResolver.addr, (0, coinType));
        if (useFallback) {
            calls[1] = abi.encodeCall(IAddressResolver.addr, (0, EVM_BIT));
            // this makes sense only if default can only be set by eoa
            calls[2] = abi.encodeCall(IAddressResolver.addr, (0, COIN_TYPE_ETH));
            calls[3] = abi.encodeCall(IAddrResolver.addr, (0));
        }
    }

    struct Reverse2 {
        bytes addr;
        uint256 coinType;
        string[] batchedGateways;
        Lookup rev;
    }

    function reverseCallback2(Lookup calldata lookup, Response[] calldata res, bytes memory carry)
        external
        pure
        returns (Lookup memory rev, Lookup memory fwd, bytes memory answer)
    {
        Reverse2 memory state = abi.decode(carry, (Reverse2));
        rev = state.rev;
        fwd = lookup;
        if (fwd.ok) {
            for (uint256 i; i < res.length; i++) {
                Response memory r = res[i];
                if ((r.bits & ResponseBits.ERROR) == 0) {
                    bytes memory v = SafeDecoder.decodeAddress(bytes4(r.call), r.data);
                    if (v.length != 0) {
                        answer = v;
                        break;
                    }
                }
            }
        }
    }

    function _shouldTryDefault(uint256 coinType) internal pure returns (bool) {
        return coinType == COIN_TYPE_ETH
            || (uint32(coinType) == coinType && (coinType & EVM_BIT) != 0 && coinType != EVM_BIT);
    }

}
