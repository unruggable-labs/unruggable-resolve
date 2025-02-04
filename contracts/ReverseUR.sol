// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {INameResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/INameResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {CCIPReader} from "@unruggable/CCIPReader.sol/contracts/CCIPReader.sol";
import {IReverseUR} from "./IReverseUR.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {ReverseName} from "./ReverseName.sol";
import {DNSCoder} from "./DNSCoder.sol";
import {SafeDecoder} from "./SafeDecoder.sol";
import {EVM_BIT, COIN_TYPE_ETH} from "./Constants.sol";

contract ReverseUR is IReverseUR, CCIPReader {
    IUR public immutable ur;

    constructor(IUR _ur) {
        ur = _ur;
    }

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

    function reverseName(bytes memory addr, uint256 coinType) external pure returns (string memory) {
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
        return ccipRead(
            address(ur),
            abi.encodeCall(IUR.resolve, (DNSCoder.encode(name), calls, batchedGateways)),
            this.reverseCallback1.selector,
            abi.encode(ReverseCarry(addr, coinType, coinType0, batchedGateways))
        );
    }

    struct ReverseCarry {
        bytes addr;
        uint256 coinType;
        uint256 coinType0;
        string[] batchedGateways;
    }

    function reverseCallback1(bytes calldata ccip, bytes calldata carry)
        external
        view
        returns (Lookup memory lookup, Lookup memory nul, bytes memory v)
    {
        Response[] memory res;
        (lookup, res) = abi.decode(ccip, (Lookup, Response[]));
        ReverseCarry memory state = abi.decode(carry, (ReverseCarry));
        bytes memory primary;
        if (lookup.resolver != address(0) && (res[0].bits & ResponseBits.ERROR) == 0) {
            primary = SafeDecoder.decodeBytes(res[0].data);
        }
        if (primary.length == 0) {
            if (!_shouldTryDefault(state.coinType)) return (lookup, nul, "");
            v = _lookupPrimary(state.addr, EVM_BIT, state.coinType0, state.batchedGateways);
        } else {
            v = ccipRead(
                address(ur),
                abi.encodeCall(
                    IUR.resolve,
                    (
                        DNSCoder.encode(string(primary)),
                        _makeCalls(state.coinType0, state.coinType == EVM_BIT && state.coinType0 != EVM_BIT),
                        state.batchedGateways
                    )
                ),
                this.reverseCallback2.selector,
                abi.encode(lookup)
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

    function reverseCallback2(bytes calldata ccip, bytes calldata carry)
        external
        pure
        returns (Lookup memory rev, Lookup memory fwd, bytes memory answer)
    {
        Response[] memory res;
        (fwd, res) = abi.decode(ccip, (Lookup, Response[]));
        rev = abi.decode(carry, (Lookup));
        if (fwd.resolver != address(0)) {
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
