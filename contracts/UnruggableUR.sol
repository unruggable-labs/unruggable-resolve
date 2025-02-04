// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ITextResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/ITextResolver.sol";
import {IAddressResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddressResolver.sol";
import {IAddrResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IAddrResolver.sol";
import {IContentHashResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IContentHashResolver.sol";
import {CCIPReader} from "@unruggable/CCIPReader.sol/contracts/CCIPReader.sol";
import {IUR, Lookup, Response, ResponseBits} from "./IUR.sol";
import {DNSCoder} from "./DNSCoder.sol";
import {SafeDecoder} from "./SafeDecoder.sol";
import {COIN_TYPE_ETH} from "./Constants.sol";

contract UnruggableUR is CCIPReader {
    IUR public immutable ur;

    constructor(IUR _ur) {
        ur = _ur;
    }

    function resolve(
        string memory name,
        string[] memory keys,
        uint256[] memory coins,
        bool useContenthash,
        string[] memory gateways
    )
        external
        view
        returns (Lookup memory lookup, string[] memory texts, bytes[] memory addrs, bytes memory contenthash)
    {
        lookup = ur.lookupName(DNSCoder.encode(name));
        if (lookup.resolver == address(0)) return (lookup, texts, addrs, contenthash);
        bytes[] memory calls = new bytes[](keys.length + coins.length + (useContenthash ? 1 : 0));
        {
            uint256 pos;
            for (uint256 i; i < keys.length; i++) {
                calls[pos++] = abi.encodeCall(ITextResolver.text, (0, keys[i]));
            }
            for (uint256 i; i < coins.length; i++) {
                uint256 coinType = coins[i];
                calls[pos++] = coinType == COIN_TYPE_ETH
                    ? abi.encodeCall(IAddrResolver.addr, (0))
                    : abi.encodeCall(IAddressResolver.addr, (0, coinType));
            }
            if (useContenthash) {
                calls[pos++] = abi.encodeCall(IContentHashResolver.contenthash, (0));
            }
        }
        bytes memory v = ccipRead(
            address(ur),
            abi.encodeCall(IUR.resolve, (lookup.dns, calls, gateways)),
            this.resolveCallback.selector,
            abi.encode(keys.length, coins.length, useContenthash)
        );
        assembly {
            return(add(v, 32), mload(v))
        }
    }

    function resolveCallback(bytes calldata ccip, bytes calldata carry)
        external
        pure
        returns (Lookup memory lookup, string[] memory texts, bytes[] memory addrs, bytes memory contenthash)
    {
        Response[] memory res;
        (lookup, res) = abi.decode(ccip, (Lookup, Response[]));
        (uint256 textCount, uint256 addrCount, bool useContenthash) = abi.decode(carry, (uint256, uint256, bool));
        texts = new string[](textCount);
        addrs = new bytes[](addrCount);
        uint256 pos;
        for (uint256 i; i < textCount; i++) {
            Response memory r = res[pos++];
            if ((r.bits & ResponseBits.ERROR) == 0) {
                texts[i] = string(SafeDecoder.decodeBytes(r.data));
            }
        }
        for (uint256 i; i < addrCount; i++) {
            Response memory r = res[pos++];
            if ((r.bits & ResponseBits.ERROR) == 0) {
                addrs[i] = SafeDecoder.decodeAddress(bytes4(r.call), r.data);
            }
        }
        if (useContenthash && (res[pos].bits & ResponseBits.ERROR) == 0) {
            contenthash = SafeDecoder.decodeBytes(res[pos].data);
        }
    }
}
