// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC165, IERC165} from "./ERC165.sol";
import {ENS} from "@ensdomains/ens-contracts/contracts/registry/ENS.sol";
import {IExtendedResolver} from "@ensdomains/ens-contracts/contracts/resolvers/profiles/IExtendedResolver.sol";
import {BytesUtils} from "@ensdomains/ens-contracts/contracts/utils/BytesUtils.sol";
import {OffchainLookup, OffchainLookupTuple, CCIPReadProtocol} from "./CCIPReadProtocol.sol";
import {IBatchedGateway, BatchedGatewayQuery} from "./IBatchedGateway.sol";
import {IResolveMulticall} from "./IResolveMulticall.sol";
import {IUR, Lookup, Response, ResponseBits, LengthMismatch} from "./IUR.sol";

contract UR is IUR, IERC165 {
    address public immutable registry;
    string[] public batchedGateways;

    constructor(address ens, string[] memory gateways) {
        registry = ens;
        batchedGateways = gateways;
    }

    function supportsInterface(bytes4 x) external pure returns (bool) {
        return type(IERC165).interfaceId == x || type(IUR).interfaceId == x;
    }

    function lookupName(bytes memory dns) public view returns (Lookup memory lookup) {
        // https://docs.ens.domains/ensip/10
        lookup.dns = dns;
        lookup.node = lookup.basenode = BytesUtils.namehash(dns, 0);
        while (true) {
            lookup.resolver = ENS(registry).resolver(lookup.basenode);
            if (lookup.resolver != address(0)) break;
            uint256 len = uint8(dns[lookup.offset]);
            if (len == 0) return lookup;
            lookup.offset += 1 + len;
            lookup.basenode = BytesUtils.namehash(dns, lookup.offset);
        }
        if (ERC165.supportsInterface(lookup.resolver, type(IExtendedResolver).interfaceId)) {
            lookup.extended = true;
        } else if (lookup.offset != 0) {
            lookup.resolver = address(0);
        }
    }

    function resolve(bytes memory dns, bytes[] memory calls, string[] memory gateways)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        lookup = lookupName(dns);
        if (lookup.resolver == address(0)) return (lookup, res);
        res = new Response[](calls.length); // create result storage
        if (gateways.length == 0) gateways = batchedGateways; // use default
        bytes[] memory offchainCalls = new bytes[](calls.length);
        uint256 offchain; // count how many offchain
        for (uint256 i; i < res.length; i++) {
            bytes memory call = _injectNode(calls[i], lookup.node);
            (bool ok, bytes memory v) = _callResolver(lookup, call);
            Response memory r = res[i];
            r.call = call; // remember calldata (post-inject, pre-resolve)
            r.data = v;
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                r.bits |= ResponseBits.OFFCHAIN | ResponseBits.BATCHED;
                offchainCalls[offchain++] = call;
            } else {
                if (!ok) r.bits |= ResponseBits.ERROR;
                r.bits |= ResponseBits.RESOLVED;
            }
        }
        if (offchain > 1) {
            assembly {
                mstore(offchainCalls, offchain)
            }
            (bool ok, bytes memory v) =
                _callResolver(lookup, abi.encodeCall(IResolveMulticall.multicall, (offchainCalls)));
            if (!ok && bytes4(v) == OffchainLookup.selector) {
                Response[] memory multi = new Response[](1);
                multi[0].data = v;
                _revertOffchain(lookup, multi, res, gateways);
            }
        }
        _revertOffchain(lookup, res, new Response[](0), gateways);
    }

    function _callResolver(Lookup memory lookup, bytes memory call) internal view returns (bool ok, bytes memory v) {
        if (lookup.extended) call = abi.encodeCall(IExtendedResolver.resolve, (lookup.dns, call)); // wrap
        (ok, v) = lookup.resolver.staticcall(call); // call it
        if (ok && lookup.extended) v = abi.decode(v, (bytes)); // unwrap
    }

    function _revertOffchain(
        Lookup memory lookup,
        Response[] memory res,
        Response[] memory alt,
        string[] memory gateways
    ) internal view {
        BatchedGatewayQuery[] memory queries = new BatchedGatewayQuery[](res.length);
        uint256 missing;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) == 0) {
                OffchainLookupTuple memory x = CCIPReadProtocol.decode(r.data);
                queries[missing++] = BatchedGatewayQuery(x.sender, x.gateways, x.request);
            }
        }
        if (missing > 0) {
            assembly {
                mstore(queries, missing)
            }
            revert OffchainLookup(
                address(this),
                gateways,
                abi.encodeCall(IBatchedGateway.query, (queries)),
                this.resolveCallback.selector,
                abi.encode(lookup, res, alt, gateways) // batchedCarry
            );
        }
    }

    function resolveCallback(bytes memory ccip, bytes memory batchedCarry)
        external
        view
        returns (Lookup memory lookup, Response[] memory res)
    {
        Response[] memory alt;
        string[] memory gateways;
        (lookup, res, alt, gateways) = abi.decode(batchedCarry, (Lookup, Response[], Response[], string[]));
        (bool[] memory failures, bytes[] memory responses) = abi.decode(ccip, (bool[], bytes[]));
        if (failures.length != responses.length) revert LengthMismatch();
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) == 0) {
                bytes memory v = responses[expected];
                if (failures[expected++]) {
                    r.bits |= ResponseBits.RESOLVED | ResponseBits.ERROR; // ccip-read failed
                } else {
                    OffchainLookupTuple memory x = CCIPReadProtocol.decode(r.data);
                    bool ok;
                    (ok, v) = x.sender.staticcall(abi.encodeWithSelector(x.selector, v, x.carry));
                    if (ok) {
                        if (bytes4(x.request) == IExtendedResolver.resolve.selector) {
                            v = abi.decode(v, (bytes)); // unwrap
                        }
                        r.bits |= ResponseBits.RESOLVED;
                    } else if (bytes4(v) != OffchainLookup.selector) {
                        r.bits |= ResponseBits.RESOLVED | ResponseBits.ERROR; // callback failed
                    }
                }
                r.data = v;
            }
        }
        if (expected != responses.length) revert LengthMismatch();
        _revertOffchain(lookup, res, alt, gateways);
        if (alt.length > 0) {
            if ((res[0].bits & ResponseBits.ERROR) != 0) {
                _revertOffchain(lookup, alt, new Response[](0), gateways); // try separate
            } else {
                _decodeMulticall(res[0].data, alt);
                res = alt;
            }
        }
    }

    // utils
    function _decodeMulticall(bytes memory encoded, Response[] memory res) internal pure {
        bytes[] memory m = abi.decode(encoded, (bytes[]));
        uint256 expected;
        for (uint256 i; i < res.length; i++) {
            Response memory r = res[i];
            if ((r.bits & ResponseBits.RESOLVED) == 0) {
                bytes memory v = m[expected++];
                r.data = v;
                if ((v.length & 31) != 0) r.bits |= ResponseBits.ERROR;
                r.bits |= ResponseBits.RESOLVED;
            }
        }
        if (expected != m.length) revert LengthMismatch();
    }

    function _injectNode(bytes memory v, bytes32 node) internal pure returns (bytes memory) {
        bytes32 node0;
        assembly {
            node0 := mload(add(v, 36)) // old node
        }
        if (node0 == bytes32(0)) {
            v = abi.encodePacked(v); // make copy
            assembly {
                mstore(add(v, 36), node) // inject new node
            }
        }
        return v;
    }
}
